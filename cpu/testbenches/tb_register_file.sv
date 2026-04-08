`timescale 1ns/1ps

module tb_register_file;

    logic clk;
    logic [2:0] rs1, rs2, rd;
    logic [31:0] write_data;
    logic reg_write;
    logic [31:0] read_data1, read_data2;

    // Instancia del DUT (Device Under Test)
    register_file dut (
        .clk(clk),
        .rs1(rs1),
        .rs2(rs2),
        .rd(rd),
        .write_data(write_data),
        .reg_write(reg_write),
        .read_data1(read_data1),
        .read_data2(read_data2)
    );

    // Clock
    always #5 clk = ~clk;

    initial begin
        // Inicialización
        clk = 0;
        reg_write = 0;

        // Dump de señales (para GTKWave)
        $dumpfile("sim/register_file.vcd");
        $dumpvars(0, tb_register_file);

        // -------------------------
        // TEST 1: escribir en R1
        // -------------------------
        #10;
        rd = 3'd1;
        write_data = 32'd5;
        reg_write = 1;

        #10;
        reg_write = 0;

        // Leer R1
        rs1 = 3'd1;
        rs2 = 3'd0;

        #10;
        $display("R1 = %0d (esperado 5)", read_data1);

        // -------------------------
        // TEST 2: R0 siempre 0
        // -------------------------
        rs1 = 3'd0;

        #10;
        $display("R0 = %0d (esperado 0)", read_data1);

        // -------------------------
        // TEST 3: escribir en R2
        // -------------------------
        rd = 3'd2;
        write_data = 32'd10;
        reg_write = 1;

        #10;
        reg_write = 0;

        rs1 = 3'd2;

        #10;
        $display("R2 = %0d (esperado 10)", read_data1);

        // -------------------------
        // FIN
        // -------------------------
        #20;
        $finish;
    end

endmodule