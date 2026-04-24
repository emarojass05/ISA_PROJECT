`timescale 1ns/1ps

import isa_defs::*;

module tb_control_unit;

    opcode_t opcode;
    funct3_t funct3;
    logic [6:0] funct7;

    pc_src_t pc_src;
    wb_src_t wb_src;
    alu_op_t alu_op;

    logic reg_write;
    logic mem_write;
    logic alu_src;
    logic jal;
    logic u_load;
    logic branch;

    int errors;

    control_unit dut (
        .opcode(opcode),
        .funct3(funct3),
        .funct7(funct7),
        .pc_src(pc_src),
        .reg_write(reg_write),
        .mem_write(mem_write),
        .alu_src(alu_src),
        .jal(jal),
        .u_load(u_load),
        .branch(branch),
        .wb_src(wb_src),
        .alu_op(alu_op)
    );

    task automatic check_control(
        input opcode_t expected_opcode,
        input funct3_t expected_funct3,
        input logic [6:0] expected_funct7,

        input pc_src_t expected_pc_src,
        input logic expected_reg_write,
        input logic expected_mem_write,
        input logic expected_alu_src,
        input logic expected_jal,
        input logic expected_u_load,
        input logic expected_branch,
        input wb_src_t expected_wb_src,
        input alu_op_t expected_alu_op,

        input string test_name
    );
        begin
            opcode = expected_opcode;
            funct3 = expected_funct3;
            funct7 = expected_funct7;

            #1;

            if (pc_src !== expected_pc_src) begin
                $display("FAIL %-24s pc_src=%0d expected=%0d", test_name, pc_src, expected_pc_src);
                errors++;
            end

            if (reg_write !== expected_reg_write) begin
                $display("FAIL %-24s reg_write=%b expected=%b", test_name, reg_write, expected_reg_write);
                errors++;
            end

            if (mem_write !== expected_mem_write) begin
                $display("FAIL %-24s mem_write=%b expected=%b", test_name, mem_write, expected_mem_write);
                errors++;
            end

            if (alu_src !== expected_alu_src) begin
                $display("FAIL %-24s alu_src=%b expected=%b", test_name, alu_src, expected_alu_src);
                errors++;
            end

            if (jal !== expected_jal) begin
                $display("FAIL %-24s jal=%b expected=%b", test_name, jal, expected_jal);
                errors++;
            end

            if (u_load !== expected_u_load) begin
                $display("FAIL %-24s u_load=%b expected=%b", test_name, u_load, expected_u_load);
                errors++;
            end

            if (branch !== expected_branch) begin
                $display("FAIL %-24s branch=%b expected=%b", test_name, branch, expected_branch);
                errors++;
            end

            if (wb_src !== expected_wb_src) begin
                $display("FAIL %-24s wb_src=%0d expected=%0d", test_name, wb_src, expected_wb_src);
                errors++;
            end

            if (alu_op !== expected_alu_op) begin
                $display("FAIL %-24s alu_op=%0d expected=%0d", test_name, alu_op, expected_alu_op);
                errors++;
            end

            if (
                pc_src    === expected_pc_src &&
                reg_write === expected_reg_write &&
                mem_write === expected_mem_write &&
                alu_src   === expected_alu_src &&
                jal       === expected_jal &&
                u_load    === expected_u_load &&
                branch    === expected_branch &&
                wb_src    === expected_wb_src &&
                alu_op    === expected_alu_op
            ) begin
                $display("PASS %-24s", test_name);
            end
        end
    endtask

    initial begin
        errors = 0;

        // R-type
        check_control(
            OP_ALU, F3_ADD, 7'b0000000,
            PC_PLUS4, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, WB_ALU, ALU_ADD,
            "add"
        );

        check_control(
            OP_ALU, F3_SUB, 7'b0000000,
            PC_PLUS4, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, WB_ALU, ALU_SUB,
            "sub"
        );

        check_control(
            OP_ALU, F3_MUL, 7'b0000001,
            PC_PLUS4, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, WB_ALU, ALU_MUL,
            "mul"
        );

        check_control(
            OP_ALU, F3_DIV, 7'b0000001,
            PC_PLUS4, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, WB_ALU, ALU_DIV,
            "div"
        );

        check_control(
            OP_ALU, F3_REM, 7'b0000001,
            PC_PLUS4, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, WB_ALU, ALU_REM,
            "rem"
        );

        check_control(
            OP_ALU, F3_AND, 7'b0000000,
            PC_PLUS4, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, WB_ALU, ALU_AND,
            "and"
        );

        check_control(
            OP_ALU, F3_OR, 7'b0000000,
            PC_PLUS4, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, WB_ALU, ALU_OR,
            "or"
        );

        check_control(
            OP_ALU, F3_XOR, 7'b0000000,
            PC_PLUS4, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, WB_ALU, ALU_XOR,
            "xor"
        );

        check_control(
            OP_ALU, F3_SLL, 7'b0000000,
            PC_PLUS4, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, WB_ALU, ALU_SLL,
            "sll"
        );

        check_control(
            OP_ALU, F3_SRL, 7'b0000000,
            PC_PLUS4, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, WB_ALU, ALU_SRL,
            "srl"
        );

        // I-type ALU
        check_control(
            OP_ALUI, F3_ADDI, 7'b0000000,
            PC_PLUS4, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, WB_ALU, ALU_ADD,
            "addi"
        );

        check_control(
            OP_ALUI, F3_XORI, 7'b0000000,
            PC_PLUS4, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, WB_ALU, ALU_XOR,
            "xori"
        );

        check_control(
            OP_ALUI, F3_SLLI, 7'b0000000,
            PC_PLUS4, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, WB_ALU, ALU_SLL,
            "slli"
        );

        check_control(
            OP_ALUI, F3_SRLI, 7'b0000000,
            PC_PLUS4, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, WB_ALU, ALU_SRL,
            "srli"
        );

        // Memory
        check_control(
            OP_LOAD, F3_LW, 7'b0000000,
            PC_PLUS4, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, WB_MEM, ALU_ADD,
            "lw"
        );

        check_control(
            OP_STORE, F3_SW, 7'b0000000,
            PC_PLUS4, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, WB_ALU, ALU_ADD,
            "sw"
        );

        // Branches
        check_control(
            OP_BRANCH, F3_BEQ, 7'b0000000,
            PC_PLUS4, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, WB_ALU, ALU_SUB,
            "beq"
        );

        check_control(
            OP_BRANCH, F3_BNE, 7'b0000000,
            PC_PLUS4, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, WB_ALU, ALU_SUB,
            "bne"
        );

        check_control(
            OP_BRANCH, F3_BGT, 7'b0000000,
            PC_PLUS4, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, WB_ALU, ALU_SUB,
            "bgt"
        );

        check_control(
            OP_BRANCH, F3_BLT, 7'b0000000,
            PC_PLUS4, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, WB_ALU, ALU_SUB,
            "blt"
        );

        check_control(
            OP_BRANCH, F3_BGE, 7'b0000000,
            PC_PLUS4, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, WB_ALU, ALU_SUB,
            "bge"
        );

        check_control(
            OP_BRANCH, F3_BLE, 7'b0000000,
            PC_PLUS4, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, WB_ALU, ALU_SUB,
            "ble"
        );

        // Jumps
        check_control(
            OP_JUMP, F3_J, 7'b0000000,
            PC_IMM, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, WB_ALU, ALU_NONE,
            "j"
        );

        check_control(
            OP_JUMP, F3_JAL, 7'b0000000,
            PC_IMM, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, WB_PC4, ALU_NONE,
            "jal"
        );

        check_control(
            OP_JUMP, F3_JR, 7'b0000000,
            PC_JR, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, WB_ALU, ALU_NONE,
            "jr"
        );

        // U-type
        check_control(
            OP_U, F3_LUHW, 7'b0000000,
            PC_PLUS4, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, WB_ALU, ALU_LUHW,
            "luhw"
        );

        check_control(
            OP_U, F3_LLHW, 7'b0000000,
            PC_PLUS4, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, WB_ALU, ALU_LLHW,
            "llhw"
        );

        // Security placeholder
        check_control(
            OP_SEC, F3_ADD, 7'b0000000,
            PC_PLUS4, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, WB_ALU, ALU_NONE,
            "sec placeholder"
        );

        if (errors == 0) begin
            $display("CONTROL UNIT TEST PASSED");
        end else begin
            $display("CONTROL UNIT TEST FAILED: %0d error(s)", errors);
        end

        $finish;
    end

endmodule