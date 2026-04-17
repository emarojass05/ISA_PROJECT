`timescale 1ns/1ps

// -------------------------------------------------------------
// Testbench del Program Counter
// Verifica que el PC:
// Se reinicie a 0 con reset
// 4 en 4 en cada ciclo de reloj
// -------------------------------------------------------------

module tb_pc;

    logic clk;
    logic reset;

    logic [31:0] pc;
    logic [31:0] next_pc;

    // Instancias
    program_counter pc_unit (
        .clk(clk),
        .reset(reset),
        .next_pc(next_pc),
        .pc(pc)
    );

    pc_adder adder (
        .pc(pc),
        .next_pc(next_pc)
    );

    // Clock
    always #5 clk = ~clk;

    initial begin
        clk = 0;
        reset = 1;

        // Dump para GTKWave
        $dumpfile("sim/pc.vcd");
        $dumpvars(0, tb_pc);

        // -------------------------
        // Reset activo
        // -------------------------
        #10;
        reset = 0;

        // -------------------------
        // Dejar correr el PC
        // -------------------------
        #50;

        $finish;
    end

    // Mostrar PC en cada ciclo
    always @(posedge clk) begin
        $display("Tiempo=%0t | PC = %0d", $time, pc);
    end

endmodule