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
//             ──L2 miss, victim dirty, wb !full──enqueue victim──→ MEM_FETCH
//             ──L2 miss, victim dirty, wb full──→ L2_LOOKUP (stall)
//
//   MEM_FETCH (waits ~25 cycles for write buffer read) ──→ L2_FILL ──→ L1_FILL
//
//   L1_FILL ──→ IDLE  (stall drops, pipeline resumes)
//
// Cycle costs (approximate, cache_enable = 1):
//   L1 hit         :  0 extra cycles  (resolved in IDLE)
//   L2 hit         :  8 extra cycles  (L2_LOOKUP + L2_WAIT×5 + L1_FILL) — matches spec
//   Main-mem fetch :  ≥29 extra cycles (L2_LOOKUP + MEM_FETCH×25 + L2_FILL + L1_FILL)
//   Dirty L2 eviction: victim enqueued to write buffer, drain is background
//                      (no longer serialized in the critical path).
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

    // ── Write buffer interface ────────────────────────────────────────────
    output logic                  wb_enq,
    output logic [XLEN-1:0]       wb_enq_addr,
    output logic [LINE_BITS-1:0]  wb_enq_data,
    input  logic                  wb_full,
    output logic                  wb_rd_req,
    output logic [XLEN-1:0]       wb_rd_addr,
    input  logic                  wb_rd_ready,
    input  logic [LINE_BITS-1:0]  wb_rd_data,

    // ── Performance counters (only active when cache_enable = 1) ─────────
    output logic [31:0]           perf_l1_accesses,   // total L1 requests
    output logic [31:0]           perf_l1_hits,        // L1 hits
    output logic [31:0]           perf_l1_misses,      // L1 misses
    output logic [31:0]           perf_l2_hits,        // L2 hits (on L1 miss)
    output logic [31:0]           perf_l2_misses,      // L2 misses → main memory
    output logic [31:0]           perf_mm_accesses,    // main memory fetches
    output logic [31:0]           perf_stall_cycles    // total cache stall cycles
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
        L2_WAIT,       // stall 5 extra cycles to match 8-cycle L2 hit time spec
        MEM_FETCH,     // fetch the missed line from main memory via write buffer
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

    // ── Main-memory request tracking ─────────────────────────────────────
    // (see mm_req_sent below — kept together for clarity)

    // ── Line to install in L1 (set in L2_LOOKUP on hit, or in MEM_FETCH) ─
    logic [LINE_BITS-1:0]  lat_fill_line;    // 256-bit line heading for L1
    logic                  lat_from_l2_hit;  // 1 = line came from L2 (not MM)
    logic [1:0]            lat_l2_hit_way;   // L2 way that was hit (for PLRU update)

    // mm_req_sent goes high after wb_rd_req fires so we don't pulse it again.
    logic mm_req_sent;

    // ── L2 wait counter ───────────────────────────────────────────────────
    // Counts 5 extra cycles in L2_WAIT to reach the 8-cycle L2 hit time spec
    // (1 IDLE miss + 1 L2_LOOKUP + 5 L2_WAIT + 1 L1_FILL = 8 stall cycles).
    logic [2:0] l2_wait_count;

    // ── Performance counter registers ────────────────────────────────────
    logic [31:0] perf_l1_accesses_r;
    logic [31:0] perf_l1_hits_r;
    logic [31:0] perf_l1_misses_r;
    logic [31:0] perf_l2_hits_r;
    logic [31:0] perf_l2_misses_r;
    logic [31:0] perf_mm_accesses_r;
    logic [31:0] perf_stall_cycles_r;

    assign perf_l1_accesses  = perf_l1_accesses_r;
    assign perf_l1_hits      = perf_l1_hits_r;
    assign perf_l1_misses    = perf_l1_misses_r;
    assign perf_l2_hits      = perf_l2_hits_r;
    assign perf_l2_misses    = perf_l2_misses_r;
    assign perf_mm_accesses  = perf_mm_accesses_r;
    assign perf_stall_cycles = perf_stall_cycles_r;

    // ── Registered state transitions and latching ────────────────────────
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state              <= IDLE;
            lat_addr           <= '0;
            lat_line_addr      <= '0;
            lat_wdata          <= '0;
            lat_mem_read       <= 1'b0;
            lat_mem_write      <= 1'b0;
            lat_l1_vway        <= 1'b0;
            lat_l1_vaddr       <= '0;
            lat_l1_vdata       <= '0;
            lat_fill_line      <= '0;
            lat_from_l2_hit    <= 1'b0;
            lat_l2_hit_way     <= '0;
            mm_req_sent        <= 1'b0;
            l2_wait_count      <= '0;
            perf_l1_accesses_r <= '0;
            perf_l1_hits_r     <= '0;
            perf_l1_misses_r   <= '0;
            perf_l2_hits_r     <= '0;
            perf_l2_misses_r   <= '0;
            perf_mm_accesses_r <= '0;
            perf_stall_cycles_r<= '0;
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
                // On a dirty miss, enqueue the victim to the write buffer
                // (combinational wb_enq fires this same cycle) and go straight
                // to MEM_FETCH. If the buffer is full, stay here until it drains.
                L2_LOOKUP: begin
                    if (l2_hit) begin
                        lat_fill_line   <= l2_hit_rdata_line;
                        lat_from_l2_hit <= 1'b1;
                        lat_l2_hit_way  <= l2_hit_way;
                        l2_wait_count   <= '0;
                        state           <= L2_WAIT;
                    end else begin
                        lat_from_l2_hit <= 1'b0;
                        if (l2_victim_dirty && wb_full) begin
                            // Buffer full: re-lookup next cycle (idempotent stall).
                            // cache_stall stays high because state != IDLE.
                        end else begin
                            state <= MEM_FETCH;
                        end
                    end
                end

                // ── L2_WAIT ──────────────────────────────────────────────
                // Hold for 5 cycles to meet the 8-cycle L2 hit time from spec.
                // (1 IDLE + 1 L2_LOOKUP + 5 L2_WAIT + 1 L1_FILL = 8 stalls)
                L2_WAIT: begin
                    if (l2_wait_count == 3'd4)
                        state <= L1_FILL;
                    else
                        l2_wait_count <= l2_wait_count + 1;
                end

                // ── MEM_FETCH ─────────────────────────────────────────────
                // Fetch the missed cache line via the write buffer (~25-cycle wait).
                // wb_rd_req fires for exactly one cycle, then we wait for wb_rd_ready.
                MEM_FETCH: begin
                    if (!mm_req_sent)
                        mm_req_sent <= 1'b1;
                    if (wb_rd_ready) begin
                        lat_fill_line <= wb_rd_data;
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

            // ── Performance counter increments ───────────────────────────
            // L1 access/hit/miss: one event per memory request arriving in IDLE
            if (cache_enable && (mem_read || mem_write) && state == IDLE) begin
                perf_l1_accesses_r <= perf_l1_accesses_r + 1;
                if (l1_hit)
                    perf_l1_hits_r <= perf_l1_hits_r + 1;
                else
                    perf_l1_misses_r <= perf_l1_misses_r + 1;
            end

            // L2 hit/miss: count only on first entry into L2_LOOKUP
            // (the state re-loops when wb_full; only the first cycle is the real lookup)
            if (state == L2_LOOKUP && (l2_hit || !l2_victim_dirty || !wb_full)) begin
                if (l2_hit)
                    perf_l2_hits_r <= perf_l2_hits_r + 1;
                else
                    perf_l2_misses_r <= perf_l2_misses_r + 1;
            end

            // Main memory fetch: first cycle of MEM_FETCH (when mm_req fires)
            if (state == MEM_FETCH && !mm_req_sent)
                perf_mm_accesses_r <= perf_mm_accesses_r + 1;

            // Stall cycles: every cycle cache_stall is asserted
            if (cache_enable && ((state != IDLE) || ((mem_read || mem_write) && !l1_hit)))
                perf_stall_cycles_r <= perf_stall_cycles_r + 1;
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

    // ── Write buffer interface ────────────────────────────────────────────
    // wb_enq is a single-cycle pulse fired during L2_LOOKUP when a dirty victim
    // needs to be evicted and the buffer has space. l2_victim_addr/data are
    // combinational and stable throughout L2_LOOKUP.
    assign wb_enq      = (state == L2_LOOKUP) && !l2_hit && l2_victim_dirty && !wb_full;
    assign wb_enq_addr = l2_victim_addr;
    assign wb_enq_data = l2_victim_data;

    // wb_rd_req is a single-cycle pulse on the first cycle of MEM_FETCH.
    assign wb_rd_req  = (state == MEM_FETCH) && !mm_req_sent;
    assign wb_rd_addr = lat_line_addr;

endmodule
