// =============================================================================
// cache_l1d.sv — L1 Data Cache
// =============================================================================
// Size         : 4 KB
// Associativity: 2-way set-associative
// Sets         : 64
// Line size    : 32 bytes (8 x 32-bit words = 256 bits)
// Replacement  : LRU — 1 bit per set. 0 means way 0 was used last (replace way 0 next),
//                1 means way 1 was used last (replace way 1 next).
// Write policy : Write-back + Write-allocate
//                On a store miss, allocate a new line (fill), then write to it.
//                Dirty lines are only written back to L2 when evicted.
//
// Address breakdown (32-bit byte address):
//   [31:11]  tag         (21 bits)
//   [10:5]   set index   (6 bits  → 64 sets)
//   [4:2]    word offset (3 bits  → 8 words per line)
//   [1:0]    byte offset (ignored — all accesses are word-aligned)
//
// Interface (driven by cache_ctrl):
//
//   Combinational lookup — results are available the same cycle req_addr is driven:
//     req_addr     → address to look up
//     hit          → 1 if the line is currently cached
//     hit_way      → which way holds the hit (0 or 1)
//     hit_rdata    → the requested 32-bit word (only valid when hit=1)
//     victim_dirty → 1 if the LRU line has unsaved data (needs write-back before eviction)
//     victim_addr  → base address of the line that would be evicted
//     victim_data  → full 256-bit content of that line
//
//   Registered operations — take effect on the next rising clock edge:
//     do_fill       → load a new line (fetched from L2/memory) into the cache
//     fill_way      → which way to write into (decided by cache_ctrl)
//     fill_addr     → base address of the incoming line
//     fill_data     → 256-bit line data to store
//
//     do_write_hit  → update a single word inside a cached line (store hit)
//     write_way     → way that holds the line being written
//     write_addr    → full address (word offset lives in bits [4:2])
//     write_data    → 32-bit word to write
//
//     do_lru_update → update LRU after a read hit (no data write involved)
//     lru_set       → set index to update
//     lru_way       → way that was just accessed
// =============================================================================

module cache_l1d #(
    parameter int XLEN        = 32,
    parameter int SETS        = 64,      // 2^6
    parameter int WAYS        = 2,
    parameter int LINE_WORDS  = 8,       // 32 bytes / 4 bytes per word
    parameter int LINE_BITS   = LINE_WORDS * 32  // 256 bits per cache line
)(
    input  logic clk,
    input  logic rst,

    // -- Combinational lookup (same-cycle response) ------------------------
    input  logic [XLEN-1:0]      req_addr,

    output logic                 hit,
    output logic                 hit_way,
    output logic [31:0]          hit_rdata,
    output logic                 victim_dirty,
    output logic                 victim_way,   // LRU way that would be evicted next
    output logic [XLEN-1:0]      victim_addr,
    output logic [LINE_BITS-1:0] victim_data,

    // -- Fill (bring a new line into the cache) ----------------------------
    input  logic                 do_fill,
    input  logic                 fill_way,
    input  logic [XLEN-1:0]      fill_addr,
    input  logic [LINE_BITS-1:0] fill_data,

    // -- Write-hit (store that hits a cached line) -------------------------
    input  logic                 do_write_hit,
    input  logic                 write_way,
    input  logic [XLEN-1:0]      write_addr,
    input  logic [31:0]          write_data,

    // -- LRU update (after a read hit, no data written) -------------------
    input  logic                    do_lru_update,
    input  logic [$clog2(SETS)-1:0] lru_set,
    input  logic                    lru_way
);

    // -- Address field widths ---------------------------------------------
    localparam int BYTE_ALIGN_BITS = 2;
    localparam int OFFSET_BITS     = $clog2(LINE_WORDS) + BYTE_ALIGN_BITS;  // 5 bits
    localparam int INDEX_BITS      = $clog2(SETS);                           // 6 bits
    localparam int TAG_BITS        = XLEN - INDEX_BITS - OFFSET_BITS;        // 21 bits

    // -- Storage arrays ---------------------------------------------------
    // Each entry is indexed as [way][set].
    logic                  valid [WAYS][SETS];
    logic                  dirty [WAYS][SETS];  // set when a word is written; cleared on fill
    logic [TAG_BITS-1:0]   tags  [WAYS][SETS];
    logic [LINE_BITS-1:0]  data  [WAYS][SETS];
    logic                  lru   [SETS];  // LRU bit: 0 = evict way 0 next, 1 = evict way 1 next

    // -- Break req_addr into tag / index / word ---------------------------
    logic [TAG_BITS-1:0]           req_tag;
    logic [INDEX_BITS-1:0]         req_index;
    logic [$clog2(LINE_WORDS)-1:0] req_word;

    assign req_tag   = req_addr[XLEN-1 : INDEX_BITS+OFFSET_BITS];
    assign req_index = req_addr[INDEX_BITS+OFFSET_BITS-1 : OFFSET_BITS];
    assign req_word  = req_addr[OFFSET_BITS-1 : 2];

    // -- Hit detection (purely combinational) -----------------------------
    // Check both ways in parallel. Way 0 takes priority if both somehow hit
    // (shouldn't happen in a correct implementation, but safe to handle).
    logic hit0, hit1;

    assign hit0 = valid[0][req_index] && (tags[0][req_index] == req_tag);
    assign hit1 = valid[1][req_index] && (tags[1][req_index] == req_tag);
    assign hit  = hit0 | hit1;

    assign hit_way   = hit1;  // way 1 wins if both hit; way 0 is the default
    assign hit_rdata = hit1
        ? data[1][req_index][req_word*32 +: 32]
        : data[0][req_index][req_word*32 +: 32];

    // -- Victim selection -------------------------------------------------
    // The LRU bit tells us which way is the least recently used and should
    // be replaced on the next fill. If the victim is dirty, cache_ctrl must
    // write it back to L2 before overwriting it.
    // victim_way is exposed as an output so cache_ctrl can tell cache_l1d
    // exactly which way to target on the subsequent do_fill.
    assign victim_way = lru[req_index];

    // Use explicit ternary muxes here — Icarus Verilog does not support
    // using a logic signal as an unpacked array index inside assign.
    assign victim_dirty = victim_way ? dirty[1][req_index] : dirty[0][req_index];
    assign victim_addr  = victim_way
        ? {tags[1][req_index], req_index, {OFFSET_BITS{1'b0}}}
        : {tags[0][req_index], req_index, {OFFSET_BITS{1'b0}}};
    assign victim_data  = victim_way ? data[1][req_index] : data[0][req_index];

    // -- Helper signals for registered operations -------------------------
    // Pre-decode address fields from fill_addr and write_addr so the
    // always_ff block can use them directly without repeating slice logic.
    logic [INDEX_BITS-1:0]         fill_index;
    logic [TAG_BITS-1:0]           fill_tag;
    logic [$clog2(LINE_WORDS)-1:0] write_word;
    logic [INDEX_BITS-1:0]         write_index;

    assign fill_index  = fill_addr[INDEX_BITS+OFFSET_BITS-1 : OFFSET_BITS];
    assign fill_tag    = fill_addr[XLEN-1 : INDEX_BITS+OFFSET_BITS];
    assign write_word  = write_addr[OFFSET_BITS-1 : 2];
    assign write_index = write_addr[INDEX_BITS+OFFSET_BITS-1 : OFFSET_BITS];

    // -- Registered operations --------------------------------------------
    integer s, w;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            // Invalidate everything on reset. Dirty bits are also cleared so
            // no spurious write-backs happen after the first few cycles.
            for (w = 0; w < WAYS; w++) begin
                for (s = 0; s < SETS; s++) begin
                    valid[w][s] <= 1'b0;
                    dirty[w][s] <= 1'b0;
                    tags [w][s] <= '0;
                    data [w][s] <= '0;
                end
            end
            for (s = 0; s < SETS; s++)
                lru[s] <= 1'b0;

        end else begin

            // Fill: install a new line (from L2 or main memory) into the
            // selected way. The line comes in clean — any future stores will
            // set the dirty bit through do_write_hit.
            // Using if/else instead of array[fill_way][...] keeps the first
            // index constant, which Icarus requires for 2-D array writes.
            if (do_fill) begin
                if (fill_way) begin
                    valid[1][fill_index] <= 1'b1; dirty[1][fill_index] <= 1'b0;
                    tags [1][fill_index] <= fill_tag; data[1][fill_index] <= fill_data;
                end else begin
                    valid[0][fill_index] <= 1'b1; dirty[0][fill_index] <= 1'b0;
                    tags [0][fill_index] <= fill_tag; data[0][fill_index] <= fill_data;
                end
                lru[fill_index] <= ~fill_way;  // mark the filled way as MRU
            end

            // Write-hit: update a single word within an already-cached line.
            // Marks the line dirty so it will be written back to L2 on eviction.
            if (do_write_hit) begin
                if (write_way) begin
                    data [1][write_index][write_word*32 +: 32] <= write_data;
                    dirty[1][write_index]                       <= 1'b1;
                end else begin
                    data [0][write_index][write_word*32 +: 32] <= write_data;
                    dirty[0][write_index]                       <= 1'b1;
                end
                lru[write_index] <= ~write_way;  // this way was just used → mark as MRU
            end

            // LRU update after a read hit (cache_ctrl drives this when no
            // write is involved, so we only need to move the LRU pointer).
            if (do_lru_update) begin
                lru[lru_set] <= ~lru_way;
            end

        end
    end

endmodule
