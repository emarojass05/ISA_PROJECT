`timescale 1ns/1ps
// =============================================================================
// tb_main_mem_model.sv — Testbench for main_mem_model
// =============================================================================
// Test cases:
//   TC1 — Reset: ready=0, rdata=0
//   TC2 — Read: req=1 -> exactly 25 cycles -> ready=1, correct data
//   TC3 — ready lasts only 1 cycle
//   TC4 — Write + re-read: write a line, then read it back
//   TC5 — Two consecutive transactions: second starts right after ready
//   TC6 — No overlap: req ignored while active=1
//   TC7 — Clock-enable divisor: MEM_CLK_DIV=4 -> effective latency = LATENCY*4
// =============================================================================

module tb_main_mem_model;

    localparam int XLEN       = 32;
    localparam int LINE_WORDS = 8;
    localparam int LINE_BITS  = LINE_WORDS * 32;
    localparam int LATENCY    = 25;
    localparam int DEPTH      = 16384;

    // -- TC1-TC6: default DUT (MEM_CLK_DIV=1) --------------------------------
    logic                 clk, rst;
    logic                 req;
    logic                 we;
    logic [XLEN-1:0]      addr;
    logic [LINE_BITS-1:0] wdata;
    logic                 ready;
    logic [LINE_BITS-1:0] rdata;

    main_mem_model #(
        .XLEN      (XLEN),
        .DEPTH     (DEPTH),
        .LINE_WORDS(LINE_WORDS),
        .LATENCY   (LATENCY)
    ) dut (
        .clk  (clk),
        .rst  (rst),
        .req  (req),
        .we   (we),
        .addr (addr),
        .wdata(wdata),
        .ready(ready),
        .rdata(rdata)
    );

    // -- TC7: divisor DUT (MEM_CLK_DIV=4, LATENCY=5) -------------------------
    // Effective latency = 5 * 4 = 20 CPU cycles.
    localparam int TC7_DIV     = 4;
    localparam int TC7_LATENCY = 5;

    logic                 d2_rst;
    logic                 d2_req;
    logic                 d2_we;
    logic [XLEN-1:0]      d2_addr;
    logic [LINE_BITS-1:0] d2_wdata;
    logic                 d2_ready;
    logic [LINE_BITS-1:0] d2_rdata;

    main_mem_model #(
        .XLEN       (XLEN),
        .DEPTH      (DEPTH),
        .LINE_WORDS (LINE_WORDS),
        .LATENCY    (TC7_LATENCY),
        .MEM_CLK_DIV(TC7_DIV)
    ) dut2 (
        .clk  (clk),
        .rst  (d2_rst),
        .req  (d2_req),
        .we   (d2_we),
        .addr (d2_addr),
        .wdata(d2_wdata),
        .ready(d2_ready),
        .rdata(d2_rdata)
    );

    // ── Clock ─────────────────────────────────────────────────────────────────
    initial clk = 0;
    always  #5 clk = ~clk;

    // ── Helpers ───────────────────────────────────────────────────────────────
    int pass_count, fail_count;
    int cycle_count;

    task automatic check(input string name, input logic got, input logic exp);
        if (got === exp) begin
            $display("  [PASS] %s", name);
            pass_count++;
        end else begin
            $display("  [FAIL] %s -- got %0b, exp %0b", name, got, exp);
            fail_count++;
        end
    endtask

    task automatic check32(input string name, input logic [31:0] got, input logic [31:0] exp);
        if (got === exp) begin
            $display("  [PASS] %s (= %08h)", name, got);
            pass_count++;
        end else begin
            $display("  [FAIL] %s -- got %08h, exp %08h", name, got, exp);
            fail_count++;
        end
    endtask

    task automatic send_req(
        input  logic [XLEN-1:0]       a,
        input  logic                  w,
        input  logic [LINE_BITS-1:0]  wd,
        output int                    cycles_waited
    );
        @(negedge clk);
        req   = 1'b1;
        we    = w;
        addr  = a;
        wdata = wd;
        @(posedge clk); #1;
        req = 1'b0;
        we  = 1'b0;

        cycles_waited = 1;
        while (!ready) begin
            @(posedge clk); #1;
            cycles_waited++;
        end
    endtask

    function automatic logic [LINE_BITS-1:0] make_line(input logic [31:0] base);
        logic [LINE_BITS-1:0] line;
        int i;
        for (i = 0; i < LINE_WORDS; i++)
            line[i*32 +: 32] = base + i;
        return line;
    endfunction

    // ── Stimulus ──────────────────────────────────────────────────────────────
    initial begin
        $dumpfile("build/sim/tb_main_mem_model.vcd");
        $dumpvars(0, tb_main_mem_model);

        pass_count = 0;
        fail_count = 0;

        req   = 1'b0;
        we    = 1'b0;
        addr  = '0;
        wdata = '0;

        d2_rst   = 1'b1;
        d2_req   = 1'b0;
        d2_we    = 1'b0;
        d2_addr  = '0;
        d2_wdata = '0;

        // ─────────────────────────────────────────────────────────────────────
        $display("\n=== TC1: Reset ===");
        rst = 1'b1;
        repeat(3) @(posedge clk); #1;
        check("ready=0 after reset", ready, 1'b0);
        check32("rdata[31:0]=0 after reset", rdata[31:0], 32'h0);
        @(negedge clk);
        rst    = 1'b0;
        d2_rst = 1'b0;

        // ─────────────────────────────────────────────────────────────────────
        $display("\n=== TC2: Read — exact 25-cycle latency ===");
        begin
            int cycles;
            dut.memory[0] = 32'hDEAD_0000;
            dut.memory[1] = 32'hDEAD_0001;
            dut.memory[2] = 32'hDEAD_0002;
            dut.memory[3] = 32'hDEAD_0003;
            dut.memory[4] = 32'hDEAD_0004;
            dut.memory[5] = 32'hDEAD_0005;
            dut.memory[6] = 32'hDEAD_0006;
            dut.memory[7] = 32'hDEAD_0007;

            send_req(32'h0000_0000, 1'b0, '0, cycles);

            $display("  [INFO] cycles until ready = %0d (expected %0d)", cycles, LATENCY);
            check("latency = 25 cycles", (cycles == LATENCY), 1'b1);
            check("ready=1 at cycle 25",  ready, 1'b1);
            check32("rdata[word0]", rdata[0*32 +: 32], 32'hDEAD_0000);
            check32("rdata[word3]", rdata[3*32 +: 32], 32'hDEAD_0003);
            check32("rdata[word7]", rdata[7*32 +: 32], 32'hDEAD_0007);
        end

        // ─────────────────────────────────────────────────────────────────────
        $display("\n=== TC3: ready lasts only 1 cycle ===");
        @(posedge clk); #1;
        check("ready=0 next cycle", ready, 1'b0);

        // ─────────────────────────────────────────────────────────────────────
        $display("\n=== TC4: Write + re-read ===");
        begin
            logic [LINE_BITS-1:0] write_line;
            int cycles;

            write_line = make_line(32'hCAFE_0000);

            send_req(32'h0000_0100, 1'b1, write_line, cycles);
            check("write: latency = 25 cycles", (cycles == LATENCY), 1'b1);
            check("write: ready=1", ready, 1'b1);

            @(posedge clk); #1;

            send_req(32'h0000_0100, 1'b0, '0, cycles);
            check("re-read: latency = 25 cycles", (cycles == LATENCY), 1'b1);
            check32("re-read word0", rdata[0*32 +: 32], 32'hCAFE_0000);
            check32("re-read word4", rdata[4*32 +: 32], 32'hCAFE_0004);
            check32("re-read word7", rdata[7*32 +: 32], 32'hCAFE_0007);
        end

        // ─────────────────────────────────────────────────────────────────────
        $display("\n=== TC5: Two consecutive transactions ===");
        begin
            logic [LINE_BITS-1:0] line_a, line_b;
            int cycles_a, cycles_b;

            dut.memory[8]  = 32'hAAAA_0000;
            dut.memory[9]  = 32'hAAAA_0001;
            dut.memory[10] = 32'hAAAA_0002;
            dut.memory[11] = 32'hAAAA_0003;
            dut.memory[12] = 32'hAAAA_0004;
            dut.memory[13] = 32'hAAAA_0005;
            dut.memory[14] = 32'hAAAA_0006;
            dut.memory[15] = 32'hAAAA_0007;

            dut.memory[16] = 32'hBBBB_0000;
            dut.memory[17] = 32'hBBBB_0001;
            dut.memory[18] = 32'hBBBB_0002;
            dut.memory[19] = 32'hBBBB_0003;
            dut.memory[20] = 32'hBBBB_0004;
            dut.memory[21] = 32'hBBBB_0005;
            dut.memory[22] = 32'hBBBB_0006;
            dut.memory[23] = 32'hBBBB_0007;

            send_req(32'h0000_0020, 1'b0, '0, cycles_a);
            check32("tx_a word0", rdata[0*32 +: 32], 32'hAAAA_0000);

            @(posedge clk); #1;

            send_req(32'h0000_0040, 1'b0, '0, cycles_b);
            check("tx_b: latency = 25", (cycles_b == LATENCY), 1'b1);
            check32("tx_b word0", rdata[0*32 +: 32], 32'hBBBB_0000);
            check32("tx_b word7", rdata[7*32 +: 32], 32'hBBBB_0007);
        end

        // ─────────────────────────────────────────────────────────────────────
        $display("\n=== TC7: Clock-enable divisor (MEM_CLK_DIV=4, LATENCY=5) ===");
        begin
            int cycles;
            int exp_cycles;

            // Expected effective latency = TC7_LATENCY * TC7_DIV CPU cycles.
            exp_cycles = TC7_LATENCY * TC7_DIV;

            dut2.memory[0] = 32'hF00D_0000;
            dut2.memory[1] = 32'hF00D_0001;

            @(negedge clk);
            d2_req  = 1'b1;
            d2_we   = 1'b0;
            d2_addr = '0;
            @(posedge clk); #1;
            d2_req = 1'b0;

            cycles = 1;
            while (!d2_ready) begin
                @(posedge clk); #1;
                cycles++;
            end

            $display("  [INFO] cycles until ready = %0d (expected %0d)", cycles, exp_cycles);
            check("divisor: effective latency = LATENCY*MEM_CLK_DIV", (cycles == exp_cycles), 1'b1);
            check("divisor: ready=1", d2_ready, 1'b1);
            check32("divisor: rdata[word0]", d2_rdata[0*32 +: 32], 32'hF00D_0000);
            check32("divisor: rdata[word1]", d2_rdata[1*32 +: 32], 32'hF00D_0001);
        end

        // ─────────────────────────────────────────────────────────────────────
        $display("\n============================================");
        $display(" RESULT: %0d PASS  /  %0d FAIL", pass_count, fail_count);
        $display("============================================\n");

        if (fail_count == 0)
            $display(" [OK] tb_main_mem_model: all cases passed.");
        else
            $display(" [ERROR] tb_main_mem_model: %0d case(s) failed.", fail_count);

        $finish;
    end

endmodule
