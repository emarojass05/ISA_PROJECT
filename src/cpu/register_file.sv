module register_file #(
    parameter XLEN = 32
)(
    input  logic clk,

    // Read
    input  logic [4:0]  rs1,
    input  logic [4:0]  rs2,
    output logic [XLEN-1:0] rd1,
    output logic [XLEN-1:0] rd2,

    // Write
    input  logic [4:0]  rs3,
    input  logic [XLEN-1:0] wd3,
    input  logic we3
);

    // Registers
    logic [XLEN-1:0] registers [31:0];

    // Hardwired registers
    parameter logic [4:0] R_ZERO  = 5'b00000;
    parameter logic [4:0] R_DELTA = 5'b11110;

    // Reading
    assign rd1 = registers[rs1];
    assign rd2 = registers[rs2];

    // Writting
    always_ff @(negedge clk) begin
        registers[R_ZERO]  = 32'h0;
        registers[R_DELTA] = 32'h9E3779B9;
        if (we3 && (rs3 != R_ZERO && rs3 != R_DELTA)) begin
            registers[rs3] <= wd3;
        end
    end

endmodule