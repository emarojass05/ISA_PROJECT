`timescale 1ns/1ps

import isa_defs::*;

module tb_alu;

    localparam int XLEN = 32;

    logic [XLEN-1:0] a;
    logic [XLEN-1:0] b;
    alu_op_t         alu_op;
    logic [XLEN-1:0] result;
    logic            zero_fl;
    logic            negative_fl;
    logic            carry_fl;
    logic            overflow_fl;

    int errors;

    alu #(
        .XLEN(XLEN)
    ) dut (
        .a(a),
        .b(b),
        .alu_op(alu_op),
        .result(result),
        .zero_fl(zero_fl),
        .negative_fl(negative_fl),
        .carry_fl(carry_fl),
        .overflow_fl(overflow_fl)
    );

    task automatic check_result(
        input alu_op_t         op,
        input logic [XLEN-1:0] lhs,
        input logic [XLEN-1:0] rhs,
        input logic [XLEN-1:0] expected,
        input string           test_name
    );
        begin
            a = lhs;
            b = rhs;
            alu_op = op;
            #1;

            if (result !== expected) begin
                $display("FAIL %-24s result=%h expected=%h", test_name, result, expected);
                errors++;
            end else begin
                $display("PASS %-24s result=%h", test_name, result);
            end
        end
    endtask

    task automatic check_flags(
        input string test_name,
        input logic expected_zero,
        input logic expected_negative
    );
        begin
            #1;

            if (zero_fl !== expected_zero) begin
                $display("FAIL %-24s zero_fl=%b expected=%b", test_name, zero_fl, expected_zero);
                errors++;
            end

            if (negative_fl !== expected_negative) begin
                $display("FAIL %-24s negative_fl=%b expected=%b", test_name, negative_fl, expected_negative);
                errors++;
            end
        end
    endtask

    initial begin
        errors = 0;

        // Arithmetic
        check_result(ALU_ADD,  32'd10,        32'd5,         32'd15,        "add");
        check_result(ALU_SUB,  32'd10,        32'd5,         32'd5,         "sub");
        check_result(ALU_MUL,  32'd7,         32'd6,         32'd42,        "mul");
        check_result(ALU_DIV,  32'd20,        32'd4,         32'd5,         "div");
        check_result(ALU_REM,  32'd22,        32'd5,         32'd2,         "rem");

        // Signed arithmetic
        check_result(ALU_MUL,  32'hFFFF_FFFE, 32'd3,         32'hFFFF_FFFA, "mul signed");
        check_result(ALU_DIV,  32'hFFFF_FFF6, 32'd2,         32'hFFFF_FFFB, "div signed");
        check_result(ALU_REM,  32'hFFFF_FFF7, 32'd4,         32'hFFFF_FFFF, "rem signed");

        // Division by zero
        check_result(ALU_DIV,  32'd20,        32'd0,         32'd0,         "div by zero");
        check_result(ALU_REM,  32'd20,        32'd0,         32'd0,         "rem by zero");

        // Logic
        check_result(ALU_AND,  32'hF0F0_00FF, 32'h0F0F_0FFF, 32'h0000_00FF, "and");
        check_result(ALU_OR,   32'hF0F0_00FF, 32'h0F0F_0FFF, 32'hFFFF_0FFF, "or");
        check_result(ALU_XOR,  32'hAAAA_5555, 32'hFFFF_0000, 32'h5555_5555, "xor");

        // Shifts
        check_result(ALU_SLL,  32'h0000_0001, 32'd4,         32'h0000_0010, "sll");
        check_result(ALU_SRL,  32'h8000_0000, 32'd4,         32'h0800_0000, "srl logical");

        // U-type helpers
        check_result(ALU_LUHW, 32'hAAAA_5678, 32'h1234_0000, 32'h1234_5678, "luhw merge");
        check_result(ALU_LLHW, 32'h1234_AAAA, 32'h0000_BEEF, 32'h1234_BEEF, "llhw merge");

        // Flags
        check_result(ALU_SUB,  32'd5,         32'd5,         32'd0,         "zero flag source");
        check_flags("zero flag", 1'b1, 1'b0);

        check_result(ALU_SUB,  32'd5,         32'd10,        32'hFFFF_FFFB, "negative flag source");
        check_flags("negative flag", 1'b0, 1'b1);

        if (errors == 0) begin
            $display("ALU TEST PASSED");
        end else begin
            $display("ALU TEST FAILED: %0d error(s)", errors);
        end

        $finish;
    end

endmodule