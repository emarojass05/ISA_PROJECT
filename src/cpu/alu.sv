import isa_defs::*;

module alu #(
    parameter XLEN = 32
)(
    input  logic [XLEN-1:0] a,
    input  logic [XLEN-1:0] b,
    input  alu_op_t alu_op,

    output logic [XLEN-1:0] result,

    // flags (Z,N,C,V)
    output logic zero_fl, negative_fl, carry_fl, overflow_fl 
);

    logic [XLEN:0] sum_ext; // extra bit for carry

    always_comb begin
        result      = '0;
        sum_ext     = '0;
        carry_fl    = 0;
        overflow_fl = 0;

        unique case (alu_op)

            // ADD
            ALU_ADD: begin
                sum_ext   = {1'b0, a} + {1'b0, b};
                result   = sum_ext[XLEN-1:0];
                carry_fl = sum_ext[XLEN];

                // overflow: signs equal but result different
                overflow_fl = (!a[XLEN-1] && !b[XLEN-1] && result[XLEN-1]) ||
                (a[XLEN-1] && b[XLEN-1] && !result[XLEN-1]);
            end

            // SUB
            ALU_SUB: begin
                sum_ext   = {1'b0, a} + {1'b0, ~b} + 1'b1;
                result   = sum_ext[XLEN-1:0];
                carry_fl = sum_ext[XLEN]; // borrow inverted

                // overflow: signs differ and result sign wrong
                overflow_fl = (!a[XLEN-1] &&  b[XLEN-1] && result[XLEN-1]) ||
                (a[XLEN-1] && !b[XLEN-1] && !result[XLEN-1]);
            end

            // LOGIC
            ALU_AND: result = a & b;
            ALU_OR : result = a | b;
            ALU_XOR: result = a ^ b;

            // SHIFTS
            ALU_SLL: result = a << b[$clog2(XLEN)-1:0];
            ALU_SRL: result = a >> b[$clog2(XLEN)-1:0];

            // MUL/DIV
            ALU_MUL: result = a * b;

            ALU_DIV: result = (b != 0) ? (a / b) : '0;
            ALU_REM: result = (b != 0) ? (a % b) : '0;

            default: result = '0;

        endcase
    end

    // Static flags
    assign zero_fl = (result == 0);
    assign negative_fl = result[XLEN-1];

endmodule