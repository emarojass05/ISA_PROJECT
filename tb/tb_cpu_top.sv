`timescale 1ns/1ps

module tb_cpu_top;

    localparam int XLEN         = 32;
    localparam int IMEM_DEPTH   = 64;
    localparam int DMEM_DEPTH   = 64;
    localparam int CACHE_ENABLE = 0;

    logic clk;
    logic rst;

    integer errors;

    cpu_top #(
        .XLEN        (XLEN),
        .IMEM_DEPTH  (IMEM_DEPTH),
        .DMEM_DEPTH  (DMEM_DEPTH),
        .CACHE_ENABLE(CACHE_ENABLE),
        .PROGRAM_FILE(""),
        .INITIAL_MEM ("")
    ) dut (
        .clk(clk),
        .rst(rst)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        #5000;
        $display("FAIL timeout");
        $finish;
    end

    task check_value;
        input [XLEN-1:0] actual;
        input [XLEN-1:0] expected;
        input [8*40-1:0] test_name;
        begin
            if (actual !== expected) begin
                $display("FAIL %-40s actual=%h expected=%h",
                         test_name, actual, expected);
                errors = errors + 1;
            end else begin
                $display("PASS %-40s value=%h", test_name, actual);
            end
        end
    endtask

    task wait_cycles;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                @(posedge clk);
            end
            #1;
        end
    endtask

    initial begin
        $dumpfile("tb_cpu_top.vcd");
        $dumpvars(0, tb_cpu_top);

        $display("CPU TOP TEST START");

        errors = 0;
        rst    = 1'b1;

        #1;

        //
        // 0x00: luhw x5, 0x1234      -> x5 = 0x12340000
        // 0x04: llhw x5, 0xABCD      -> x5 = 0x1234ABCD
        // 0x08: addi x6, x0, 10      -> x6 = 10
        // 0x0C: add  x7, x5, x6      -> x7 = 0x1234ABD7
        // 0x10: sw   x7, 0(x0)       -> mem[0] = x7
        // 0x14: lw   x8, 0(x0)       -> x8 = mem[0]
        // 0x18: j    0               -> self-loop
        dut.u_imem.memory[0] = 32'h12340285;
        dut.u_imem.memory[1] = 32'hABCD1285;
        dut.u_imem.memory[2] = 32'h00A00301;
        dut.u_imem.memory[3] = 32'h00628380;
        dut.u_imem.memory[4] = 32'h00700002;
        dut.u_imem.memory[5] = 32'h00004403;
        dut.u_imem.memory[6] = 32'h00000007;

        #11;
        check_value(dut.if_pc_cur, 32'h0000_0000, "pc reset");

        rst = 1'b0;

        // Pipeline: give enough cycles for instructions to complete WB
        // before sampling register values.
        wait_cycles(40);

        check_value(dut.u_rf.registers[5],
                    32'h1234_ABCD,
                    "x5 after luhw/llhw");

        check_value(dut.u_rf.registers[6],
                    32'h0000_000A,
                    "x6 after addi");

        check_value(dut.u_rf.registers[7],
                    32'h1234_ABD7,
                    "x7 after add");

        check_value(dut.u_cache.bypass_mem[0],
                    32'h1234_ABD7,
                    "mem[0] after sw");

        check_value(dut.u_rf.registers[8],
                    32'h1234_ABD7,
                    "x8 after lw");

        if (errors == 0) begin
            $display("CPU TOP TEST PASSED");
        end else begin
            $display("CPU TOP TEST FAILED: %0d error(s)", errors);
        end

        $finish;
    end

endmodule