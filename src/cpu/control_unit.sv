import isa_defs::*;

module control_unit (

    input opcode_t opcode,
    input logic [2:0] funct3,
    input logic [6:0] funct7,
    input logic [3:0] flags,

    // control signals
    output logic [1:0] pc_src,
    output logic mem_read,
    output logic reg_write,
    output logic mem_write,
    output logic alu_src,
    output logic jal,
    output alu_op_t alu_op
);

    always_comb begin
        // default values
        pc_src    = 2'b0;
        reg_write = 0;
        mem_read  = 0;
        mem_write = 0;
        alu_src   = 0;
        jal       = 0;
        alu_op    = ALU_NONE;

        unique case (opcode)

            // R-type (ALU)
            OP_ALU: begin
                reg_write = 1;

                if (funct7 == 7'b0000000) begin
                    unique case (funct3)
                        3'b000: alu_op = ALU_ADD;
                        3'b001: alu_op = ALU_SUB;
                        3'b010: alu_op = ALU_AND;
                        3'b011: alu_op = ALU_OR;
                        3'b100: alu_op = ALU_XOR;
                        3'b101: alu_op = ALU_SLL;
                        3'b110: alu_op = ALU_SRL;
                        default: alu_op = ALU_NONE;
                    endcase
                end else if (funct7 == 7'b0000001) begin
                    unique case (funct3)
                        3'b000: alu_op = ALU_MUL;
                        3'b001: alu_op = ALU_DIV;
                        3'b010: alu_op = ALU_REM;
                        default: alu_op = ALU_NONE;
                    endcase
                end
            end

            // I-type (ALU immediate)
            OP_ALUI: begin
                reg_write = 1;
                alu_src   = 1;

                unique case (funct3)
                    3'b000: alu_op = ALU_ADD; 
                    3'b001: alu_op = ALU_XOR; 
                    3'b010: alu_op = ALU_SLL; 
                    3'b011: alu_op = ALU_SRL; 
                    default: alu_op = ALU_NONE;
                endcase
            end

            // LOAD
            OP_LOAD: begin
                reg_write = 1;
                mem_read  = 1;
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
                if (funct3 == 3'b000 && flags[3] ||
                    funct3 == 3'b001 && !flags[3] ||
                    funct3 == 3'b010 && !flags[2] ||
                    funct3 == 3'b011 && flags[2] ||
                    funct3 == 3'b100 && (!flags[2] || flags[3]) ||
                    funct3 == 3'b101 && (flags[2] || flags[3])) begin
                    pc_src = 2'b10; 
                end
            end

            // JUMP
            OP_JUMP: begin
                // jal writes return address
                if (funct3 == 3'b001) begin
                    reg_write = 1;
                    jal      = 1;
                    alu_op    = ALU_ADD;
                end
            end

            // U-type
            OP_U: begin
                reg_write = 1;
                alu_src = 1;
                alu_op = ALU_ADD;
            end

            // SEC 
            OP_SEC: begin
                // TODO
            end

        endcase
    end

endmodule