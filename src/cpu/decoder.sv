import isa_defs::*;

module decoder (
    input  logic [31:0] instr,

    // typed opcode
    output opcode_t opcode,

    // raw fields
    output funct3_t funct3,
    output logic [6:0] funct7,
    output logic [4:0] rs1,
    output logic [4:0] rs2,
    output logic [4:0] rd,

    output logic [31:0] imm
);

    logic [4:0] rs1_raw;

    // Field extraction
    always_comb begin
        opcode  = opcode_t'(instr[6:0]);

        rd      = instr[11:7];
        funct3  = funct3_t'(instr[14:12]);
        rs1_raw = instr[19:15];
        rs2     = instr[24:20];
        funct7  = instr[31:25];
    end

    // Inmediate extension
    always_comb begin
        imm = 32'b0;

        unique case (opcode)
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
                imm = {16'b0, instr[31:16]};
            end

            default: begin
                imm = 32'b0;
            end

        endcase
    end

    assign rs1 = (opcode == OP_U) ? 5'b00000 : rs1_raw;
endmodule