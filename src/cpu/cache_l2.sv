// =============================================================================
// cache_l2.sv — L2 Unified Cache
// =============================================================================
// Size         : 16 KB
// Associativity: 4-way set-associative
// Sets         : 128
// Line size    : 32 bytes (8 x 32-bit words = 256 bits)
// Replacement  : Pseudo-LRU — 3-bit binary tree per set (see diagram below)
// Write policy : Write-back only (no write-allocate — that is L1's job)
//
// Unlike L1, this module always transfers full 256-bit cache lines. It never
// deals with individual words; cache_ctrl is responsible for extracting the
// word that L1 actually needs from the returned line.
//
// Address breakdown (32-bit byte address):
//   [31:12]  tag        (20 bits)
//   [11:5]   set index  (7 bits → 128 sets)
//   [4:0]    offset     (5 bits — not used here, handled by cache_ctrl)
//
// -----------------------------------------------------------------------------
// Pseudo-LRU replacement policy (3-node binary tree for 4 ways):
//
//          b[2]
//         /    \
//       b[1]   b[0]
//       / \    / \
//      w0  w1 w2  w3
//
// Each bit points toward the MRU side, so the LRU way is found by following
// the bits in the opposite direction:
//   b[2]=0 → go left  → b[1]=0: evict w0,  b[1]=1: evict w1
//   b[2]=1 → go right → b[0]=0: evict w2,  b[0]=1: evict w3
//
// After accessing way X, update the bits to point *away* from X:
//   w0 accessed → b[2]=1, b[1]=1
//   w1 accessed → b[2]=1, b[1]=0
//   w2 accessed → b[2]=0, b[0]=1
//   w3 accessed → b[2]=0, b[0]=0
// -----------------------------------------------------------------------------
//
// Interface (driven by cache_ctrl):
//
//   Combinational lookup:
//     req_addr       → address to look up (line granularity)
//     hit            → 1 if the line is in L2
//     hit_way        → 2-bit way index of the hit
//     hit_rdata_line → full 256-bit line content (valid only when hit=1)
//     victim_dirty   → 1 if the PLRU victim has unsaved data
//     victim_addr    → base address of the victim line
//     victim_data    → full 256-bit content of the victim
//
//   Registered operations:
//     do_fill        → install a line fetched from main memory (goes into PLRU victim way)
//     fill_addr      → base address of the incoming line
//     fill_data      → 256-bit line data
//
//     do_write_line  → update an existing L2 line (write-back from a dirty L1 eviction)
//     wline_addr     → base address of the line to update
//     wline_data     → new 256-bit content
//
//     do_lru_update  → update PLRU after an L2 hit (no data written)
//     lru_set        → 7-bit set index
//     lru_way        → 2-bit way that was just accessed
// =============================================================================

module cache_l2 #(
    parameter int XLEN        = 32,
    parameter int SETS        = 128,     // 2^7
    parameter int WAYS        = 4,
    parameter int LINE_WORDS  = 8,
    parameter int LINE_BITS   = LINE_WORDS * 32   // 256 bits per cache line
)(
    input  logic clk,
    input  logic rst,

    // -- Combinational lookup (same-cycle response) ------------------------
    input  logic [XLEN-1:0]       req_addr,

    output logic                  hit,
    output logic [1:0]            hit_way,
    output logic [LINE_BITS-1:0]  hit_rdata_line,
    output logic                  victim_dirty,
    output logic [XLEN-1:0]       victim_addr,
    output logic [LINE_BITS-1:0]  victim_data,

    // -- Fill (bring a line from main memory into L2) ----------------------
    input  logic                  do_fill,
    input  logic [XLEN-1:0]       fill_addr,
    input  logic [LINE_BITS-1:0]  fill_data,

    // -- Write-line (write-back a dirty L1 eviction into L2) --------------
    input  logic                  do_write_line,
    input  logic [XLEN-1:0]       wline_addr,
    input  logic [LINE_BITS-1:0]  wline_data,

    // -- PLRU update (after an L2 read hit, no data written) --------------
    input  logic                  do_lru_update,
    input  logic [6:0]            lru_set,
    input  logic [1:0]            lru_way
);

    // -- Address field widths ---------------------------------------------
    localparam int BYTE_ALIGN_BITS = 2;
    localparam int OFFSET_BITS     = $clog2(LINE_WORDS) + BYTE_ALIGN_BITS;  // 5 bits
    localparam int INDEX_BITS      = $clog2(SETS);                           // 7 bits
    localparam int TAG_BITS        = XLEN - INDEX_BITS - OFFSET_BITS;        // 20 bits

    // -- Storage arrays ---------------------------------------------------
    logic                  valid [WAYS][SETS];
    logic                  dirty [WAYS][SETS];
    logic [TAG_BITS-1:0]   tags  [WAYS][SETS];
    logic [LINE_BITS-1:0]  data  [WAYS][SETS];
    logic [2:0]            plru  [SETS];  // 3-bit PLRU tree per set (unpacked array)

    // -- Break req_addr into tag and set index ----------------------------
    logic [TAG_BITS-1:0]   req_tag;
    logic [INDEX_BITS-1:0] req_index;

    assign req_tag   = req_addr[XLEN-1 : INDEX_BITS+OFFSET_BITS];
    assign req_index = req_addr[INDEX_BITS+OFFSET_BITS-1 : OFFSET_BITS];

    // -- Per-way extraction for req_index ---------------------------------
    // generate gives each iteration a constant 'gw', so [gw][req_index]
    // has a constant first index — Icarus requires this for 2-D array reads
    // inside continuous assignments.
    logic                  req_valid_w [WAYS];
    logic                  req_dirty_w [WAYS];
    logic [TAG_BITS-1:0]   req_tag_w   [WAYS];
    logic [LINE_BITS-1:0]  req_data_w  [WAYS];

    genvar gw;
    generate
        for (gw = 0; gw < WAYS; gw++) begin : gen_req_extract
            assign req_valid_w[gw] = valid[gw][req_index];
            assign req_dirty_w[gw] = dirty[gw][req_index];
            assign req_tag_w[gw]   = tags [gw][req_index];
            assign req_data_w[gw]  = data [gw][req_index];
        end
    endgenerate

    // -- Hit detection (purely combinational) -----------------------------
    logic hit_w [WAYS];
    assign hit_w[0] = req_valid_w[0] && (req_tag_w[0] == req_tag);
    assign hit_w[1] = req_valid_w[1] && (req_tag_w[1] == req_tag);
    assign hit_w[2] = req_valid_w[2] && (req_tag_w[2] == req_tag);
    assign hit_w[3] = req_valid_w[3] && (req_tag_w[3] == req_tag);

    assign hit = hit_w[0] | hit_w[1] | hit_w[2] | hit_w[3];

    // Priority encoder: higher way numbers win on the (impossible) case of
    // multiple hits. hit_way and hit_rdata_line are only meaningful when hit=1.
    assign hit_way = hit_w[3] ? 2'd3 : hit_w[2] ? 2'd2 : hit_w[1] ? 2'd1 : 2'd0;

    assign hit_rdata_line = hit_w[3] ? req_data_w[3] :
                            hit_w[2] ? req_data_w[2] :
                            hit_w[1] ? req_data_w[1] : req_data_w[0];

    // -- Victim selection via PLRU ----------------------------------------
    // Read the PLRU tree for the requested set (1-D unpacked array read —
    // variable index is fine in a continuous assign in Icarus).
    // Then decode the tree to find the LRU way.
    logic [2:0]  req_plru;
    logic [1:0]  victim_way;

    assign req_plru   = plru[req_index];
    assign victim_way = !req_plru[2] ? (req_plru[1] ? 2'd1 : 2'd0)
                                     : (req_plru[0] ? 2'd3 : 2'd2);

    // Use explicit muxes — victim_way is a 2-bit signal, not an array index.
    assign victim_dirty = (victim_way == 2'd3) ? req_dirty_w[3] :
                          (victim_way == 2'd2) ? req_dirty_w[2] :
                          (victim_way == 2'd1) ? req_dirty_w[1] : req_dirty_w[0];

    assign victim_addr  = (victim_way == 2'd3) ? {req_tag_w[3], req_index, {OFFSET_BITS{1'b0}}} :
                          (victim_way == 2'd2) ? {req_tag_w[2], req_index, {OFFSET_BITS{1'b0}}} :
                          (victim_way == 2'd1) ? {req_tag_w[1], req_index, {OFFSET_BITS{1'b0}}} :
                                                 {req_tag_w[0], req_index, {OFFSET_BITS{1'b0}}};

    assign victim_data  = (victim_way == 2'd3) ? req_data_w[3] :
                          (victim_way == 2'd2) ? req_data_w[2] :
                          (victim_way == 2'd1) ? req_data_w[1] : req_data_w[0];

    // -- PLRU update function ---------------------------------------------
    // Returns the new 3-bit tree value after accessing 'used_way'.
    // Only the two bits on the path to that way are updated; the other bit
    // is left unchanged (it belongs to the other subtree and is irrelevant).
    function automatic logic [2:0] plru_update(
        input logic [2:0] old_plru,
        input logic [1:0] used_way
    );
        logic [2:0] np;
        np = old_plru;
        case (used_way)
            2'd0: begin np[2] = 1'b1; np[1] = 1'b1; end  // w0: steer both bits away from w0
            2'd1: begin np[2] = 1'b1; np[1] = 1'b0; end  // w1: steer away from w1
            2'd2: begin np[2] = 1'b0; np[0] = 1'b1; end  // w2: steer away from w2
            2'd3: begin np[2] = 1'b0; np[0] = 1'b0; end  // w3: steer away from w3
            default: np = old_plru;
        endcase
        return np;
    endfunction

    // -- Helper signals for registered operations -------------------------
    logic [INDEX_BITS-1:0] fill_index;
    logic [TAG_BITS-1:0]   fill_tag;
    logic [INDEX_BITS-1:0] wline_index;
    logic [TAG_BITS-1:0]   wline_tag;

    assign fill_index  = fill_addr[INDEX_BITS+OFFSET_BITS-1 : OFFSET_BITS];
    assign fill_tag    = fill_addr[XLEN-1 : INDEX_BITS+OFFSET_BITS];
    assign wline_index = wline_addr[INDEX_BITS+OFFSET_BITS-1 : OFFSET_BITS];
    assign wline_tag   = wline_addr[XLEN-1 : INDEX_BITS+OFFSET_BITS];

    // -- PLRU victim for fill_index ---------------------------------------
    // Computed separately from the req_index victim so a fill can target
    // a different set than the current lookup without conflict.
    logic [2:0]  fill_plru;
    logic [1:0]  fill_victim_way;

    assign fill_plru       = plru[fill_index];
    assign fill_victim_way = !fill_plru[2] ? (fill_plru[1] ? 2'd1 : 2'd0)
                                           : (fill_plru[0] ? 2'd3 : 2'd2);

    // -- Find the way that holds wline_addr (for do_write_line) -----------
    logic                wl_valid_w [WAYS];
    logic [TAG_BITS-1:0] wl_tag_w   [WAYS];
    generate
        for (gw = 0; gw < WAYS; gw++) begin : gen_wl_extract
            assign wl_valid_w[gw] = valid[gw][wline_index];
            assign wl_tag_w[gw]   = tags [gw][wline_index];
        end
    endgenerate

    logic [1:0] wline_way;
    assign wline_way = (wl_valid_w[3] && wl_tag_w[3] == wline_tag) ? 2'd3 :
                       (wl_valid_w[2] && wl_tag_w[2] == wline_tag) ? 2'd2 :
                       (wl_valid_w[1] && wl_tag_w[1] == wline_tag) ? 2'd1 : 2'd0;

    // -- Registered operations --------------------------------------------
    integer s, w;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (w = 0; w < WAYS; w++) begin
                for (s = 0; s < SETS; s++) begin
                    valid[w][s] <= 1'b0;
                    dirty[w][s] <= 1'b0;
                    tags [w][s] <= '0;
                    data [w][s] <= '0;
                end
            end
            for (s = 0; s < SETS; s++)
                plru[s] <= 3'b000;

        end else begin

            // Fill: install a line from main memory into the PLRU victim way.
            // The line comes in clean; it only becomes dirty if L1 later
            // evicts a modified line back into this L2 entry via do_write_line.
            // case statement keeps the first array index constant (Icarus req.).
            if (do_fill) begin
                case (fill_victim_way)
                    2'd0: begin valid[0][fill_index]<=1'b1; dirty[0][fill_index]<=1'b0; tags[0][fill_index]<=fill_tag; data[0][fill_index]<=fill_data; end
                    2'd1: begin valid[1][fill_index]<=1'b1; dirty[1][fill_index]<=1'b0; tags[1][fill_index]<=fill_tag; data[1][fill_index]<=fill_data; end
                    2'd2: begin valid[2][fill_index]<=1'b1; dirty[2][fill_index]<=1'b0; tags[2][fill_index]<=fill_tag; data[2][fill_index]<=fill_data; end
                    2'd3: begin valid[3][fill_index]<=1'b1; dirty[3][fill_index]<=1'b0; tags[3][fill_index]<=fill_tag; data[3][fill_index]<=fill_data; end
                endcase
                plru[fill_index] <= plru_update(plru[fill_index], fill_victim_way);
            end

            // Write-line: a dirty L1 line is being evicted and its data needs
            // to be saved here. We mark the L2 line dirty because it now holds
            // data that hasn't reached main memory yet.
            if (do_write_line) begin
                case (wline_way)
                    2'd0: begin data[0][wline_index]<=wline_data; dirty[0][wline_index]<=1'b1; end
                    2'd1: begin data[1][wline_index]<=wline_data; dirty[1][wline_index]<=1'b1; end
                    2'd2: begin data[2][wline_index]<=wline_data; dirty[2][wline_index]<=1'b1; end
                    2'd3: begin data[3][wline_index]<=wline_data; dirty[3][wline_index]<=1'b1; end
                endcase
                plru[wline_index] <= plru_update(plru[wline_index], wline_way);
            end

            // PLRU update after a read hit (cache_ctrl drives this when the
            // pipeline just read a line that was already in L2).
            if (do_lru_update) begin
                plru[lru_set] <= plru_update(plru[lru_set], lru_way);
            end

        end
    end

endmodule
