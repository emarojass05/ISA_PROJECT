`timescale 1ns/1ps

module tb_pc;

    localparam int XLEN = 32;

    logic            clk;
    logic            rst;
    logic [XLEN-1:0] next_pc;
    logic [XLEN-1:0] pc;

    int errors;

    pc #(
        .XLEN(XLEN)
    ) dut (
        .clk(clk),
        .rst(rst),
        .next_pc(next_pc),
        .pc(pc)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic check_pc(
        input logic [XLEN-1:0] expected_pc,
        input string           test_name
    );
        begin
            #1;

            if (pc !== expected_pc) begin
                $display("FAIL %-24s pc=%h expected=%h", test_name, pc, expected_pc);
                errors++;
            end else begin
                $display("PASS %-24s pc=%h", test_name, pc);
            end
        end
    endtask

    initial begin
        errors  = 0;
        rst     = 1'b0;
        next_pc = '0;

        #2;

        rst = 1'b1;
        #1;
        check_pc(32'h0000_0000, "async reset");

        rst = 1'b0;

        next_pc = 32'h0000_0004;
        @(posedge clk);
        check_pc(32'h0000_0004, "load pc 4");

        next_pc = 32'h0000_0010;
        @(posedge clk);
        check_pc(32'h0000_0010, "load pc 16");

        next_pc = 32'h1234_5678;
        @(posedge clk);
        check_pc(32'h1234_5678, "load arbitrary pc");

        rst = 1'b1;
        #1;
        check_pc(32'h0000_0000, "reset after load");

        if (errors == 0) begin
            $display("PC TEST PASSED");
        end else begin
            $display("PC TEST FAILED: %0d error(s)", errors);
        end

        $finish;
    end

endmodule