import isa_defs::*;

module control_unit (

    input opcode_t opcode,
    input funct3_t funct3,
    input logic [6:0] funct7,
    input logic zero_fl, negative_fl, carry_fl, overflow_fl,

    // control signals
    output pc_src_t pc_src,
    output logic reg_write,
    output logic mem_write,
    output logic alu_src,
    output logic jal,
    output logic u_load,
    output wb_src_t wb_src,
    output alu_op_t alu_op
);

    always_comb begin
        // default values
        pc_src    = PC_PLUS4;
        reg_write = 0;
        wb_src    = WB_ALU;
        mem_write = 0;
        alu_src   = 0;
        jal       = 0;
        u_load    = 1'b0;
        alu_op    = ALU_NONE;

        unique case (opcode)

            // R-type (ALU)
            OP_ALU: begin
                reg_write = 1;

                if (funct7 == 7'b0000000) begin
                    unique case (funct3)
                        F3_ADD: alu_op = ALU_ADD;
                        F3_SUB: alu_op = ALU_SUB;
                        F3_AND: alu_op = ALU_AND;
                        F3_OR: alu_op = ALU_OR;
                        F3_XOR: alu_op = ALU_XOR;
                        F3_SLL: alu_op = ALU_SLL;
                        F3_SRL: alu_op = ALU_SRL;
                        default: alu_op = ALU_NONE;
                    endcase
                end else if (funct7 == 7'b0000001) begin
                    unique case (funct3)
                        F3_MUL: alu_op = ALU_MUL;
                        F3_DIV: alu_op = ALU_DIV;
                        F3_REM: alu_op = ALU_REM;
                        default: alu_op = ALU_NONE;
                    endcase
                end
            end

            // I-type 
            OP_ALUI: begin
                reg_write = 1;
                alu_src   = 1;

                unique case (funct3)
                    F3_ADDI: alu_op = ALU_ADD; 
                    F3_XORI: alu_op = ALU_XOR; 
                    F3_SLLI: alu_op = ALU_SLL; 
                    F3_SRLI: alu_op = ALU_SRL; 
                    default: alu_op = ALU_NONE;
                endcase
            end

            // LOAD
            OP_LOAD: begin
                reg_write = 1;
                wb_src    = WB_MEM;
                alu_src   = 1;
                alu_op    = ALU_ADD;
            end

            // STORE
            OP_STORE: begin
                mem_write = 1;
                alu_src   = 1;
                alu_op    = ALU_ADD;
            end

            // BRANCH
            OP_BRANCH: begin
                alu_op = ALU_SUB;

                unique case (funct3)
                    F3_BEQ: if (zero_fl) pc_src = PC_IMM;
                    F3_BNE: if (!zero_fl) pc_src = PC_IMM;
                    F3_BLT: if (negative_fl != overflow_fl) pc_src = PC_IMM;
                    F3_BGT: if (!zero_fl && (negative_fl == overflow_fl)) pc_src = PC_IMM;
                    F3_BGE: if (negative_fl == overflow_fl) pc_src = PC_IMM;
                    F3_BLE: if (zero_fl || (negative_fl != overflow_fl)) pc_src = PC_IMM;
                endcase
            end

            // JUMP
            OP_JUMP: begin
                // jal writes return address
                unique case (funct3)
                    F3_J: begin
                        pc_src = PC_IMM;
                    end
                    F3_JAL: begin
                        reg_write = 1;
                        jal       = 1;
                        pc_src    = PC_IMM;
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
                reg_write = 1;
                alu_src   = 1;
                wb_src    = WB_ALU;
                u_load    = 1'b1; 

                unique case (funct3)
                    F3_LUHW: alu_op = ALU_LUHW;
                    F3_LLHW: alu_op = ALU_LLHW;
                    default: alu_op = ALU_NONE;
                endcase
            end

            // SEC 
            OP_SEC: begin
                // TODO
            end

        endcase
    end

endmodule