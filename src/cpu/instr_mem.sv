module instr_mem #(
    parameter int XLEN = 32,
    parameter int DEPTH = 65536,
    parameter PROGRAM_FILE = "programs/hex/program.hex"
)(
    input  logic [XLEN-1:0] pc,
    output logic [31:0] instruction
);

    logic [31:0] memory [0:DEPTH-1];

    integer i;

    initial begin
        string plus_prog_file;
        for (i = 0; i < DEPTH; i = i + 1) begin
            memory[i] = 32'h0000_0007;
        end

        // +PROGRAM_FILE= at vvp runtime takes precedence over the module parameter
        if ($value$plusargs("PROGRAM_FILE=%s", plus_prog_file)) begin
            $display("Loading instruction memory from: %s", plus_prog_file);
            $readmemh(plus_prog_file, memory);
        end else if (PROGRAM_FILE != "") begin
            $display("Loading instruction memory from: %s", PROGRAM_FILE);
            $readmemh(PROGRAM_FILE, memory);
        end
    end

    assign instruction = memory[pc[$clog2(DEPTH)+1:2]];

endmodule