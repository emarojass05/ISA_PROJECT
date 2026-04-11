`timescale 1ns/1ps

// -------------------------------------------------------------
// Testbench Decoder
// Verifica que los campos se extraigan correctamente.
// -------------------------------------------------------------

module tb_decoder;

    logic [31:0] instruction;

    logic [5:0] opcode;
    logic [2:0] rd;
    logic [2:0] rs1;
    logic [2:0] rs2;
    logic [19:0] imm;

    decoder dut (
        .instruction(instruction),
        .opcode(opcode),
        .rd(rd),
        .rs1(rs1),
        .rs2(rs2),
        .imm(imm)
    );

    initial begin
        $dumpfile("sim/decoder.vcd");
        $dumpvars(0, tb_decoder);

        // -------------------------
        // Ejemplo tipo R
        // opcode=1, rd=2, rs1=3, rs2=4
        // -------------------------
        instruction = 32'b000001_010_011_100_00000000000000000;
        #10;

        $display("Tipo R:");
        $display("opcode=%0d rd=%0d rs1=%0d rs2=%0d",
                  opcode, rd, rs1, rs2);

        // -------------------------
        // Ejemplo tipo I
        // opcode=2, rd=1, rs1=2, imm=5
        // -------------------------
        instruction = 32'b000010_001_010_00000000000000101;
        #10;

        $display("Tipo I:");
        $display("opcode=%0d rd=%0d rs1=%0d imm=%0d",
                  opcode, rd, rs1, imm);

        #20;
        $finish;
    end

endmodule