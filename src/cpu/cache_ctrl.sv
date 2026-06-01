// =============================================================================
// cache_ctrl.sv — Cache Hierarchy Controller
// =============================================================================
// This module is the brain of the cache subsystem. It receives a memory
// request from the pipeline's MEM stage, resolves it against L1 → L2 →
// Main Memory in that order, and asserts cache_stall until the data is ready.
//
// When cache_enable = 0 the module is completely bypassed: every request goes
// straight to data_mem, there are no stalls, and the three cache arrays are
// never touched.
//
// FSM state diagram (cache_enable = 1):
//
//   IDLE ──L1 hit────────────────────────────────────────────────→ IDLE
//        ──L1 miss, victim clean──→ L2_LOOKUP
//        ──L1 miss, victim dirty──→ L1_WRITEBACK ──→ L2_LOOKUP
//
//   L2_LOOKUP ──L2 hit──────────────────────────────────→ L1_FILL
//             ──L2 miss, victim clean──→ MEM_FETCH
//             ──L2 miss, victim dirty──→ L2_WRITEBACK ──→ MEM_FETCH
//
//   MEM_FETCH (waits 25 cycles for main memory) ──→ L2_FILL ──→ L1_FILL
//
//   L1_FILL ──→ IDLE  (stall drops, pipeline resumes)
//
// Cycle costs (approximate, cache_enable = 1):
//   L1 hit         :  0 extra cycles  (resolved in IDLE)
//   L2 hit         :  2 extra cycles  (L2_LOOKUP + L1_FILL)
//   Main-mem fetch :  ≥29 extra cycles (L2_LOOKUP + MEM_FETCH×25 + L2_FILL + L1_FILL)
//   Each dirty eviction adds another 25-cycle main-memory write.
//
// Interface notes:
//   - All cache arrays (cache_l1d, cache_l2, main_mem_model) are instantiated
//     OUTSIDE this module and connected through explicit ports.  This module
//     only drives/reads those ports — it does not instantiate any sub-module.
//   - data_mem is the original pipeline memory; it is used as-is when
//     cache_enable = 0 so the existing CPU flow continues to work.
// =============================================================================

module cache_ctrl #(
    parameter int XLEN       = 32,
    parameter int LINE_WORDS = 8,
    parameter int LINE_BITS  = LINE_WORDS * 32,   // 256 bits per cache line
    parameter int L1_SETS    = 64,
    parameter int L2_SETS    = 128
)(
    input  logic clk,
    input  logic rst,

    // ── Pipeline interface ────────────────────────────────────────────────
    input  logic             cache_enable,  // 0 = bypass everything, use data_mem
    input  logic             mem_read,      // load  request from MEM stage
    input  logic             mem_write,     // store request from MEM stage
    input  logic [XLEN-1:0] addr,           // byte address from MEM stage
    input  logic [31:0]      write_data,    // data to store (mem_write = 1)
    output logic [31:0]      read_data,     // data returned to WB stage
    output logic             cache_stall,   // freeze the pipeline while busy

    // ── Data-memory bypass (active when cache_enable = 0) ─────────────────
    output logic             dm_read,
    output logic             dm_write,
    output logic [XLEN-1:0] dm_addr,
    output logic [31:0]      dm_write_data,
    input  logic [31:0]      dm_read_data,

    // ── L1D cache interface ───────────────────────────────────────────────
    output logic [XLEN-1:0]       l1_req_addr,
    input  logic                  l1_hit,
    input  logic                  l1_hit_way,
    input  logic [31:0]           l1_hit_rdata,
    input  logic                  l1_victim_dirty,
    input  logic                  l1_victim_way,    // LRU way to evict / fill into
    input  logic [XLEN-1:0]       l1_victim_addr,
    input  logic [LINE_BITS-1:0]  l1_victim_data,
    output logic                  l1_do_fill,
    output logic                  l1_fill_way,
    output logic [XLEN-1:0]       l1_fill_addr,
    output logic [LINE_BITS-1:0]  l1_fill_data,
    output logic                  l1_do_write_hit,
    output logic                  l1_write_way,
    output logic [XLEN-1:0]       l1_write_addr,
    output logic [31:0]           l1_write_data,
    output logic                  l1_do_lru_update,
    output logic [5:0]            l1_lru_set,
    output logic                  l1_lru_way,

    // ── L2 cache interface ────────────────────────────────────────────────
    output logic [XLEN-1:0]       l2_req_addr,
    input  logic                  l2_hit,
    input  logic [1:0]            l2_hit_way,
    input  logic [LINE_BITS-1:0]  l2_hit_rdata_line,
    input  logic                  l2_victim_dirty,
    input  logic [XLEN-1:0]       l2_victim_addr,
    input  logic [LINE_BITS-1:0]  l2_victim_data,
    output logic                  l2_do_fill,
    output logic [XLEN-1:0]       l2_fill_addr,
    output logic [LINE_BITS-1:0]  l2_fill_data,
    output logic                  l2_do_write_line,
    output logic [XLEN-1:0]       l2_wline_addr,
    output logic [LINE_BITS-1:0]  l2_wline_data,
    output logic                  l2_do_lru_update,
    output logic [6:0]            l2_lru_set,
    output logic [1:0]            l2_lru_way,

    // ── Main memory interface ─────────────────────────────────────────────
    output logic                  mm_req,
    output logic                  mm_we,
    output logic [XLEN-1:0]       mm_addr,
    output logic [LINE_BITS-1:0]  mm_wdata,
    input  logic                  mm_ready,
    input  logic [LINE_BITS-1:0]  mm_rdata
);

    // ── Address field constants ──────────────────────────────────────────
    localparam int OFFSET_BITS   = $clog2(LINE_WORDS) + 2;  // 5 bits [4:0]
    localparam int L1_INDEX_BITS = $clog2(L1_SETS);         // 6 bits [10:5]
    localparam int L2_INDEX_BITS = $clog2(L2_SETS);         // 7 bits [11:5]

    // Line-aligned address: clears the 5 offset bits.
    logic [XLEN-1:0] line_addr;
    assign line_addr = {addr[XLEN-1:OFFSET_BITS], {OFFSET_BITS{1'b0}}};

    // ── FSM state encoding ───────────────────────────────────────────────
    typedef enum logic [2:0] {
        IDLE,
        L1_WRITEBACK,  // write dirty L1 victim line into L2
        L2_LOOKUP,     // check whether the missed line is in L2
        L2_WRITEBACK,  // write dirty L2 victim line to main memory
        MEM_FETCH,     // fetch the missed line from main memory
        L2_FILL,       // install fetched line into L2
        L1_FILL        // install line into L1 (+ write word if it was a store miss)
    } state_t;

    state_t state;

    // ── Latched request info (captured at the moment of an L1 miss) ──────
    logic [XLEN-1:0]      lat_addr;          // original byte address
    logic [XLEN-1:0]      lat_line_addr;     // line-aligned version
    logic [31:0]           lat_wdata;         // store word (if mem_write)
    logic                  lat_mem_read;      // was this a load?
    logic                  lat_mem_write;     // was this a store?
    logic                  lat_l1_vway;       // which L1 way to evict / fill into
    logic [XLEN-1:0]       lat_l1_vaddr;     // L1 victim line address (for L2 write-line)
    logic [LINE_BITS-1:0]  lat_l1_vdata;     // L1 victim line data

    // ── Latched L2 miss info (captured in L2_LOOKUP when L2 misses) ──────
    logic [XLEN-1:0]       lat_l2_vaddr;     // L2 victim address  (for MM write-back)
    logic [LINE_BITS-1:0]  lat_l2_vdata;     // L2 victim data

    // ── Line to install in L1 (set in L2_LOOKUP on hit, or in MEM_FETCH) ─
    logic [LINE_BITS-1:0]  lat_fill_line;    // 256-bit line heading for L1
    logic                  lat_from_l2_hit;  // 1 = line came from L2 (not MM)
    logic [1:0]            lat_l2_hit_way;   // L2 way that was hit (for PLRU update)

    // ── Main-memory request tracking ─────────────────────────────────────
    // main_mem_model requires req to be a single-cycle pulse.
    // mm_req_sent goes high after we fire the pulse so we don't fire again.
    logic mm_req_sent;

    // ── Registered state transitions and latching ────────────────────────
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state           <= IDLE;
            lat_addr        <= '0;
            lat_line_addr   <= '0;
            lat_wdata       <= '0;
            lat_mem_read    <= 1'b0;
            lat_mem_write   <= 1'b0;
            lat_l1_vway     <= 1'b0;
            lat_l1_vaddr    <= '0;
            lat_l1_vdata    <= '0;
            lat_l2_vaddr    <= '0;
            lat_l2_vdata    <= '0;
            lat_fill_line   <= '0;
            lat_from_l2_hit <= 1'b0;
            lat_l2_hit_way  <= '0;
            mm_req_sent     <= 1'b0;
        end else begin

            case (state)

                // ── IDLE ─────────────────────────────────────────────────
                // Serve hits in one cycle. On a miss, latch everything we
                // need and pick the next state depending on L1 victim status.
                IDLE: begin
                    if (cache_enable && (mem_read || mem_write) && !l1_hit) begin
                        // Capture the request and the L1 victim info.
                        lat_addr      <= addr;
                        lat_line_addr <= line_addr;
                        lat_wdata     <= write_data;
                        lat_mem_read  <= mem_read;
                        lat_mem_write <= mem_write;
                        lat_l1_vway   <= l1_victim_way;
                        lat_l1_vaddr  <= l1_victim_addr;
                        lat_l1_vdata  <= l1_victim_data;
                        mm_req_sent   <= 1'b0;

                        if (l1_victim_dirty)
                            state <= L1_WRITEBACK;
                        else
                            state <= L2_LOOKUP;
                    end
                    // Hits are handled entirely by combinational outputs below.
                end

                // ── L1_WRITEBACK ─────────────────────────────────────────
                // Write the dirty L1 victim into L2 (do_write_line fires
                // combinationally this cycle; L2 registers it at posedge).
                // Always move on to check L2 next cycle.
                L1_WRITEBACK: begin
                    state <= L2_LOOKUP;
                end

                // ── L2_LOOKUP ────────────────────────────────────────────
                // L2 hit / miss is combinational and stable now.
                // Latch what we need and pick the path forward.
                L2_LOOKUP: begin
                    if (l2_hit) begin
                        lat_fill_line   <= l2_hit_rdata_line;
                        lat_from_l2_hit <= 1'b1;
                        lat_l2_hit_way  <= l2_hit_way;
                        state           <= L1_FILL;
                    end else begin
                        lat_l2_vaddr    <= l2_victim_addr;
                        lat_l2_vdata    <= l2_victim_data;
                        lat_from_l2_hit <= 1'b0;
                        if (l2_victim_dirty)
                            state <= L2_WRITEBACK;
                        else
                            state <= MEM_FETCH;
                    end
                end

                // ── L2_WRITEBACK ──────────────────────────────────────────
                // Send the dirty L2 victim to main memory (write-back).
                // mm_req fires for exactly one cycle, then we wait for ready.
                L2_WRITEBACK: begin
                    if (!mm_req_sent)
                        mm_req_sent <= 1'b1;
                    if (mm_ready) begin
                        mm_req_sent <= 1'b0;
                        state       <= MEM_FETCH;
                    end
                end

                // ── MEM_FETCH ─────────────────────────────────────────────
                // Fetch the missed cache line from main memory (25-cycle wait).
                // mm_req fires for exactly one cycle, then we wait for ready.
                MEM_FETCH: begin
                    if (!mm_req_sent)
                        mm_req_sent <= 1'b1;
                    if (mm_ready) begin
                        lat_fill_line <= mm_rdata;
                        mm_req_sent   <= 1'b0;
                        state         <= L2_FILL;
                    end
                end

                // ── L2_FILL ──────────────────────────────────────────────
                // Install the fetched line into L2 (do_fill fires this cycle;
                // L2 registers it at posedge). Move to L1_FILL next cycle.
                L2_FILL: begin
                    state <= L1_FILL;
                end

                // ── L1_FILL ──────────────────────────────────────────────
                // Install the line into L1. If the original request was a
                // store, also write the word (write-allocate). Drop the stall
                // by returning to IDLE next cycle.
                L1_FILL: begin
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

    // ── Mux: extract the requested word from a 256-bit fill line ─────────
    // Constant part-selects inside always_* are not supported by Icarus, so
    // this is written as a chain of continuous assigns with literal offsets.
    // lat_addr[4:2] selects which of the 8 words in the cache line we need.
    logic [31:0] w0, w1, w2, w3, w4, w5, w6, w7;
    assign w0 = lat_fill_line[  0 +: 32];
    assign w1 = lat_fill_line[ 32 +: 32];
    assign w2 = lat_fill_line[ 64 +: 32];
    assign w3 = lat_fill_line[ 96 +: 32];
    assign w4 = lat_fill_line[128 +: 32];
    assign w5 = lat_fill_line[160 +: 32];
    assign w6 = lat_fill_line[192 +: 32];
    assign w7 = lat_fill_line[224 +: 32];

    logic [31:0] fill_word;
    assign fill_word = (lat_addr[4:2] == 3'd7) ? w7 :
                       (lat_addr[4:2] == 3'd6) ? w6 :
                       (lat_addr[4:2] == 3'd5) ? w5 :
                       (lat_addr[4:2] == 3'd4) ? w4 :
                       (lat_addr[4:2] == 3'd3) ? w3 :
                       (lat_addr[4:2] == 3'd2) ? w2 :
                       (lat_addr[4:2] == 3'd1) ? w1 : w0;

    // ── read_data ─────────────────────────────────────────────────────────
    // Produced combinationally so the pipeline can capture it on the clock
    // edge when cache_stall finally drops (transitioning out of L1_FILL).
    always_comb begin
        if (!cache_enable)
            read_data = dm_read_data;
        else if (state == IDLE && l1_hit && mem_read)
            read_data = l1_hit_rdata;
        else if (state == L1_FILL && lat_mem_read)
            read_data = fill_word;
        else
            read_data = '0;
    end

    // ── cache_stall ───────────────────────────────────────────────────────
    // High whenever the pipeline must wait: either we're mid-FSM, or we're
    // in IDLE and have just detected an L1 miss (next cycle we leave IDLE).
    assign cache_stall = cache_enable && (
        (state != IDLE) ||
        ((mem_read || mem_write) && !l1_hit)
    );

    // ── Data-memory bypass ────────────────────────────────────────────────
    assign dm_read       = cache_enable ? 1'b0 : mem_read;
    assign dm_write      = cache_enable ? 1'b0 : mem_write;
    assign dm_addr       = addr;
    assign dm_write_data = write_data;

    // ── L1 req_addr ───────────────────────────────────────────────────────
    // In IDLE we present the live pipeline address; in all other states we
    // keep presenting the latched address so the combinational outputs from
    // cache_l1d remain stable throughout the miss-handling sequence.
    assign l1_req_addr = (state == IDLE) ? addr : lat_addr;

    // ── L1 write-hit (store that lands in a cached line) ──────────────────
    // Also fires in L1_FILL for write-allocate: the fill installs the clean
    // line and the write_hit simultaneously marks the one store word dirty.
    // cache_l1d handles both in the same always_ff block via non-blocking
    // assignments — the write_hit's dirty=1 overrides the fill's dirty=0.
    assign l1_do_write_hit = ((state == IDLE)   && cache_enable && mem_write && l1_hit) ||
                             ((state == L1_FILL) && lat_mem_write);
    assign l1_write_way    = (state == L1_FILL) ? lat_l1_vway : l1_hit_way;
    assign l1_write_addr   = (state == L1_FILL) ? lat_addr    : addr;
    assign l1_write_data   = (state == L1_FILL) ? lat_wdata   : write_data;

    // ── L1 LRU update (read hit — no data write needed) ───────────────────
    assign l1_do_lru_update = (state == IDLE) && cache_enable && mem_read && l1_hit;
    assign l1_lru_set       = addr[OFFSET_BITS + L1_INDEX_BITS - 1 : OFFSET_BITS];
    assign l1_lru_way       = l1_hit_way;

    // ── L1 fill (install line after a miss is resolved) ───────────────────
    assign l1_do_fill  = (state == L1_FILL);
    assign l1_fill_way = lat_l1_vway;    // overwrite the LRU victim way
    assign l1_fill_addr = lat_line_addr;
    assign l1_fill_data = lat_fill_line;

    // ── L2 req_addr ───────────────────────────────────────────────────────
    // Always the line-aligned version of the missed address.
    assign l2_req_addr = (state == IDLE) ? line_addr : lat_line_addr;

    // ── L2 write-line (dirty L1 eviction → update the L2 copy) ───────────
    // Fires during L1_WRITEBACK; L2 registers it at the posedge.
    assign l2_do_write_line = (state == L1_WRITEBACK);
    assign l2_wline_addr    = lat_l1_vaddr;
    assign l2_wline_data    = lat_l1_vdata;

    // ── L2 fill (install a line fetched from main memory) ─────────────────
    assign l2_do_fill  = (state == L2_FILL);
    assign l2_fill_addr = lat_line_addr;
    assign l2_fill_data = lat_fill_line;

    // ── L2 PLRU update (L2 read hit — data is forwarded to L1, not written)
    // We update the PLRU tree so the just-read way is marked as MRU.
    assign l2_do_lru_update = (state == L1_FILL) && lat_from_l2_hit;
    assign l2_lru_set       = lat_line_addr[OFFSET_BITS + L2_INDEX_BITS - 1 : OFFSET_BITS];
    assign l2_lru_way       = lat_l2_hit_way;

    // ── Main memory ───────────────────────────────────────────────────────
    // mm_req is a single-cycle pulse: high only in the FIRST cycle of
    // L2_WRITEBACK or MEM_FETCH, then held low while waiting for ready.
    assign mm_req   = ((state == L2_WRITEBACK) || (state == MEM_FETCH)) && !mm_req_sent;
    assign mm_we    = (state == L2_WRITEBACK);
    assign mm_addr  = (state == L2_WRITEBACK) ? lat_l2_vaddr : lat_line_addr;
    assign mm_wdata = lat_l2_vdata;

endmodule
