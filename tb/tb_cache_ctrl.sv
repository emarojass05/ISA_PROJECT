`timescale 1ns/1ps
// =============================================================================
// tb_cache_ctrl.sv — Testbench for cache_ctrl
// =============================================================================
// Strategy: cache_l1d, cache_l2, and main_mem_model are NOT instantiated here.
// Instead, their interface signals are driven directly by the testbench, acting
// as a hand-controlled behavioral model. This lets each test case exercise one
// FSM path in isolation without coupling to the cache-array implementations.
//
// Test cases:
//   TC1 — Bypass (cache_enable=0): request goes to data_mem, no stall
//   TC2 — L1 read hit: read_data correct, lru_update fires, no stall
//   TC3 — L1 write hit: do_write_hit fires, no stall
//   TC4 — L1 miss → L2 hit, clean L1 victim: stall ~2 cycles, correct data
//   TC5 — L1 miss → L2 miss → MEM fetch, all clean: stall ~29 cycles
//   TC6 — L1 miss, dirty L1 victim → L2 hit: l2_do_write_line fires, fill OK
//   TC7 — Store miss (write-allocate): l1_do_fill + l1_do_write_hit both fire
//   TC8 — L1 miss → L2 miss, dirty L2 victim: two MM transactions (WB + fetch)
// =============================================================================

module tb_cache_ctrl;

    // ── Parameters ────────────────────────────────────────────────────────
    localparam int XLEN       = 32;
    localparam int LINE_WORDS = 8;
    localparam int LINE_BITS  = LINE_WORDS * 32;
    localparam int L1_SETS    = 64;
    localparam int L2_SETS    = 128;
    localparam int MM_LATENCY = 25;

    // ── DUT signals ───────────────────────────────────────────────────────
    logic clk, rst;

    // Pipeline side
    logic             cache_enable, mem_read, mem_write;
    logic [XLEN-1:0]  addr;
    logic [31:0]      write_data, read_data;
    logic             cache_stall;

    // Data-memory bypass
    logic             dm_read, dm_write;
    logic [XLEN-1:0]  dm_addr;
    logic [31:0]      dm_write_data, dm_read_data;

    // L1 interface (cache_ctrl → L1D outputs; L1D → cache_ctrl inputs)
    logic [XLEN-1:0]      l1_req_addr;
    logic                 l1_hit, l1_hit_way;
    logic [31:0]          l1_hit_rdata;
    logic                 l1_victim_dirty, l1_victim_way;
    logic [XLEN-1:0]      l1_victim_addr;
    logic [LINE_BITS-1:0] l1_victim_data;
    logic                 l1_do_fill, l1_fill_way;
    logic [XLEN-1:0]      l1_fill_addr;
    logic [LINE_BITS-1:0] l1_fill_data;
    logic                 l1_do_write_hit, l1_write_way;
    logic [XLEN-1:0]      l1_write_addr;
    logic [31:0]          l1_write_data;
    logic                 l1_do_lru_update;
    logic [5:0]           l1_lru_set;
    logic                 l1_lru_way;

    // L2 interface
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
    logic [6:0]           l2_lru_set;
    logic [1:0]           l2_lru_way;

    // Main memory interface
    logic                 mm_req, mm_we;
    logic [XLEN-1:0]      mm_addr;
    logic [LINE_BITS-1:0] mm_wdata;
    logic                 mm_ready;
    logic [LINE_BITS-1:0] mm_rdata;

    // ── DUT instantiation ─────────────────────────────────────────────────
    cache_ctrl #(
        .XLEN      (XLEN),
        .LINE_WORDS(LINE_WORDS),
        .L1_SETS   (L1_SETS),
        .L2_SETS   (L2_SETS)
    ) dut (
        .clk(clk), .rst(rst),
        .cache_enable(cache_enable),
        .mem_read(mem_read), .mem_write(mem_write),
        .addr(addr), .write_data(write_data),
        .read_data(read_data), .cache_stall(cache_stall),
        .dm_read(dm_read), .dm_write(dm_write),
        .dm_addr(dm_addr), .dm_write_data(dm_write_data),
        .dm_read_data(dm_read_data),
        .l1_req_addr(l1_req_addr),
        .l1_hit(l1_hit), .l1_hit_way(l1_hit_way), .l1_hit_rdata(l1_hit_rdata),
        .l1_victim_dirty(l1_victim_dirty), .l1_victim_way(l1_victim_way),
        .l1_victim_addr(l1_victim_addr),   .l1_victim_data(l1_victim_data),
        .l1_do_fill(l1_do_fill),           .l1_fill_way(l1_fill_way),
        .l1_fill_addr(l1_fill_addr),       .l1_fill_data(l1_fill_data),
        .l1_do_write_hit(l1_do_write_hit), .l1_write_way(l1_write_way),
        .l1_write_addr(l1_write_addr),     .l1_write_data(l1_write_data),
        .l1_do_lru_update(l1_do_lru_update),
        .l1_lru_set(l1_lru_set),           .l1_lru_way(l1_lru_way),
        .l2_req_addr(l2_req_addr),
        .l2_hit(l2_hit), .l2_hit_way(l2_hit_way),
        .l2_hit_rdata_line(l2_hit_rdata_line),
        .l2_victim_dirty(l2_victim_dirty),
        .l2_victim_addr(l2_victim_addr),   .l2_victim_data(l2_victim_data),
        .l2_do_fill(l2_do_fill),
        .l2_fill_addr(l2_fill_addr),       .l2_fill_data(l2_fill_data),
        .l2_do_write_line(l2_do_write_line),
        .l2_wline_addr(l2_wline_addr),     .l2_wline_data(l2_wline_data),
        .l2_do_lru_update(l2_do_lru_update),
        .l2_lru_set(l2_lru_set),           .l2_lru_way(l2_lru_way),
        .mm_req(mm_req), .mm_we(mm_we),
        .mm_addr(mm_addr), .mm_wdata(mm_wdata),
        .mm_ready(mm_ready), .mm_rdata(mm_rdata)
    );

    // ── Clock ─────────────────────────────────────────────────────────────
    initial clk = 0;
    always  #5 clk = ~clk;

    // ── Helpers ───────────────────────────────────────────────────────────
    int pass_count, fail_count;

    task automatic check(input string name, input logic got, input logic exp);
        if (got === exp) begin
            $display("  [PASS] %s", name);
            pass_count++;
        end else begin
            $display("  [FAIL] %s — got %0b, exp %0b", name, got, exp);
            fail_count++;
        end
    endtask

    task automatic check32(input string name, input logic [31:0] got, input logic [31:0] exp);
        if (got === exp) begin
            $display("  [PASS] %s (= %08h)", name, got);
            pass_count++;
        end else begin
            $display("  [FAIL] %s — got %08h, exp %08h", name, got, exp);
            fail_count++;
        end
    endtask

    // Construct a 256-bit line where word[i] = base + i
    function automatic logic [LINE_BITS-1:0] make_line(input logic [31:0] base);
        logic [LINE_BITS-1:0] line;
        int i;
        for (i = 0; i < LINE_WORDS; i++)
            line[i*32 +: 32] = base + i;
        return line;
    endfunction

    // Simulate main memory responding to a request.
    // Call this in a forked thread. It watches for mm_req, waits MM_LATENCY
    // cycles, then pulses mm_ready for exactly one cycle.
    task automatic mm_respond(input logic [LINE_BITS-1:0] data);
        wait(mm_req);                    // level-sensitive: passes if mm_req is already high
        repeat(MM_LATENCY - 1) @(posedge clk);
        @(negedge clk);
        mm_rdata = data;
        mm_ready = 1'b1;
        @(posedge clk); #1;
        mm_ready = 1'b0;
    endtask

    // Wait in a loop until l1_do_fill goes high (FSM is in L1_FILL state —
    // the last state before returning to IDLE). Returns the cycle count.
    // Clears mem_read/mem_write so IDLE doesn't immediately detect a new miss.
    task automatic wait_for_l1_fill(output int cycles);
        cycles = 0;
        while (!l1_do_fill) begin
            @(posedge clk); #1;
            cycles++;
            if (cycles > 300) begin
                $display("  [TIMEOUT] l1_do_fill never arrived");
                fail_count++;
                disable wait_for_l1_fill;
            end
        end
        // FSM is in L1_FILL: clear the pipeline request so IDLE re-entry
        // doesn't see another miss (the pipeline would be frozen, but our
        // testbench drives signals manually).
        mem_read  = 1'b0;
        mem_write = 1'b0;
    endtask

    // Default state: cache enabled, no request, all hits/misses = clean miss
    task automatic idle_defaults();
        cache_enable    = 1'b1;
        mem_read        = 1'b0;
        mem_write       = 1'b0;
        addr            = '0;
        write_data      = '0;
        dm_read_data    = 32'hDEFADEFA;
        l1_hit          = 1'b0;
        l1_hit_way      = 1'b0;
        l1_hit_rdata    = '0;
        l1_victim_dirty = 1'b0;
        l1_victim_way   = 1'b0;
        l1_victim_addr  = '0;
        l1_victim_data  = '0;
        l2_hit          = 1'b0;
        l2_hit_way      = 2'd0;
        l2_hit_rdata_line = '0;
        l2_victim_dirty = 1'b0;
        l2_victim_addr  = '0;
        l2_victim_data  = '0;
        mm_ready        = 1'b0;
        mm_rdata        = '0;
    endtask

    // ── Event monitors ────────────────────────────────────────────────────
    // l2_do_fill fires during L2_FILL state, which is one cycle before L1_FILL.
    // By the time wait_for_l1_fill() returns (L1_FILL), l2_do_fill is already 0.
    // This latch captures whether it ever fired during a miss sequence.
    logic l2_fill_happened;
    initial l2_fill_happened = 0;
    always @(l2_do_fill) if (l2_do_fill) l2_fill_happened = 1;

    // ── Test sequence ─────────────────────────────────────────────────────
    initial begin
        $dumpfile("build/sim/tb_cache_ctrl.vcd");
        $dumpvars(0, tb_cache_ctrl);

        pass_count = 0;
        fail_count = 0;

        idle_defaults();
        rst = 1'b1;
        repeat(3) @(posedge clk); #1;
        check("stall=0 during reset", cache_stall, 1'b0);
        @(negedge clk); rst = 1'b0;

        // ─────────────────────────────────────────────────────────────────
        $display("\n=== TC1: Bypass mode (cache_enable=0) ===");
        cache_enable = 1'b0;
        mem_read     = 1'b1;
        addr         = 32'h0000_ABCD;
        dm_read_data = 32'hCAFE_BABE;
        #1;
        check  ("cache_stall=0",         cache_stall, 1'b0);
        check  ("dm_read=1",             dm_read,     1'b1);
        check  ("dm_write=0",            dm_write,    1'b0);
        check32("dm_addr mirrors addr",  dm_addr,     32'h0000_ABCD);
        check32("read_data = dm_rdata",  read_data,   32'hCAFE_BABE);
        check  ("mm_req=0",              mm_req,      1'b0);
        @(posedge clk); #1;
        mem_read     = 1'b0;
        cache_enable = 1'b1;

        // ─────────────────────────────────────────────────────────────────
        $display("\n=== TC2: L1 read hit ===");
        addr         = 32'h0000_0100;
        mem_read     = 1'b1;
        l1_hit       = 1'b1;
        l1_hit_way   = 1'b1;
        l1_hit_rdata = 32'hAAAA_1111;
        #1;
        check  ("stall=0 on hit",       cache_stall,      1'b0);
        check32("read_data=l1_rdata",   read_data,        32'hAAAA_1111);
        check  ("lru_update fires",     l1_do_lru_update, 1'b1);
        check  ("no write_hit",         l1_do_write_hit,  1'b0);
        check  ("mm_req=0",             mm_req,           1'b0);
        check  ("dm_read=0",            dm_read,          1'b0);
        @(posedge clk); #1;
        mem_read = 1'b0; l1_hit = 1'b0;

        // ─────────────────────────────────────────────────────────────────
        $display("\n=== TC3: L1 write hit ===");
        addr         = 32'h0000_0104;
        mem_write    = 1'b1;
        write_data   = 32'hDEAD_BEEF;
        l1_hit       = 1'b1;
        l1_hit_way   = 1'b0;
        #1;
        check("stall=0 on write hit",  cache_stall,     1'b0);
        check("do_write_hit=1",        l1_do_write_hit, 1'b1);
        check("write_way=0",           l1_write_way,    1'b0);
        check("no lru_update",         l1_do_lru_update, 1'b0);
        check("no l1_do_fill",         l1_do_fill,      1'b0);
        @(posedge clk); #1;
        mem_write = 1'b0; l1_hit = 1'b0;

        // ─────────────────────────────────────────────────────────────────
        $display("\n=== TC4: L1 miss → L2 hit (clean L1 victim) ===");
        begin
            logic [LINE_BITS-1:0] l2_line;
            int cycles;
            l2_line = make_line(32'hBB00_0000);

            // addr = 0x0200 → offset=0, word[0] expected
            @(negedge clk);
            addr            = 32'h0000_0200;
            mem_read        = 1'b1;
            l1_hit          = 1'b0;
            l1_victim_dirty = 1'b0;
            l1_victim_way   = 1'b1;
            l2_hit          = 1'b1;
            l2_hit_way      = 2'd2;
            l2_hit_rdata_line = l2_line;

            @(posedge clk); #1;   // FSM latches miss → L2_LOOKUP
            mem_read = 1'b0;      // clear so IDLE re-entry is quiet
            check("stall during miss", cache_stall, 1'b1);

            // Wait for L1_FILL (state where l1_do_fill and read_data are valid)
            wait_for_l1_fill(cycles);
            $display("  [INFO] cycles to L1_FILL = %0d (expected 2: L2_LOOKUP+L1_FILL)", cycles);

            check("l1_do_fill in L1_FILL",     l1_do_fill,      1'b1);
            check("l2_do_lru_update fires",    l2_do_lru_update,1'b1);
            check32("read_data = line[word0]", read_data,       32'hBB00_0000);

            @(posedge clk); #1;   // IDLE
            check("stall cleared",             cache_stall,     1'b0);
        end

        // ─────────────────────────────────────────────────────────────────
        $display("\n=== TC5: L1 miss → L2 miss → MEM fetch (all victims clean) ===");
        begin
            logic [LINE_BITS-1:0] mem_line;
            int cycles;
            // addr = 0x030C → bits[4:2] = 0x0C[4:2] = 011 = 3 → word[3]
            mem_line = make_line(32'hCC00_0000);
            l2_fill_happened = 0;   // reset monitor before this test

            @(negedge clk);
            addr            = 32'h0000_030C;
            mem_read        = 1'b1;
            l1_hit          = 1'b0;
            l1_victim_dirty = 1'b0;
            l1_victim_way   = 1'b0;
            l2_hit          = 1'b0;
            l2_victim_dirty = 1'b0;

            @(posedge clk); #1;   // FSM latches miss → L2_LOOKUP
            mem_read = 1'b0;
            check("stall=1 on miss", cache_stall, 1'b1);

            fork
                mm_respond(mem_line);
                wait_for_l1_fill(cycles);
            join

            $display("  [INFO] cycles to L1_FILL = %0d (expected ~27: L2_LOOKUP+MEM×25+L2_FILL)", cycles);
            check("l1_do_fill fires",           l1_do_fill,       1'b1);
            check("l2_do_fill happened",        l2_fill_happened, 1'b1);
            // addr[4:2] = 0x0C[4:2] = 011 = 3 → word[3]
            check32("read_data = line[word3]",  read_data,        32'hCC00_0003);

            @(posedge clk); #1;
            check("stall cleared after MM", cache_stall, 1'b0);
        end

        // ─────────────────────────────────────────────────────────────────
        $display("\n=== TC6: L1 miss, dirty L1 victim → L2 hit ===");
        begin
            logic [LINE_BITS-1:0] l2_line, dirty_line;
            int cycles;
            // addr = 0x0404 → [4:2] = 3'b000 + carry → word[1]? No:
            // 0x04 = 0000_0100 → bits[4:2] = 001 → word[1]
            l2_line    = make_line(32'hDD00_0000);
            dirty_line = make_line(32'hEE00_0000);

            @(negedge clk);
            addr            = 32'h0000_0404;
            mem_read        = 1'b1;
            l1_hit          = 1'b0;
            l1_victim_dirty = 1'b1;         // dirty! → L1_WRITEBACK first
            l1_victim_way   = 1'b0;
            l1_victim_addr  = 32'h0000_0800;
            l1_victim_data  = dirty_line;
            l2_hit          = 1'b1;
            l2_hit_way      = 2'd1;
            l2_hit_rdata_line = l2_line;

            @(posedge clk); #1;   // FSM latches miss → L1_WRITEBACK
            mem_read = 1'b0;

            // One cycle into L1_WRITEBACK — check that l2_do_write_line fires
            check("l2_do_write_line in L1_WRITEBACK", l2_do_write_line, 1'b1);

            wait_for_l1_fill(cycles);
            $display("  [INFO] cycles to L1_FILL = %0d (expected 3: L1_WB+L2_LOOKUP+L1_FILL)", cycles);

            check("l1_do_fill fires",         l1_do_fill,  1'b1);
            // 0x0404[4:2] = 001 → word[1]
            check32("read_data = line[word1]",read_data,   32'hDD00_0001);

            @(posedge clk); #1;
            check("stall cleared", cache_stall, 1'b0);
            l1_victim_dirty = 1'b0;
        end

        // ─────────────────────────────────────────────────────────────────
        $display("\n=== TC7: Store miss — write-allocate ===");
        begin
            logic [LINE_BITS-1:0] mem_line;
            int cycles;
            mem_line = make_line(32'hFF00_0000);

            @(negedge clk);
            addr            = 32'h0000_0510;  // [4:2] = 010 → word[2]
            mem_write       = 1'b1;
            write_data      = 32'hDEAD_CAFE;
            l1_hit          = 1'b0;
            l1_victim_dirty = 1'b0;
            l1_victim_way   = 1'b0;
            l2_hit          = 1'b0;
            l2_victim_dirty = 1'b0;

            @(posedge clk); #1;
            mem_write = 1'b0;
            check("stall=1 on store miss", cache_stall, 1'b1);

            fork
                mm_respond(mem_line);
                wait_for_l1_fill(cycles);
            join

            $display("  [INFO] cycles to L1_FILL = %0d", cycles);
            // Write-allocate: both fill and write_hit must fire simultaneously
            check("l1_do_fill fires",      l1_do_fill,      1'b1);
            check("l1_do_write_hit fires", l1_do_write_hit, 1'b1);

            @(posedge clk); #1;
            check("stall cleared after store miss", cache_stall, 1'b0);
        end

        // ─────────────────────────────────────────────────────────────────
        $display("\n=== TC8: L1 miss → L2 miss, dirty L2 victim (2× MM) ===");
        begin
            logic [LINE_BITS-1:0] dirty_l2, fetch_line;
            int cycles;
            // addr = 0x060C → [4:2] = 001 → word[1]? Let's check:
            // 0x60C = 0110_0000_1100 → [4:2] = 011 → word[3]
            dirty_l2   = make_line(32'hAA00_0000);
            fetch_line = make_line(32'h5500_0000);

            @(negedge clk);
            addr            = 32'h0000_060C;
            mem_read        = 1'b1;
            l1_hit          = 1'b0;
            l1_victim_dirty = 1'b0;
            l1_victim_way   = 1'b0;
            l2_hit          = 1'b0;
            l2_victim_dirty = 1'b1;   // dirty L2 victim → MM write-back first
            l2_victim_addr  = 32'h0001_0000;
            l2_victim_data  = dirty_l2;

            @(posedge clk); #1;
            mem_read = 1'b0;
            check("stall=1", cache_stall, 1'b1);

            fork
                begin
                    // First MM transaction: write-back dirty L2 victim (we=1)
                    mm_respond('0);
                    // After write-back, cache_ctrl moves to MEM_FETCH.
                    // Clear dirty so re-checking victim won't confuse things.
                    l2_victim_dirty = 1'b0;
                    // Second MM transaction: fetch the missed line (we=0)
                    mm_respond(fetch_line);
                end
                wait_for_l1_fill(cycles);
            join

            $display("  [INFO] cycles to L1_FILL = %0d (expected ~56: 2×25 + overhead)", cycles);
            check("l1_do_fill fires",        l1_do_fill,  1'b1);
            // 0x060C[4:2] = 011 → word[3]
            check32("read_data = line[word3]", read_data, 32'h5500_0003);

            @(posedge clk); #1;
            check("stall cleared after 2×MM", cache_stall, 1'b0);
        end

        // ─────────────────────────────────────────────────────────────────
        $display("\n============================================");
        $display(" RESULTADO: %0d PASS  /  %0d FAIL", pass_count, fail_count);
        $display("============================================\n");

        if (fail_count == 0)
            $display(" [OK] tb_cache_ctrl: todos los casos pasaron.");
        else
            $display(" [ERROR] tb_cache_ctrl: %0d caso(s) fallaron.", fail_count);

        $finish;
    end

endmodule
