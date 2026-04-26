module pc #(
    parameter XLEN = 32
)(
    input  logic              clk,
    input  logic              rst,
    input  logic [XLEN-1:0]   next_pc,
    output logic [XLEN-1:0]   pc
);

    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            pc <= '0;
        else
            pc <= next_pc;
    end

endmodule