module instr_mem #(
    parameter XLEN = 32,
    parameter DEPTH = 65536
)(
    input  logic [XLEN-1:0] pc,
    output logic [31:0] instruction
);

    // Memory array
    logic [XLEN-1:0] memory [0:DEPTH-1];

    // Word-aligned access
    assign instruction = memory[pc[($clog2(DEPTH)+1):2]];

endmodule