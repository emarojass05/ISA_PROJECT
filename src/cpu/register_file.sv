import isa_defs::*;

module register_file #(
    parameter int XLEN = 32
)(
    input  logic            clk,

    input  logic [4:0]      rs1,
    input  logic [4:0]      rs2,
    input  logic [4:0]      rs3,

    input  logic [XLEN-1:0] wd3,
    input  logic            we3,

    output logic [XLEN-1:0] rd1,
    output logic [XLEN-1:0] rd2
);

    logic [XLEN-1:0] registers [31:0];

    integer i;

    initial begin
        for (i = 0; i < 32; i = i + 1) begin
            registers[i] = '0;
        end
    end

    always_comb begin
        case (rs1)
            R_ZERO: begin
                rd1 = '0;
            end

            R_DELTA: begin
                rd1 = 32'h9E37_79B9;
            end

            default: begin
                if (we3 && (rs3 == rs1) && (rs3 != R_ZERO) && (rs3 != R_DELTA)) begin
                    rd1 = wd3;
                end else begin
                    rd1 = registers[rs1];
                end
            end
        endcase
    end

    always_comb begin
        case (rs2)
            R_ZERO: begin
                rd2 = '0;
            end

            R_DELTA: begin
                rd2 = 32'h9E37_79B9;
            end

            default: begin
                if (we3 && (rs3 == rs2) && (rs3 != R_ZERO) && (rs3 != R_DELTA)) begin
                    rd2 = wd3;
                end else begin
                    rd2 = registers[rs2];
                end
            end
        endcase
    end

    always_ff @(negedge clk) begin
        if (we3 && (rs3 != R_ZERO) && (rs3 != R_DELTA)) begin
            registers[rs3] <= wd3;
        end
    end

endmodule