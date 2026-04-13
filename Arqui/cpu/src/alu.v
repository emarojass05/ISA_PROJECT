`include "cpu_defs.vh"

module alu (
    input  logic [31:0] srcA,
    input  logic [31:0] srcB,
    input  logic [4:0]  aluOp,
    output logic [31:0] result
);

    always @(*) begin
        case (aluOp)
            ALU_ADD: result = srcA + srcB;
            ALU_SUB: result = srcA - srcB;
            ALU_MUL: result = srcA * srcB;
            ALU_DIV: result = srcA / srcB;
            ALU_REM: result = srcA % srcB;
            ALU_AND: result = srcA & srcB;
            ALU_OR: result = srcA | srcB;
            ALU_XOR: result = srcA ^ srcB;
            ALU_SLL: result = srcA << srcB[4:0];
            ALU_SRL: result = srcA >> srcB[4:0];
            default: result = 32'd0;
        endcase
    end

endmodule