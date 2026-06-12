import isa_defs::*;

module decoder #(
    parameter int XLEN = 32
)(
    input  logic [31:0] instr,

    output opcode_t opcode,

    output funct3_t funct3,
    output logic [6:0] funct7,
    output logic [4:0] rs1,
    output logic [4:0] rs2,
    output logic [4:0] rd,

    output logic [XLEN-1:0] imm
);

    // Field extraction
    always @(*) begin
        opcode  = opcode_t'(instr[6:0]);

        rd     = instr[11:7];
        funct3 = funct3_t'(instr[14:12]);
        rs1    = instr[19:15];
        rs2    = instr[24:20];
        funct7 = instr[31:25];
    end

    always @(*) begin
        imm = '0;

        case (opcode)
            OP_ALUI,
            OP_LOAD: begin
                imm = {{20{instr[31]}}, instr[31:20]};
            end

            OP_STORE,
            OP_BRANCH,
            OP_JUMP: begin
                imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            end

            OP_U: begin
                case (funct3)
                    F3_LUHW: imm = {instr[31:16], 16'b0};
                    F3_LLHW: imm = {16'b0, instr[31:16]};
                    default: imm = '0;
                endcase
            end

            default: begin
                imm = '0;
            end

        endcase
    end
endmodule