module register_file (
    input  logic        clk,

    // Lectura
    input  logic [2:0]  rs1,
    input  logic [2:0]  rs2,
    output logic [31:0] read_data1,
    output logic [31:0] read_data2,

    // Escritura
    input  logic [2:0]  rd,
    input  logic [31:0] write_data,
    input  logic        reg_write
);

    // 8 registros de 32 bits
    logic [31:0] registers [15:0];

    // -------------------------
    // Lectura 
    // -------------------------
    assign read_data1 = (rs1 == 3'd0) ? 32'd0 : registers[rs1];
    assign read_data2 = (rs2 == 3'd0) ? 32'd0 : registers[rs2];

    // -------------------------
    // Escritura 
    // -------------------------
    always_ff @(posedge clk) begin
        if (reg_write && rd != 3'd0) begin
            registers[rd] <= write_data;
        end
    end

endmodule