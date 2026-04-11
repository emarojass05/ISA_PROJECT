`timescale 1ns/1ps

// -------------------------------------------------------------
// Testbench Instruction Memory
// Verifica que el PC acceda correctamente a las instrucciones.
// -------------------------------------------------------------

module tb_instruction_memory;

    logic [31:0] pc;
    logic [31:0] instruction;

    instruction_memory dut (
        .pc(pc),
        .instruction(instruction)
    );

    initial begin
        $dumpfile("sim/instruction_memory.vcd");
        $dumpvars(0, tb_instruction_memory);

        // -------------------------
        // Probar diferentes direcciones
        // -------------------------

        pc = 0;
        #10;
        $display("PC=0 -> instr=%h", instruction);

        pc = 4;
        #10;
        $display("PC=4 -> instr=%h", instruction);

        pc = 8;
        #10;
        $display("PC=8 -> instr=%h", instruction);

        pc = 12;
        #10;
        $display("PC=12 -> instr=%h", instruction);

        #20;
        $finish;
    end

endmodule