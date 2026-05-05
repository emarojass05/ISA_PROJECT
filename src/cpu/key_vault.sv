module key_vault #(
    parameter int XLEN = 32,
    parameter int KEYS = 4,
    parameter int WORDS_PER_KEY = 4
)(
    // Input signals
    input  logic            clk,
    input  logic            vault_we,
    input  logic            auth_en,
    
    input  logic [3:0]      addr,
    input  logic [XLEN-1:0] wdata,
    
    // Output signals
    output logic [XLEN-1:0] k_out
);

    // Isolated RAM array
    logic [XLEN-1:0] vault [0:(KEYS*WORDS_PER_KEY)-1];

    integer i;
    initial begin
        for (i = 0; i < (KEYS*WORDS_PER_KEY); i = i + 1) begin
            vault[i] = '0;
        end
    end

    // Combinational read
    assign k_out = (auth_en) ? vault[addr] : '0;

    // Sequential write
    always_ff @(posedge clk) begin
        if (vault_we && auth_en) begin
            vault[addr] <= wdata;
        end
    end

endmodule