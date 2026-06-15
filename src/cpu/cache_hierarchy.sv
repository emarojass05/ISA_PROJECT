// =============================================================================
// cache_hierarchy.sv: Cache Hierarchy Wrapper
// =============================================================================
//
//    Pipeline
//       │
//   cache_ctrl            hierarchy controller
//     ├── cache_l1d       L1_D (2-way, 64 sets, 256 b/line)
//     ├── cache_l2        L2 (unified, 4-way, 128 sets, 256 b/line)
//     ├── mem_write_buffer write buffer between L2 evictions and main memory
//     └── main_mem_model
//
// Exposes only pipeline ports to cpu_top.
// When cache_enable = 0, cache_ctrl stays in IDLE so wb_enq and wb_rd_req
// never assert — the write buffer remains empty and wb_empty = 1 throughout.
// =============================================================================

module cache_hierarchy #(
    parameter int    XLEN          = 32,
    parameter int    LINE_WORDS    = 8,                    // 32b/line words
    parameter int    LINE_BITS     = LINE_WORDS * 32,      // 256b/cache line
    parameter int    L1_SETS       = 64,                   // L1 sets (2^6)
    parameter int    L2_SETS       = 128,                  // L2 sets (2^7)
    parameter int    MEM_DEPTH     = 16384,                // main_mem words (64 KB)
    parameter int    MEM_LATENCY   = 25,                   // DRAM lat. cycles
    parameter int    MEM_CLK_DIV   = 1,                    // memory clock-enable divisor
    parameter [1023:0] MEM_INIT_FILE = ""                  // optional init file
)(
    input  logic             clk,
    input  logic             rst,

    // Pipeline Interface - MEM stage
    input  logic             cache_enable,   // 0 = bypass, 1 = hierarchy active
    input  logic             mem_read,       // read req  (stage MEM)
    input  logic             mem_write,      // write req (stage MEM)
    input  logic [XLEN-1:0] addr,            // byte addr (stage MEM)
    input  logic [31:0]      write_data,     // write data (mem_write = 1)
    output logic [31:0]      read_data,      // data forwarded to stage WB
    output logic             cache_stall,    // pipeline freeze

    // Performance counters (only meaningful when cache_enable = 1)
    output logic [31:0]      perf_l1_accesses,
    output logic [31:0]      perf_l1_hits,
    output logic [31:0]      perf_l1_misses,
    output logic [31:0]      perf_l2_hits,
    output logic [31:0]      perf_l2_misses,
    output logic [31:0]      perf_mm_accesses,
    output logic [31:0]      perf_stall_cycles,

    // Write buffer observability (used by tb_cpu_program to confirm all
    // dirty evictions have reached main memory before the register dump)
    output logic             wb_empty
);

    // Internal signals cache_ctrl - cache_l1d
    logic [XLEN-1:0]      l1_req_addr;
    logic                 l1_hit;
    logic [$clog2(2)-1:0] l1_hit_way;
    logic [31:0]          l1_hit_rdata;
    logic                 l1_victim_dirty;
    logic                 l1_victim_way;
    logic [XLEN-1:0]      l1_victim_addr;
    logic [LINE_BITS-1:0] l1_victim_data;
    logic                 l1_do_fill;
    logic [$clog2(2)-1:0] l1_fill_way;
    logic [XLEN-1:0]      l1_fill_addr;
    logic [LINE_BITS-1:0] l1_fill_data;
    logic                 l1_do_write_hit;
    logic                 l1_write_way;
    logic [XLEN-1:0]      l1_write_addr;
    logic [31:0]          l1_write_data;
    logic                 l1_do_lru_update;
    logic [5:0]           l1_lru_set;       // $clog2(L1_SETS=64) = 6 bits
    logic                 l1_lru_way;

    // Internal signals cache_ctrl - cache_l2
    logic [XLEN-1:0]      l2_req_addr;
    logic                 l2_hit;
    logic [1:0]           l2_hit_way;
    logic [LINE_BITS-1:0] l2_hit_rdata_line;
    logic                 l2_victim_dirty;
    logic [XLEN-1:0]      l2_victim_addr;
    logic [LINE_BITS-1:0] l2_victim_data;
    logic                 l2_do_fill;
    logic [XLEN-1:0]      l2_fill_addr;
    logic [LINE_BITS-1:0] l2_fill_data;
    logic                 l2_do_write_line;
    logic [XLEN-1:0]      l2_wline_addr;
    logic [LINE_BITS-1:0] l2_wline_data;
    logic                 l2_do_lru_update;
    logic [6:0]           l2_lru_set;       // $clog2(L2_SETS=128) = 7 bits
    logic [1:0]           l2_lru_way;

    // Internal signals cache_ctrl - mem_write_buffer (upstream enqueue/read)
    logic                 wb_enq;
    logic [XLEN-1:0]      wb_enq_addr;
    logic [LINE_BITS-1:0] wb_enq_data;
    logic                 wb_full;
    logic                 wb_rd_req;
    logic [XLEN-1:0]      wb_rd_addr;
    logic                 wb_rd_ready;
    logic [LINE_BITS-1:0] wb_rd_data;

    // Internal signals mem_write_buffer - main_mem_model (downstream mm)
    logic                 mm_req;
    logic                 mm_we;
    logic [XLEN-1:0]      mm_addr;
    logic [LINE_BITS-1:0] mm_wdata;
    logic                 mm_ready;
    logic [LINE_BITS-1:0] mm_rdata;

    // Internal signals cache_ctrl - bypass_mem
    logic             dm_read;
    logic             dm_write;
    logic [XLEN-1:0] dm_addr;
    logic [31:0]      dm_write_data;
    logic [31:0]      dm_read_data;

    // =========================================================================
    // Bypass SRAM (cache_enable = 0)
    // =========================================================================
    localparam int DM_AW = $clog2(MEM_DEPTH);  // index bits into bypass_mem

    logic [31:0] bypass_mem [0:MEM_DEPTH-1];

    initial begin
        integer i;

        for (i = 0; i < MEM_DEPTH; i = i + 1)
            bypass_mem[i] = 32'h0;

        if (MEM_INIT_FILE != "")
            $readmemh(MEM_INIT_FILE, bypass_mem);
    end

    // word-aligned index: drop the 2 LSBs of the byte address
    logic [DM_AW-1:0] dm_word_idx;
    assign dm_word_idx = dm_addr[DM_AW+1:2];

    always_ff @(posedge clk) begin
        if (dm_write)
            bypass_mem[dm_word_idx] <= dm_write_data;
    end

    assign dm_read_data = bypass_mem[dm_word_idx];

    // Instance: cache_ctrl
    cache_ctrl #(
        .XLEN      (XLEN),
        .LINE_WORDS(LINE_WORDS),
        .LINE_BITS (LINE_BITS),
        .L1_SETS   (L1_SETS),
        .L2_SETS   (L2_SETS)
    ) u_cache_ctrl (
        .clk             (clk),
        .rst             (rst),
        // Pipeline
        .cache_enable    (cache_enable),
        .mem_read        (mem_read),
        .mem_write       (mem_write),
        .addr            (addr),
        .write_data      (write_data),
        .read_data       (read_data),
        .cache_stall     (cache_stall),
        // Bypass (data-mem)
        .dm_read         (dm_read),
        .dm_write        (dm_write),
        .dm_addr         (dm_addr),
        .dm_write_data   (dm_write_data),
        .dm_read_data    (dm_read_data),
        // L1D
        .l1_req_addr     (l1_req_addr),
        .l1_hit          (l1_hit),
        .l1_hit_way      (l1_hit_way),
        .l1_hit_rdata    (l1_hit_rdata),
        .l1_victim_dirty (l1_victim_dirty),
        .l1_victim_way   (l1_victim_way),
        .l1_victim_addr  (l1_victim_addr),
        .l1_victim_data  (l1_victim_data),
        .l1_do_fill      (l1_do_fill),
        .l1_fill_way     (l1_fill_way),
        .l1_fill_addr    (l1_fill_addr),
        .l1_fill_data    (l1_fill_data),
        .l1_do_write_hit (l1_do_write_hit),
        .l1_write_way    (l1_write_way),
        .l1_write_addr   (l1_write_addr),
        .l1_write_data   (l1_write_data),
        .l1_do_lru_update(l1_do_lru_update),
        .l1_lru_set      (l1_lru_set),
        .l1_lru_way      (l1_lru_way),
        // L2
        .l2_req_addr      (l2_req_addr),
        .l2_hit           (l2_hit),
        .l2_hit_way       (l2_hit_way),
        .l2_hit_rdata_line(l2_hit_rdata_line),
        .l2_victim_dirty  (l2_victim_dirty),
        .l2_victim_addr   (l2_victim_addr),
        .l2_victim_data   (l2_victim_data),
        .l2_do_fill       (l2_do_fill),
        .l2_fill_addr     (l2_fill_addr),
        .l2_fill_data     (l2_fill_data),
        .l2_do_write_line (l2_do_write_line),
        .l2_wline_addr    (l2_wline_addr),
        .l2_wline_data    (l2_wline_data),
        .l2_do_lru_update (l2_do_lru_update),
        .l2_lru_set       (l2_lru_set),
        .l2_lru_way       (l2_lru_way),
        // Write buffer
        .wb_enq           (wb_enq),
        .wb_enq_addr      (wb_enq_addr),
        .wb_enq_data      (wb_enq_data),
        .wb_full          (wb_full),
        .wb_rd_req        (wb_rd_req),
        .wb_rd_addr       (wb_rd_addr),
        .wb_rd_ready      (wb_rd_ready),
        .wb_rd_data       (wb_rd_data),
        // Performance counters
        .perf_l1_accesses (perf_l1_accesses),
        .perf_l1_hits     (perf_l1_hits),
        .perf_l1_misses   (perf_l1_misses),
        .perf_l2_hits     (perf_l2_hits),
        .perf_l2_misses   (perf_l2_misses),
        .perf_mm_accesses (perf_mm_accesses),
        .perf_stall_cycles(perf_stall_cycles)
    );

    // Instance: cache_l1d (cache L1_D, 2-way LRU)
    cache_l1d #(
        .XLEN      (XLEN),
        .SETS      (L1_SETS),
        .LINE_WORDS(LINE_WORDS),
        .LINE_BITS (LINE_BITS)
    ) u_l1d (
        .clk          (clk),
        .rst          (rst),
        // Lookup comb
        .req_addr     (l1_req_addr),
        .hit          (l1_hit),
        .hit_way      (l1_hit_way),
        .hit_rdata    (l1_hit_rdata),
        .victim_dirty (l1_victim_dirty),
        .victim_way   (l1_victim_way),
        .victim_addr  (l1_victim_addr),
        .victim_data  (l1_victim_data),
        // Fill
        .do_fill      (l1_do_fill),
        .fill_way     (l1_fill_way),
        .fill_addr    (l1_fill_addr),
        .fill_data    (l1_fill_data),
        // Write-hit
        .do_write_hit (l1_do_write_hit),
        .write_way    (l1_write_way),
        .write_addr   (l1_write_addr),
        .write_data   (l1_write_data),
        // LRU update
        .do_lru_update(l1_do_lru_update),
        .lru_set      (l1_lru_set),
        .lru_way      (l1_lru_way)
    );

    // Instance: cache_l2 (cache L2, 4-way PLRU)
    cache_l2 #(
        .XLEN      (XLEN),
        .SETS      (L2_SETS),
        .LINE_WORDS(LINE_WORDS),
        .LINE_BITS (LINE_BITS)
    ) u_l2 (
        .clk           (clk),
        .rst           (rst),
        // Lookup comb.
        .req_addr      (l2_req_addr),
        .hit           (l2_hit),
        .hit_way       (l2_hit_way),
        .hit_rdata_line(l2_hit_rdata_line),
        .victim_dirty  (l2_victim_dirty),
        .victim_addr   (l2_victim_addr),
        .victim_data   (l2_victim_data),
        // Fill
        .do_fill       (l2_do_fill),
        .fill_addr     (l2_fill_addr),
        .fill_data     (l2_fill_data),
        // Write-line (write-back dirty L1)
        .do_write_line (l2_do_write_line),
        .wline_addr    (l2_wline_addr),
        .wline_data    (l2_wline_data),
        // PLRU update
        .do_lru_update (l2_do_lru_update),
        .lru_set       (l2_lru_set),
        .lru_way       (l2_lru_way)
    );

    // Instance: mem_write_buffer
    mem_write_buffer #(
        .XLEN     (XLEN),
        .LINE_BITS(LINE_BITS),
        .DEPTH    (4)
    ) u_wbuf (
        .clk      (clk),
        .rst      (rst),
        .enq      (wb_enq),
        .enq_addr (wb_enq_addr),
        .enq_data (wb_enq_data),
        .full     (wb_full),
        .rd_req   (wb_rd_req),
        .rd_addr  (wb_rd_addr),
        .rd_ready (wb_rd_ready),
        .rd_data  (wb_rd_data),
        .empty    (wb_empty),
        .mm_req   (mm_req),
        .mm_we    (mm_we),
        .mm_addr  (mm_addr),
        .mm_wdata (mm_wdata),
        .mm_ready (mm_ready),
        .mm_rdata (mm_rdata),
        .perf_wb_drains         (),
        .perf_wb_conflict_drains(),
        .perf_wb_full_stalls    ()
    );

    // Instance: main_mem_model
    main_mem_model #(
        .XLEN       (XLEN),
        .DEPTH      (MEM_DEPTH),
        .LINE_WORDS (LINE_WORDS),
        .LINE_BITS  (LINE_BITS),
        .LATENCY    (MEM_LATENCY),
        .MEM_CLK_DIV(MEM_CLK_DIV),
        .INIT_FILE  (MEM_INIT_FILE)
    ) u_main_mem (
        .clk  (clk),
        .rst  (rst),
        .req  (mm_req),
        .we   (mm_we),
        .addr (mm_addr),
        .wdata(mm_wdata),
        .ready(mm_ready),
        .rdata(mm_rdata)
    );

endmodule