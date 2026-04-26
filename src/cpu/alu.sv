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

    logic [XLEN:0] sum_ext;
    logic signed [XLEN-1:0] signed_a;
    logic signed [XLEN-1:0] signed_b;

    assign signed_a = a;
    assign signed_b = b;

    always @(*) begin
        result      = '0;
        sum_ext     = '0;
        carry_fl    = 0;
        overflow_fl = 0;

        case (alu_op)

            ALU_ADD: begin
                sum_ext   = {1'b0, a} + {1'b0, b};
                result    = sum_ext[XLEN-1:0];
                carry_fl  = sum_ext[XLEN];

                overflow_fl = (!a[XLEN-1] && !b[XLEN-1] && result[XLEN-1]) ||
                            ( a[XLEN-1] &&  b[XLEN-1] && !result[XLEN-1]);
            end

            ALU_SUB: begin
                sum_ext   = {1'b0, a} + {1'b0, ~b} + 1'b1;
                result    = sum_ext[XLEN-1:0];
                carry_fl  = sum_ext[XLEN];

                overflow_fl = (!a[XLEN-1] &&  b[XLEN-1] && result[XLEN-1]) ||
                            ( a[XLEN-1] && !b[XLEN-1] && !result[XLEN-1]);
            end

            ALU_AND: result = a & b;
            ALU_OR : result = a | b;
            ALU_XOR: result = a ^ b;

            ALU_SLL: result = a << b[$clog2(XLEN)-1:0];
            ALU_SRL: result = a >> b[$clog2(XLEN)-1:0];

            ALU_LUHW: result = {b[31:16], a[15:0]};
            ALU_LLHW: result = {a[31:16], b[15:0]};

            ALU_MUL: begin
                result = signed_a * signed_b;
            end

            ALU_DIV: begin
                if (b == '0) begin
                    result = '0;
                end else begin
                    result = signed_a / signed_b;
                end
            end

            ALU_REM: begin
                if (b == '0) begin
                    result = '0;
                end else begin
                    result = signed_a % signed_b;
                end
            end
            default: result = '0;

        endcase
    end

    // Static flags
    assign zero_fl = (result == 0);
    assign negative_fl = result[XLEN-1];

endmodule