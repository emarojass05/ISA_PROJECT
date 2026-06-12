// =============================================================================
// tb_cache_hierarchy.sv
//
// Self-checking testbench for cache_hierarchy.
// Compatible with iverilog -g2012 (no 'automatic' tasks, no local variables
// inside named begin-end blocks, no 'int' in task ports).
//
// Test cases
// ──────────
//  TC-1  Bypass mode   (cache_enable=0): write then read-back
//  TC-2  Cold miss:    write + read through L1-miss -> L2-miss -> DRAM
//  TC-3  Hit after fill: second read to the same line
//  TC-4  Multiple sets: stress 8 distinct L1 sets (stride 256 B)
//  TC-5  Write overwrite (write-hit): latest value must survive
//  TC-6  cache_enable toggle 1->0->1: cached state must persist
//  TC-7  Reset: cache_stall must be 0 with no pending request
// =============================================================================

`timescale 1ns / 1ps

module tb_cache_hierarchy;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam XLEN        = 32;
    localparam LINE_WORDS  = 8;
    localparam LINE_BITS   = LINE_WORDS * 32;
    localparam L1_SETS     = 64;
    localparam L2_SETS     = 128;
    localparam MEM_DEPTH   = 16384;
    localparam MEM_LATENCY = 25;

    localparam CLK_HALF   = 5;             // half-period in ns (100 MHz)
    localparam CLK_PERIOD = CLK_HALF * 2;
    localparam RST_CYCLES = 6;

    // Per-operation stall timeout: worst case = 2 × DRAM latency + FSM margin
    localparam OP_TIMEOUT = MEM_LATENCY * 4 + 20;

    // Global watchdog budget in ns
    localparam WD_NS = CLK_PERIOD * (RST_CYCLES * 2 + 8 * 8 * OP_TIMEOUT + 200);

    // =========================================================================
    // DUT signals
    // =========================================================================
    reg              clk;
    reg              rst;
    reg              cache_enable;
    reg              mem_read;
    reg              mem_write;
    reg  [XLEN-1:0] addr;
    reg  [31:0]     write_data;
    wire [31:0]     read_data;
    wire            cache_stall;

    // =========================================================================
    // DUT instantiation
    // =========================================================================
    cache_hierarchy #(
        .XLEN       (XLEN),
        .LINE_WORDS (LINE_WORDS),
        .LINE_BITS  (LINE_BITS),
        .L1_SETS    (L1_SETS),
        .L2_SETS    (L2_SETS),
        .MEM_DEPTH  (MEM_DEPTH),
        .MEM_LATENCY(MEM_LATENCY)
    ) dut (
        .clk         (clk),
        .rst         (rst),
        .cache_enable(cache_enable),
        .mem_read    (mem_read),
        .mem_write   (mem_write),
        .addr        (addr),
        .write_data  (write_data),
        .read_data   (read_data),
        .cache_stall (cache_stall)
    );
    defparam dut.u_main_mem.INIT_FILE = "";

    // =========================================================================
    // Clock
    // =========================================================================
    initial clk = 1'b0;
    always  #CLK_HALF clk = ~clk;

    // =========================================================================
    // Scoreboard counters
    // =========================================================================
    integer n_tests  = 0;
    integer n_passed = 0;
    integer n_failed = 0;

    // =========================================================================
    // Module-level temporaries
    // 'automatic' tasks are not supported by iverilog, so all variables that
    // would otherwise be task-local live here instead.
    // =========================================================================
    integer      cyc;        // stall cycle counter used inside do_read / do_write
    reg [31:0]   cap_rdata;  // captured read_data
    reg          ok;         // generic ok flag
    reg          ok_w;       // write-operation ok flag
    reg          ok_r;       // read-operation  ok flag
    integer      lp_i;       // loop index  (TC-4)
    reg [XLEN-1:0] lp_addr; // loop address (TC-4)
    reg [31:0]   lp_data;   // loop data    (TC-4)

    // =========================================================================
    // Task: apply_reset
    // =========================================================================
    task apply_reset;
        begin
            rst          = 1'b1;
            cache_enable = 1'b0;
            mem_read     = 1'b0;
            mem_write    = 1'b0;
            addr         = {XLEN{1'b0}};
            write_data   = 32'h0;
            repeat (RST_CYCLES) @(posedge clk);
            @(negedge clk);
            rst = 1'b0;
            $display("[TB]  Reset released  t=%0t", $time);
        end
    endtask

    // =========================================================================
    // Task: do_write
    //   Issues a store request; holds inputs while cache_stall is high.
    //   Sets op_ok=1 on success, op_ok=0 on timeout.
    // =========================================================================
    task do_write;
        input  [XLEN-1:0] a;
        input  [31:0]     wdata;
        output            op_ok;
        begin
            @(negedge clk);
            mem_read   = 1'b0;
            mem_write  = 1'b1;
            addr       = a;
            write_data = wdata;

            cyc   = 0;
            op_ok = 1'b1;
            @(posedge clk);
            while (cache_stall && op_ok) begin
                cyc = cyc + 1;
                if (cyc >= OP_TIMEOUT) begin
                    $display("[TB]  TIMEOUT  do_write @0x%08h  (stall>%0d cycles)",
                             a, OP_TIMEOUT);
                    op_ok = 1'b0;
                end else
                    @(posedge clk);
            end
            @(negedge clk);
            mem_write = 1'b0;
        end
    endtask

    // =========================================================================
    // Task: do_read
    //   Issues a load request; holds inputs while cache_stall is high.
    //   Captures read_data on the rising edge where stall first drops.
    //   Sets op_ok=1 on success, op_ok=0 on timeout.
    // =========================================================================
    task do_read;
        input  [XLEN-1:0] a;
        output [31:0]     rdata;
        output            op_ok;
        begin
            @(negedge clk);
            mem_read  = 1'b1;
            mem_write = 1'b0;
            addr      = a;

            cyc   = 0;
            op_ok = 1'b1;
            rdata = 32'h0;
            @(posedge clk);
            while (cache_stall && op_ok) begin
                cyc = cyc + 1;
                if (cyc >= OP_TIMEOUT) begin
                    $display("[TB]  TIMEOUT  do_read @0x%08h  (stall>%0d cycles)",
                             a, OP_TIMEOUT);
                    op_ok = 1'b0;
                    rdata = 32'hx;
                end else
                    @(posedge clk);
            end
            if (op_ok) rdata = read_data; // sample on the posedge where stall drops
            @(negedge clk);
            mem_read = 1'b0;
        end
    endtask

    // =========================================================================
    // Task: idle  —  advance N cycles with no request on the bus
    // =========================================================================
    task idle;
        input integer n;
        repeat (n) @(posedge clk);
    endtask

    // =========================================================================
    // Task: check_val  —  compare got vs expected and update scoreboard
    //   op_ok : 1 = operation completed successfully, 0 = timed out
    // =========================================================================
    task check_val;
        input string  lbl;
        input         op_ok;
        input [31:0]  got;
        input [31:0]  exp;
        begin
            n_tests = n_tests + 1;
            if (!op_ok) begin
                $display("[FAIL]  %-52s  timed out", lbl);
                n_failed = n_failed + 1;
            end else if (got !== exp) begin
                $display("[FAIL]  %-52s  exp=0x%08h  got=0x%08h", lbl, exp, got);
                n_failed = n_failed + 1;
            end else begin
                $display("[PASS]  %-52s  0x%08h", lbl, got);
                n_passed = n_passed + 1;
            end
        end
    endtask

    // =========================================================================
    // Task: check_op  —  verify only that an operation completed (no data cmp)
    // =========================================================================
    task check_op;
        input string lbl;
        input        op_ok;
        begin
            n_tests = n_tests + 1;
            if (!op_ok) begin
                $display("[FAIL]  %-52s  timed out", lbl);
                n_failed = n_failed + 1;
            end else begin
                $display("[PASS]  %-52s", lbl);
                n_passed = n_passed + 1;
            end
        end
    endtask

    // =========================================================================
    // Main stimulus
    // =========================================================================
    initial begin
        $dumpfile("tb_cache_hierarchy.vcd");
        $dumpvars(0, tb_cache_hierarchy);

        $display("============================================================");
        $display("  tb_cache_hierarchy  start  (t=%0t)", $time);
        $display("============================================================");

        apply_reset();
        idle(2);

        // ── TC-1  Bypass mode (cache_enable = 0) ─────────────────────────────
        $display("\n-- TC-1  Bypass mode (cache_enable=0) --");
        cache_enable = 1'b0;

        do_write(32'h0000_0010, 32'hDEAD_BEEF, ok_w);
        do_read (32'h0000_0010, cap_rdata,     ok_r);
        check_val("TC-1a bypass write->read addr=0x0010",
                  ok_w & ok_r, cap_rdata, 32'hDEAD_BEEF);

        do_write(32'h0000_0020, 32'hCAFE_F00D, ok_w);
        do_read (32'h0000_0020, cap_rdata,     ok_r);
        check_val("TC-1b bypass write->read addr=0x0020",
                  ok_w & ok_r, cap_rdata, 32'hCAFE_F00D);

        do_read(32'h0000_0010, cap_rdata, ok_r);
        check_val("TC-1c bypass re-read addr=0x0010 (isolation)",
                  ok_r, cap_rdata, 32'hDEAD_BEEF);

        idle(2);

        // ── TC-2  Cache enabled — cold miss ───────────────────────────────────
        $display("\n-- TC-2  Cache enabled — cold miss --");
        cache_enable = 1'b1;

        do_write(32'h0000_0100, 32'hA5A5_5A5A, ok_w);
        check_op("TC-2a cold miss write addr=0x0100", ok_w);

        do_read(32'h0000_0100, cap_rdata, ok_r);
        check_val("TC-2b cold miss read-back addr=0x0100",
                  ok_r, cap_rdata, 32'hA5A5_5A5A);

        idle(2);

        // ── TC-3  Cache hit after fill ────────────────────────────────────────
        $display("\n-- TC-3  Cache hit after fill --");
        cache_enable = 1'b1;

        do_write(32'h0000_0200, 32'h1234_5678, ok_w);
        check_op("TC-3a fill — write addr=0x0200", ok_w);

        do_read(32'h0000_0200, cap_rdata, ok_r);
        check_val("TC-3b first read (fill) addr=0x0200",
                  ok_r, cap_rdata, 32'h1234_5678);

        do_read(32'h0000_0200, cap_rdata, ok);
        check_val("TC-3c second read (hit)  addr=0x0200",
                  ok, cap_rdata, 32'h1234_5678);

        idle(2);

        // ── TC-4  Multiple cache sets (stride 256 B) ──────────────────────────
        // 256-byte stride guarantees distinct L1 set indices (6-bit index field).
        $display("\n-- TC-4  Multiple cache sets (stride 256B) --");
        cache_enable = 1'b1;
        for (lp_i = 0; lp_i < 8; lp_i = lp_i + 1) begin
            lp_addr = 32'h0000_1000 + (lp_i * 32'h100);
            lp_data = 32'hBEEF_0000 | lp_i[31:0];
            do_write(lp_addr, lp_data, ok_w);
            do_read (lp_addr, cap_rdata, ok_r);
            check_val($sformatf("TC-4 set stress addr=0x%08h", lp_addr),
                      ok_w & ok_r, cap_rdata, lp_data);
        end

        idle(2);

        // ── TC-5  Write overwrite (write-hit) ─────────────────────────────────
        $display("\n-- TC-5  Write overwrite (write-hit) --");
        cache_enable = 1'b1;

        do_write(32'h0000_0300, 32'h1111_1111, ok);
        check_op("TC-5a first  write addr=0x0300", ok);

        do_write(32'h0000_0300, 32'h2222_2222, ok);
        check_op("TC-5b second write addr=0x0300 (overwrite)", ok);

        do_read(32'h0000_0300, cap_rdata, ok);
        check_val("TC-5c read-back after overwrite addr=0x0300",
                  ok, cap_rdata, 32'h2222_2222);

        idle(2);

        // ── TC-6  cache_enable toggle 1 -> 0 -> 1 ────────────────────────────
        $display("\n-- TC-6  cache_enable 1->0->1 (cache state persists) --");
        cache_enable = 1'b1;

        do_write(32'h0000_0400, 32'hFACE_CAFE, ok);
        check_op("TC-6a cache write addr=0x0400", ok);

        do_read(32'h0000_0400, cap_rdata, ok);
        check_val("TC-6b cache initial read addr=0x0400",
                  ok, cap_rdata, 32'hFACE_CAFE);

        cache_enable = 1'b0;
        do_write(32'h0000_0008, 32'hDEAD_C0DE, ok);
        check_op("TC-6c bypass write (unrelated) addr=0x0008", ok);

        cache_enable = 1'b1;
        do_read(32'h0000_0400, cap_rdata, ok);
        check_val("TC-6d cache re-read after bypass addr=0x0400",
                  ok, cap_rdata, 32'hFACE_CAFE);

        idle(2);

        // ── TC-7  Reset clears pending stall ──────────────────────────────────
        $display("\n-- TC-7  Reset: stall must be 0 with no pending request --");
        apply_reset();
        idle(1);
        @(posedge clk);
        n_tests = n_tests + 1;
        if (cache_stall !== 1'b0) begin
            $display("[FAIL]  TC-7  cache_stall not deasserted after reset");
            n_failed = n_failed + 1;
        end else begin
            $display("[PASS]  TC-7  cache_stall = 0 after reset with no request");
            n_passed = n_passed + 1;
        end

        // ── Summary ───────────────────────────────────────────────────────────
        idle(4);
        $display("\n============================================================");
        $display("  RESULTS: %0d / %0d tests passed", n_passed, n_tests);
        if (n_failed == 0)
            $display("  *** ALL TESTS PASSED ***");
        else
            $display("  *** %0d TEST(S) FAILED ***", n_failed);
        $display("============================================================");
        $finish;
    end

    // =========================================================================
    // Global watchdog  —  kills simulation if it hangs longer than WD_NS
    // =========================================================================
    initial begin
        #WD_NS;
        $fatal(1, "[TB]  Watchdog fired after %0d ns — deadlock suspected", WD_NS);
    end

endmodule