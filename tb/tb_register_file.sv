`timescale 1ns/1ps

import isa_defs::*;

module tb_register_file;

    localparam int XLEN = 32;

    logic            clk;
    logic [4:0]      rs1;
    logic [4:0]      rs2;
    logic [4:0]      rs3;
    logic [XLEN-1:0] wd3;
    logic            we3;
    logic [XLEN-1:0] rd1;
    logic [XLEN-1:0] rd2;

    int errors;

    register_file #(
        .XLEN(XLEN)
    ) dut (
        .clk(clk),
        .rs1(rs1),
        .rs2(rs2),
        .rs3(rs3),
        .wd3(wd3),
        .we3(we3),
        .rd1(rd1),
        .rd2(rd2)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic check_read(
        input logic [4:0]      read_rs1,
        input logic [4:0]      read_rs2,
        input logic [XLEN-1:0] expected_rd1,
        input logic [XLEN-1:0] expected_rd2,
        input string           test_name
    );
        begin
            rs1 = read_rs1;
            rs2 = read_rs2;
            #1;

            if (rd1 !== expected_rd1) begin
                $display("FAIL %-24s rd1=%h expected=%h", test_name, rd1, expected_rd1);
                errors++;
            end

            if (rd2 !== expected_rd2) begin
                $display("FAIL %-24s rd2=%h expected=%h", test_name, rd2, expected_rd2);
                errors++;
            end

            if (rd1 === expected_rd1 && rd2 === expected_rd2) begin
                $display("PASS %-24s", test_name);
            end
        end
    endtask

    task automatic write_reg(
        input logic [4:0]      write_rs3,
        input logic [XLEN-1:0] write_wd3,
        input logic            write_we3
    );
        begin
            rs3 = write_rs3;
            wd3 = write_wd3;
            we3 = write_we3;
            @(negedge clk);
            #1;
            we3 = 1'b0;
        end
    endtask

    initial begin
        errors = 0;

        rs1 = '0;
        rs2 = '0;
        rs3 = '0;
        wd3 = '0;
        we3 = 1'b0;

        #2;

        // Hardwired reads
        check_read(R_ZERO, R_DELTA, 32'h0000_0000, 32'h9E37_79B9, "hardwired reads");

        // Basic write and readback
        write_reg(5'd5, 32'h1234_5678, 1'b1);
        check_read(5'd5, R_ZERO, 32'h1234_5678, 32'h0000_0000, "write x5");

        write_reg(5'd6, 32'hABCD_EF01, 1'b1);
        check_read(5'd5, 5'd6, 32'h1234_5678, 32'hABCD_EF01, "read x5 x6");

        // Disabled write
        write_reg(5'd7, 32'hCAFE_BABE, 1'b0);
        check_read(5'd7, R_ZERO, 32'h0000_0000, 32'h0000_0000, "disabled write");

        // Overwrite normal register
        write_reg(5'd5, 32'hDEAD_BEEF, 1'b1);
        check_read(5'd5, 5'd6, 32'hDEAD_BEEF, 32'hABCD_EF01, "overwrite x5");

        // Ignore writes to x0
        write_reg(R_ZERO, 32'hFFFF_FFFF, 1'b1);
        check_read(R_ZERO, 5'd5, 32'h0000_0000, 32'hDEAD_BEEF, "ignore write x0");

        // Ignore writes to x30
        write_reg(R_DELTA, 32'h0000_0000, 1'b1);
        check_read(R_DELTA, 5'd6, 32'h9E37_79B9, 32'hABCD_EF01, "ignore write x30");

        // Simultaneous independent read ports
        check_read(5'd6, 5'd5, 32'hABCD_EF01, 32'hDEAD_BEEF, "dual read ports");

        if (errors == 0) begin
            $display("REGISTER FILE TEST PASSED");
        end else begin
            $display("REGISTER FILE TEST FAILED: %0d error(s)", errors);
        end

        $finish;
    end

endmodule