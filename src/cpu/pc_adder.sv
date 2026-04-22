module pc_adder (
    input logic [31:0] pc,
    input logic [31:0] imm,
    output logic [31:0] next_pc,
    output logic [31:0] pc_imm
);

    assign next_pc = pc + 32'd4;
    assign pc_imm = pc + imm;

endmodule