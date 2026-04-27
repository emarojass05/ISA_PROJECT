module instr_mem #(
    parameter int XLEN = 32,
    parameter int DEPTH = 65536,
    parameter string PROGRAM_FILE = "programs/hex/program.hex"
)(
    input  logic [XLEN-1:0] pc,
    output logic [31:0] instruction
);

    logic [31:0] memory [0:DEPTH-1];

    initial begin
        $readmemh(PROGRAM_FILE, memory);
    end

    assign instruction = memory[pc[$clog2(DEPTH)+1:2]];

endmodule