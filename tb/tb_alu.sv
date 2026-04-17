`timescale 1ns/1ps

module tb_alu;

    logic [31:0] A, B;
    logic [2:0] alu_op;
    logic [31:0] result;

    alu dut (
        .A(A),
        .B(B),
        .alu_op(alu_op),
        .result(result)
    );

    initial begin
        $dumpfile("sim/alu.vcd");
        $dumpvars(0, tb_alu);

        // -------------------------
        // ADD
        // -------------------------
        A = 10; B = 5; alu_op = 3'b000;
        #10;
        $display("ADD: %0d (esperado 15)", result);

        // -------------------------
        // SUB
        // -------------------------
        A = 10; B = 5; alu_op = 3'b001;
        #10;
        $display("SUB: %0d (esperado 5)", result);

        // -------------------------
        // AND
        // -------------------------
        A = 6; B = 3; alu_op = 3'b010;
        #10;
        $display("AND: %0d (esperado 2)", result);

        // -------------------------
        // OR
        // -------------------------
        A = 6; B = 3; alu_op = 3'b011;
        #10;
        $display("OR: %0d (esperado 7)", result);

        // -------------------------
        // XOR
        // -------------------------
        A = 6; B = 3; alu_op = 3'b100;
        #10;
        $display("XOR: %0d (esperado 5)", result);

        // -------------------------
        // SLL
        // -------------------------
        A = 1; B = 2; alu_op = 3'b101;
        #10;
        $display("SLL: %0d (esperado 4)", result);

        // -------------------------
        // SRL
        // -------------------------
        A = 8; B = 2; alu_op = 3'b110;
        #10;
        $display("SRL: %0d (esperado 2)", result);

        #20;
        $finish;
    end

endmodule