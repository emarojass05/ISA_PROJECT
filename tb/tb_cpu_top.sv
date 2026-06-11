`timescale 1ns/1ps

module tb_cpu_top;

    localparam int XLEN       = 32;
    localparam int IMEM_DEPTH = 64;
    localparam int DMEM_DEPTH = 64;
    localparam int CACHE_ENABLE = 1;

    logic clk;
    logic rst;

    int errors;

    cpu_top #(
        .XLEN(XLEN),
        .IMEM_DEPTH(IMEM_DEPTH),
        .DMEM_DEPTH(DMEM_DEPTH),
        .CACHE_ENABLE(CACHE_ENABLE),
        .INITIAL_MEM("")
    ) dut (
        .clk(clk),
        .rst(rst)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        #1000;
        $display("FAIL timeout");
        $finish;
    end

    task automatic check_value(
        input logic [XLEN-1:0] actual,
        input logic [XLEN-1:0] expected,
        input string           test_name
    );
        begin
            if (actual !== expected) begin
                $display("FAIL %-24s actual=%h expected=%h", test_name, actual, expected);
                errors++;
            end else begin
                $display("PASS %-24s value=%h", test_name, actual);
            end
        end
    endtask

    initial begin
        $display("CPU TOP TEST START");

        errors = 0;
        rst = 1'b1;

        #12;
        check_value(dut.pc_cur, 32'h0000_0000, "pc reset");

        rst = 1'b0;

        // Due to negedge writting chech for luhw is ommited
        @(negedge clk);
        #1;
        //check_value(dut.u_rf.registers[5], 32'h1234_0000, "luhw x5");

        @(negedge clk);
        #1;
        check_value(dut.u_rf.registers[5], 32'h1234_ABCD, "llhw x5");

        @(negedge clk);
        #1;
        check_value(dut.u_rf.registers[6], 32'h0000_000A, "addi x6");

        @(negedge clk);
        #1;
        check_value(dut.u_rf.registers[7], 32'h1234_ABD7, "add x7");

        @(posedge clk);
        #1;
        check_value(dut.u_dmem.memory[0], 32'h1234_ABD7, "sw mem[0]");

        @(negedge clk);
        #1;
        check_value(dut.u_rf.registers[8], 32'h1234_ABD7, "lw x8");

        @(posedge clk);
        #1;
        check_value(dut.pc_cur, 32'h0000_0018, "pc at j");

        @(posedge clk);
        #1;
        check_value(dut.pc_cur, 32'h0000_0018, "j self loop");

        if (errors == 0) begin
            $display("CPU TOP TEST PASSED");
        end else begin
            $display("CPU TOP TEST FAILED: %0d error(s)", errors);
        end

        $finish;
    end

endmodule