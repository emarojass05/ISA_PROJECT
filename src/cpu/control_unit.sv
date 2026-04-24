import isa_defs::*;

module control_unit (
    input  opcode_t    opcode,
    input  funct3_t    funct3,
    input  logic [6:0] funct7,

    output pc_src_t    pc_src,
    output logic       reg_write,
    output logic       mem_write,
    output logic       alu_src,
    output logic       jal,
    output logic       u_load,
    output logic       branch,
    output wb_src_t    wb_src,
    output alu_op_t    alu_op
);

    always @(*) begin
        pc_src    = PC_PLUS4;
        reg_write = 1'b0;
        mem_write = 1'b0;
        alu_src   = 1'b0;
        jal       = 1'b0;
        u_load    = 1'b0;
        branch    = 1'b0;
        wb_src    = WB_ALU;
        alu_op    = ALU_NONE;

        case (opcode)

            // R-type
            OP_ALU: begin
                reg_write = 1'b1;
                wb_src    = WB_ALU;

                case (funct7)
                    7'b0000000: begin
                        case (funct3)
                            F3_ADD: alu_op = ALU_ADD;
                            F3_SUB: alu_op = ALU_SUB;
                            F3_AND: alu_op = ALU_AND;
                            F3_OR:  alu_op = ALU_OR;
                            F3_XOR: alu_op = ALU_XOR;
                            F3_SLL: alu_op = ALU_SLL;
                            F3_SRL: alu_op = ALU_SRL;
                            default: alu_op = ALU_NONE;
                        endcase
                    end

                    7'b0000001: begin
                        case (funct3)
                            F3_MUL: alu_op = ALU_MUL;
                            F3_DIV: alu_op = ALU_DIV;
                            F3_REM: alu_op = ALU_REM;
                            default: alu_op = ALU_NONE;
                        endcase
                    end

                    default: begin
                        alu_op = ALU_NONE;
                    end
                endcase
            end

            // I-type ALU
            OP_ALUI: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                wb_src    = WB_ALU;

                case (funct3)
                    F3_ADDI: alu_op = ALU_ADD;
                    F3_XORI: alu_op = ALU_XOR;
                    F3_SLLI: alu_op = ALU_SLL;
                    F3_SRLI: alu_op = ALU_SRL;
                    default: alu_op = ALU_NONE;
                endcase
            end

            // Load
            OP_LOAD: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                wb_src    = WB_MEM;
                alu_op    = ALU_ADD;
            end

            // Store
            OP_STORE: begin
                mem_write = 1'b1;
                alu_src   = 1'b1;
                alu_op    = ALU_ADD;
            end

            // Branch
            OP_BRANCH: begin
                branch = 1'b1;
                alu_op = ALU_SUB;
            end

            // Jump
            OP_JUMP: begin
                case (funct3)
                    F3_J: begin
                        pc_src = PC_IMM;
                    end

                    F3_JAL: begin
                        pc_src    = PC_IMM;
                        reg_write = 1'b1;
                        jal       = 1'b1;
                        wb_src    = WB_PC4;
                    end

                    F3_JR: begin
                        pc_src = PC_JR;
                    end

                    default: begin
                        pc_src = PC_PLUS4;
                    end
                endcase
            end

            // U-type
            OP_U: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                u_load    = 1'b1;
                wb_src    = WB_ALU;

                case (funct3)
                    F3_LUHW: alu_op = ALU_LUHW;
                    F3_LLHW: alu_op = ALU_LLHW;
                    default: alu_op = ALU_NONE;
                endcase
            end

            // Security placeholder
            OP_SEC: begin
                alu_op = ALU_NONE;
            end

            default: begin
                pc_src    = PC_PLUS4;
                reg_write = 1'b0;
                mem_write = 1'b0;
                alu_src   = 1'b0;
                jal       = 1'b0;
                u_load    = 1'b0;
                branch    = 1'b0;
                wb_src    = WB_ALU;
                alu_op    = ALU_NONE;
            end

        endcase
    end

endmodule