module data_mem #(
    parameter int XLEN = 32,
    parameter int DEPTH = 65536,
    parameter INITIAL_MEM = ""
)(
    input  logic              clk,
    input  logic              mem_write_enable,
    input  logic [XLEN-1:0]   mem_write_data,
    input  logic [XLEN-1:0]   memory_address,

    output logic [XLEN-1:0]   mem_read_data
);

    logic [XLEN-1:0] memory [0:DEPTH-1];

    logic [$clog2(DEPTH)-1:0] addr;

    integer i;

    initial begin
        for (i = 0; i < DEPTH; i = i + 1) begin
            memory[i] = '0;
        end

        if (INITIAL_MEM != "") begin
            $display("Loading data memory from: %s", INITIAL_MEM);
            $readmemh(INITIAL_MEM, memory);
        end
    end

    assign addr = memory_address[$clog2(DEPTH)+1:2];

    assign mem_read_data = memory[addr];

    always_ff @(posedge clk) begin
        if (mem_write_enable) begin
            memory[addr] <= mem_write_data;
        end
    end

endmodule