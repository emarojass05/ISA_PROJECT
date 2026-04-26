module data_mem #(
    parameter XLEN  = 32,
    parameter DEPTH = 65536
)(
    input  logic              clk,
    input  logic              mem_write_enable,
    input  logic [XLEN-1:0]   mem_write_data,
    input  logic [XLEN-1:0]   memory_address,

    output logic [XLEN-1:0]   mem_read_data
);

    // Memory array
    logic [XLEN-1:0] memory [0:DEPTH-1];

    integer i;

    initial begin
        for (i = 0; i < DEPTH; i = i + 1) begin
            memory[i] = '0;
        end
    end

    // Word-aligned address
    logic [$clog2(DEPTH)-1:0] addr;

    assign addr = memory_address[($clog2(DEPTH)+1):2];

    // Read (combinational)
    assign mem_read_data = memory[addr];

    // Write (sequential)
    always_ff @(posedge clk) begin
        if (mem_write_enable) begin
            memory[addr] <= mem_write_data;
        end
    end

endmodule