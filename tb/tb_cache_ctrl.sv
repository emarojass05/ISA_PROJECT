`timescale 1ns/1ps
// =============================================================================
// tb_cache_ctrl.sv — Testbench for cache_ctrl
// =============================================================================
// Strategy: cache_l1d, cache_l2 are NOT instantiated here; their interface
// signals are driven directly by the testbench as a behavioral model.
// The real mem_write_buffer and main_mem_model are instantiated so that
// cache_ctrl's wb_* ports are wired to actual hardware.
//
// Test cases:
//   TC1 — Bypass (cache_enable=0): request goes to data_mem, no stall
//   TC2 — L1 read hit: read_data correct, lru_update fires, no stall
//   TC3 — L1 write hit: do_write_hit fires, no stall
//   TC4 — L1 miss -> L2 hit, clean L1 victim: stall ~2 cycles, correct data
//   TC5 — L1 miss -> L2 miss -> MEM fetch, all clean: stall ~29 cycles
//   TC6 — L1 miss, dirty L1 victim -> L2 hit: l2_do_write_line fires, fill OK
//   TC7 — Store miss (write-allocate): l1_do_fill + l1_do_write_hit both fire
//   TC8 — L1 miss -> L2 miss, dirty L2 victim: fetch goes first (~27cy),
//         drain happens in background; verify victim drained to memory
//   TC9 — Drain-on-conflict: victim addr == fetch addr; write before read
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

    // L1 interface
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

    // Write buffer interface (DUT -> u_wbuf)
    logic                 wb_enq, wb_full;
    logic [XLEN-1:0]      wb_enq_addr;
    logic [LINE_BITS-1:0] wb_enq_data;
    logic                 wb_rd_req, wb_rd_ready;
    logic [XLEN-1:0]      wb_rd_addr;
    logic [LINE_BITS-1:0] wb_rd_data;
    logic                 wb_empty;

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
        // Write buffer
        .wb_enq      (wb_enq),
        .wb_enq_addr (wb_enq_addr),
        .wb_enq_data (wb_enq_data),
        .wb_full     (wb_full),
        .wb_rd_req   (wb_rd_req),
        .wb_rd_addr  (wb_rd_addr),
        .wb_rd_ready (wb_rd_ready),
        .wb_rd_data  (wb_rd_data)
    );

    // ── Write buffer + main memory ────────────────────────────────────────
    // Wires between the buffer and main_mem_model
    logic                 mm_req, mm_we;
    logic [XLEN-1:0]      mm_addr;
    logic [LINE_BITS-1:0] mm_wdata;
    logic                 mm_ready;
    logic [LINE_BITS-1:0] mm_rdata;

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

    main_mem_model #(
        .XLEN      (XLEN),
        .DEPTH     (16384),
        .LINE_WORDS(LINE_WORDS),
        .LINE_BITS (LINE_BITS),
        .LATENCY   (MM_LATENCY)
    ) u_mem (
        .clk  (clk),
        .rst  (rst),
        .req  (mm_req),
        .we   (mm_we),
        .addr (mm_addr),
        .wdata(mm_wdata),
        .ready(mm_ready),
        .rdata(mm_rdata)
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

    // Wait in a loop until l1_do_fill goes high.
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
    endtask

    // ── Event monitors ────────────────────────────────────────────────────
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
        check  ("wb_enq=0",              wb_enq,      1'b0);
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
        check  ("wb_enq=0",             wb_enq,           1'b0);
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
        $display("\n=== TC4: L1 miss -> L2 hit (clean L1 victim) ===");
        begin
            logic [LINE_BITS-1:0] l2_line;
            int cycles;
            l2_line = make_line(32'hBB00_0000);

            @(negedge clk);
            addr            = 32'h0000_0200;
            mem_read        = 1'b1;
            l1_hit          = 1'b0;
            l1_victim_dirty = 1'b0;
            l1_victim_way   = 1'b1;
            l2_hit          = 1'b1;
            l2_hit_way      = 2'd2;
            l2_hit_rdata_line = l2_line;

            @(posedge clk); #1;
            mem_read = 1'b0;
            check("stall during miss", cache_stall, 1'b1);

            wait_for_l1_fill(cycles);
            $display("  [INFO] cycles to L1_FILL = %0d (expected 2: L2_LOOKUP+L1_FILL)", cycles);

            check("l1_do_fill in L1_FILL",     l1_do_fill,      1'b1);
            check("l2_do_lru_update fires",    l2_do_lru_update,1'b1);
            check32("read_data = line[word0]", read_data,       32'hBB00_0000);

            @(posedge clk); #1;
            check("stall cleared",             cache_stall,     1'b0);
        end

        // ─────────────────────────────────────────────────────────────────
        $display("\n=== TC5: L1 miss -> L2 miss -> MEM fetch (all victims clean) ===");
        begin
            logic [LINE_BITS-1:0] mem_line;
            int cycles;
            mem_line = make_line(32'hCC00_0000);
            l2_fill_happened = 0;

            @(negedge clk);
            addr            = 32'h0000_030C;
            mem_read        = 1'b1;
            l1_hit          = 1'b0;
            l1_victim_dirty = 1'b0;
            l1_victim_way   = 1'b0;
            l2_hit          = 1'b0;
            l2_victim_dirty = 1'b0;

            @(posedge clk); #1;
            mem_read = 1'b0;
            check("stall=1 on miss", cache_stall, 1'b1);

            // No mm_respond helper needed: buffer+main_mem handle it automatically
            wait_for_l1_fill(cycles);

            $display("  [INFO] cycles to L1_FILL = %0d (expected ~27: L2_LOOKUP+MEM×25+L2_FILL)", cycles);
            check("l1_do_fill fires",           l1_do_fill,       1'b1);
            check("l2_do_fill happened",        l2_fill_happened, 1'b1);
            // addr[4:2] = 0x0C[4:2] = 011 = 3 -> word[3], but mem is zero-init
            // TC5 reads an all-zero memory region -> fill_line[word3]=0
            @(posedge clk); #1;
            check("stall cleared after MM", cache_stall, 1'b0);
        end

        // ─────────────────────────────────────────────────────────────────
        $display("\n=== TC6: L1 miss, dirty L1 victim -> L2 hit ===");
        begin
            logic [LINE_BITS-1:0] l2_line, dirty_line;
            int cycles;
            l2_line    = make_line(32'hDD00_0000);
            dirty_line = make_line(32'hEE00_0000);

            @(negedge clk);
            addr            = 32'h0000_0404;
            mem_read        = 1'b1;
            l1_hit          = 1'b0;
            l1_victim_dirty = 1'b1;
            l1_victim_way   = 1'b0;
            l1_victim_addr  = 32'h0000_0800;
            l1_victim_data  = dirty_line;
            l2_hit          = 1'b1;
            l2_hit_way      = 2'd1;
            l2_hit_rdata_line = l2_line;

            @(posedge clk); #1;
            mem_read = 1'b0;

            check("l2_do_write_line in L1_WRITEBACK", l2_do_write_line, 1'b1);

            wait_for_l1_fill(cycles);
            $display("  [INFO] cycles to L1_FILL = %0d (expected 3: L1_WB+L2_LOOKUP+L1_FILL)", cycles);

            check("l1_do_fill fires",         l1_do_fill,  1'b1);
            // 0x0404[4:2] = 001 -> word[1]
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
            // mem is all-zero; write-allocate fills from zero-init memory
            mem_line = '0;

            @(negedge clk);
            addr            = 32'h0000_0510;
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

            wait_for_l1_fill(cycles);

            $display("  [INFO] cycles to L1_FILL = %0d", cycles);
            check("l1_do_fill fires",      l1_do_fill,      1'b1);
            check("l1_do_write_hit fires", l1_do_write_hit, 1'b1);

            @(posedge clk); #1;
            check("stall cleared after store miss", cache_stall, 1'b0);
        end

        // ─────────────────────────────────────────────────────────────────
        $display("\n=== TC8: L1 miss -> L2 miss, dirty L2 victim (fetch first, drain background) ===");
        begin
            logic [LINE_BITS-1:0] dirty_l2, fetch_line;
            int cycles;
            int wait_t;
            dirty_l2   = make_line(32'hAA00_0000);
            fetch_line = make_line(32'h5500_0000);

            // Victim at 0x0A00 (in-range: 0xA00/4=640, fits in 16384-word memory).
            // Fetch at 0x0600 (different line, no conflict).

            @(negedge clk);
            addr            = 32'h0000_060C;
            mem_read        = 1'b1;
            l1_hit          = 1'b0;
            l1_victim_dirty = 1'b0;
            l1_victim_way   = 1'b0;
            l2_hit          = 1'b0;
            // dirty L2 victim at a DIFFERENT address than the fetch (no conflict)
            l2_victim_dirty = 1'b1;
            l2_victim_addr  = 32'h0000_0A00;
            l2_victim_data  = dirty_l2;

            // IDLE posedge: miss detected, FSM -> L2_LOOKUP
            @(posedge clk); #1;
            mem_read = 1'b0;
            check("stall=1", cache_stall, 1'b1);
            // Keep l2_victim_dirty=1 through L2_LOOKUP so wb_enq fires.

            // L2_LOOKUP posedge: wb_enq fires for the dirty victim, FSM -> MEM_FETCH
            @(posedge clk); #1;
            l2_victim_dirty = 1'b0;  // safe to clear now

            // With write buffer: FSM enqueues victim in L2_LOOKUP and goes straight
            // to MEM_FETCH. The fetch completes without waiting for the victim drain.
            // wait_for_l1_fill counts from current point; subtract 1 for the cycle spent above
            wait_for_l1_fill(cycles);

            $display("  [INFO] cycles to L1_FILL = %0d (expected ~28, NOT ~54)", cycles);
            check("l1_do_fill fires",        l1_do_fill,  1'b1);

            // Confirm fetch completed much faster than the old 2x serialized path
            if (cycles < 40)
                $display("  [PASS] fetch completed in %0d cycles (< 40, not serialized)", cycles);
            else begin
                $display("  [FAIL] fetch took %0d cycles — may be serialized (expected < 40)", cycles);
                fail_count++;
            end
            pass_count++;  // counted as part of the cycle check above
            @(posedge clk); #1;
            wait_t = 0;
            while (!wb_empty) begin
                @(posedge clk); #1;
                wait_t++;
                if (wait_t > 100) begin
                    $display("  [FAIL] TC8: victim did not drain (wb_empty never set)");
                    fail_count++;
                    wait_t = 0;
                    disable fork;
                end
            end
            $display("  [INFO] victim drained after %0d extra cycles", wait_t);
            check("TC8 buffer empty after drain", wb_empty, 1'b1);

            // Verify the victim data landed in memory by reading it back via buffer
            begin
                logic                 old_req;
                logic [LINE_BITS-1:0] mem_content;
                // Direct: issue a read request for the victim address
                @(negedge clk);
                // Use a simple poll: issue wb_rd_req directly to the buffer
                // by driving cache_ctrl into MEM_FETCH via a fake miss at victim addr.
                // Simpler: just check memory array directly in the model.
                mem_content = '0;
                begin
                    int wi;
                    // Victim was at 0x0A00; word index = 0xA00/4 = 640
                    for (wi = 0; wi < LINE_WORDS; wi = wi + 1)
                        mem_content[wi*32 +: 32] = u_mem.memory[32'h0000_0A00/4 + wi];
                end
                if (mem_content === dirty_l2) begin
                    $display("  [PASS] TC8 victim data correct in memory");
                    pass_count++;
                end else begin
                    $display("  [FAIL] TC8 victim in memory: got[31:0]=%08h exp[31:0]=%08h",
                             mem_content[31:0], dirty_l2[31:0]);
                    fail_count++;
                end
            end

            @(posedge clk); #1;
            check("stall cleared after TC8", cache_stall, 1'b0);
        end

        // ─────────────────────────────────────────────────────────────────
        $display("\n=== TC9: Drain-on-conflict — victim addr == fetch addr ===");
        begin
            logic [LINE_BITS-1:0] dirty_l2, rline;
            int cycles;
            int wait_t;
            // Use address 0x0C00: victim is a dirty entry at the same line as fetch.
            dirty_l2 = make_line(32'hBB11_0000);

            // Enqueue the victim via a fake L2 miss at the SAME address we then fetch.
            // Keep l2_victim_dirty=1 through BOTH the IDLE and L2_LOOKUP posedges.
            @(negedge clk);
            addr            = 32'h0000_0C00;
            mem_read        = 1'b1;
            l1_hit          = 1'b0;
            l1_victim_dirty = 1'b0;
            l1_victim_way   = 1'b0;
            l2_hit          = 1'b0;
            l2_victim_dirty = 1'b1;
            l2_victim_addr  = 32'h0000_0C00;  // SAME line as the fetch
            l2_victim_data  = dirty_l2;

            // IDLE posedge: FSM detects miss, latches, goes to L2_LOOKUP
            @(posedge clk); #1;
            mem_read = 1'b0;
            check("TC9 stall=1", cache_stall, 1'b1);
            // Keep l2_victim_dirty=1 through L2_LOOKUP posedge so wb_enq fires.

            // L2_LOOKUP posedge: wb_enq fires, FSM goes to MEM_FETCH
            @(posedge clk); #1;
            // Now safe to clear dirty flag
            l2_victim_dirty = 1'b0;

            // Buffer will detect conflict: drains victim first, then reads.
            // The read returns the data that was just written.
            wait_for_l1_fill(cycles);
            $display("  [INFO] TC9 cycles to L1_FILL = %0d (expected ~54: drain+fetch)", cycles);
            check("TC9 l1_do_fill fires", l1_do_fill, 1'b1);

            // The fill line should contain the dirty_l2 data (written then read back)
            begin
                logic [LINE_BITS-1:0] filled;
                filled = l1_fill_data;
                if (filled === dirty_l2) begin
                    $display("  [PASS] TC9 conflict-drain: fill line matches evicted data");
                    pass_count++;
                end else begin
                    $display("  [FAIL] TC9 fill_data[31:0]=%08h exp[31:0]=%08h",
                             filled[31:0], dirty_l2[31:0]);
                    fail_count++;
                end
            end

            @(posedge clk); #1;
            check("TC9 stall cleared", cache_stall, 1'b0);
        end

        // ─────────────────────────────────────────────────────────────────
        $display("\n============================================");
        $display(" RESULT: %0d PASS  /  %0d FAIL", pass_count, fail_count);
        $display("============================================\n");

        if (fail_count == 0)
            $display(" [OK] tb_cache_ctrl: all cases passed.");
        else
            $display(" [ERROR] tb_cache_ctrl: %0d case(s) failed.", fail_count);

        $finish;
    end

endmodule
