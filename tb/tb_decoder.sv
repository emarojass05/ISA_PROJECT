`timescale 1ns/1ps

import isa_defs::*;

module tb_decoder;

    localparam int XLEN = 32;

    logic [31:0]     instr;

    opcode_t         opcode;
    funct3_t         funct3;
    logic [6:0]      funct7;
    logic [4:0]      rs1;
    logic [4:0]      rs2;
    logic [4:0]      rd;
    logic [XLEN-1:0] imm;

    int errors;

    decoder #(
        .XLEN(XLEN)
    ) dut (
        .instr(instr),
        .opcode(opcode),
        .funct3(funct3),
        .funct7(funct7),
        .rs1(rs1),
        .rs2(rs2),
        .rd(rd),
        .imm(imm)
    );

    function automatic logic [31:0] enc_r(
        input logic [6:0] op,
        input logic [2:0] f3,
        input logic [6:0] f7,
        input logic [4:0] r_d,
        input logic [4:0] r_s1,
        input logic [4:0] r_s2
    );
        begin
            enc_r = {f7, r_s2, r_s1, f3, r_d, op};
        end
    endfunction

    function automatic logic [31:0] enc_i(
        input logic [6:0] op,
        input logic [2:0] f3,
        input logic [4:0] r_d,
        input logic [4:0] r_s1,
        input logic [11:0] imm12
    );
        begin
            enc_i = {imm12, r_s1, f3, r_d, op};
        end
    endfunction

    function automatic logic [31:0] enc_sbj(
        input logic [6:0] op,
        input logic [2:0] f3,
        input logic [4:0] r_s1,
        input logic [4:0] r_s2,
        input logic [11:0] imm12
    );
        begin
            enc_sbj = {imm12[11:5], r_s2, r_s1, f3, imm12[4:0], op};
        end
    endfunction

    function automatic logic [31:0] enc_u(
        input logic [6:0] op,
        input logic [2:0] f3,
        input logic [4:0] r_d,
        input logic [15:0] imm16
    );
        begin
            enc_u = {imm16, 1'b0, f3, r_d, op};
        end
    endfunction

    task automatic check_decode(
        input logic [31:0]     test_instr,
        input opcode_t         expected_opcode,
        input logic [2:0]      expected_funct3,
        input logic [6:0]      expected_funct7,
        input logic [4:0]      expected_rs1,
        input logic [4:0]      expected_rs2,
        input logic [4:0]      expected_rd,
        input logic [XLEN-1:0] expected_imm,
        input string           test_name
    );
        begin
            instr = test_instr;
            #1;

            if (opcode !== expected_opcode) begin
                $display("FAIL %-24s opcode=%b expected=%b", test_name, opcode, expected_opcode);
                errors++;
            end

            if (funct3 !== expected_funct3) begin
                $display("FAIL %-24s funct3=%b expected=%b", test_name, funct3, expected_funct3);
                errors++;
            end

            if (funct7 !== expected_funct7) begin
                $display("FAIL %-24s funct7=%b expected=%b", test_name, funct7, expected_funct7);
                errors++;
            end

            if (rs1 !== expected_rs1) begin
                $display("FAIL %-24s rs1=%0d expected=%0d", test_name, rs1, expected_rs1);
                errors++;
            end

            if (rs2 !== expected_rs2) begin
                $display("FAIL %-24s rs2=%0d expected=%0d", test_name, rs2, expected_rs2);
                errors++;
            end

            if (rd !== expected_rd) begin
                $display("FAIL %-24s rd=%0d expected=%0d", test_name, rd, expected_rd);
                errors++;
            end

            if (imm !== expected_imm) begin
                $display("FAIL %-24s imm=%h expected=%h", test_name, imm, expected_imm);
                errors++;
            end

            if (
                opcode === expected_opcode &&
                funct3 === expected_funct3 &&
                funct7 === expected_funct7 &&
                rs1 === expected_rs1 &&
                rs2 === expected_rs2 &&
                rd === expected_rd &&
                imm === expected_imm
            ) begin
                $display("PASS %-24s instr=%h", test_name, test_instr);
            end
        end
    endtask

    initial begin
        errors = 0;

        // R-type
        check_decode(
            enc_r(OP_ALU, F3_ADD, 7'b0000000, 5'd3, 5'd1, 5'd2),
            OP_ALU, F3_ADD, 7'b0000000, 5'd1, 5'd2, 5'd3, '0,
            "r add"
        );

        check_decode(
            enc_r(OP_ALU, F3_MUL, 7'b0000001, 5'd6, 5'd4, 5'd5),
            OP_ALU, F3_MUL, 7'b0000001, 5'd4, 5'd5, 5'd6, '0,
            "r mul"
        );

        // I-type
        check_decode(
            enc_i(OP_ALUI, F3_ADDI, 5'd7, 5'd8, 12'h00A),
            OP_ALUI, F3_ADDI, 7'b0000000, 5'd8, 5'd10, 5'd7, 32'h0000_000A,
            "addi positive"
        );

        check_decode(
            enc_i(OP_ALUI, F3_XORI, 5'd9, 5'd10, 12'hFFF),
            OP_ALUI, F3_XORI, 7'b1111111, 5'd10, 5'd31, 5'd9, 32'hFFFF_FFFF,
            "xori negative"
        );

        // Load
        check_decode(
            enc_i(OP_LOAD, F3_LW, 5'd11, 5'd12, 12'h010),
            OP_LOAD, F3_LW, 7'b0000000, 5'd12, 5'd16, 5'd11, 32'h0000_0010,
            "lw"
        );

        // S-type
        check_decode(
            enc_sbj(OP_STORE, F3_SW, 5'd13, 5'd14, 12'h014),
            OP_STORE, F3_SW, 7'b0000000, 5'd13, 5'd14, 5'd20, 32'h0000_0014,
            "sw positive"
        );

        check_decode(
            enc_sbj(OP_STORE, F3_SW, 5'd15, 5'd16, 12'hFFC),
            OP_STORE, F3_SW, 7'b1111111, 5'd15, 5'd16, 5'd28, 32'hFFFF_FFFC,
            "sw negative"
        );

        // B-type
        check_decode(
            enc_sbj(OP_BRANCH, F3_BEQ, 5'd1, 5'd2, 12'h008),
            OP_BRANCH, F3_BEQ, 7'b0000000, 5'd1, 5'd2, 5'd8, 32'h0000_0008,
            "beq positive"
        );

        check_decode(
            enc_sbj(OP_BRANCH, F3_BLT, 5'd3, 5'd4, 12'hFFC),
            OP_BRANCH, F3_BLT, 7'b1111111, 5'd3, 5'd4, 5'd28, 32'hFFFF_FFFC,
            "blt negative"
        );

        // J-type
        check_decode(
            enc_sbj(OP_JUMP, F3_J, 5'd0, 5'd0, 12'h00C),
            OP_JUMP, F3_J, 7'b0000000, 5'd0, 5'd0, 5'd12, 32'h0000_000C,
            "j"
        );

        check_decode(
            enc_sbj(OP_JUMP, F3_JAL, 5'd0, 5'd1, 12'h010),
            OP_JUMP, F3_JAL, 7'b0000000, 5'd0, 5'd1, 5'd16, 32'h0000_0010,
            "jal"
        );

        check_decode(
            enc_sbj(OP_JUMP, F3_JR, 5'd1, 5'd0, 12'h000),
            OP_JUMP, F3_JR, 7'b0000000, 5'd1, 5'd0, 5'd0, 32'h0000_0000,
            "jr"
        );

        // U-type
        check_decode(
            enc_u(OP_U, F3_LUHW, 5'd5, 16'h1234),
            OP_U, F3_LUHW, 7'b0001001, 5'b01000, 5'b00011, 5'd5, 32'h1234_0000,
            "luhw"
        );

        check_decode(
            enc_u(OP_U, F3_LLHW, 5'd5, 16'hBEEF),
            OP_U, F3_LLHW, 7'b1011111, 5'b11110, 5'b01110, 5'd5, 32'h0000_BEEF,
            "llhw"
        );

        if (errors == 0) begin
            $display("DECODER TEST PASSED");
        end else begin
            $display("DECODER TEST FAILED: %0d error(s)", errors);
        end

        $finish;
    end

endmodule