module pc_adder #(
    parameter XLEN = 32 
)(
    input logic [XLEN-1:0] pc,
    input logic [XLEN-1:0] imm,
    output logic [XLEN-1:0] next_pc,
    output logic [XLEN-1:0] pc_imm
);

    assign next_pc = pc + 32'd4;
    assign pc_imm = pc + imm;

endmodule