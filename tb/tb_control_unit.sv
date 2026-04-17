`timescale 1ns/1ps

module tb_control_unit;

    reg [2:0] Op;
    reg [1:0] funct2;
    reg [3:0] funct4;

    wire RegWrite;
    wire MemWrite;
    wire ResultSrc;
    wire Branch;
    wire [2:0] ALUOp;

    // Instancia del DUT
    control_unit dut(
        .Op(Op),
        .funct2(funct2),
        .funct4(funct4),
        .RegWrite(RegWrite),
        .MemWrite(MemWrite),
        .ResultSrc(ResultSrc),
        .Branch(Branch),
        .ALUOp(ALUOp)
    );

    initial begin
        $display("Op funct4 | RegW MemW ResSrc Branch ALUOp");

        // Caso 1: Tipo R (ADD)
        Op = 3'b000; funct4 = 4'b0000; funct2 = 2'b00;
        #10;
        $display("%b %b | %b %b %b %b %b",
                  Op, funct4,
                  RegWrite, MemWrite, ResultSrc, Branch, ALUOp);

        // Caso 2: Tipo R (SUB)
        Op = 3'b000; funct4 = 4'b0001; funct2 = 2'b00;
        #10;
        $display("%b %b | %b %b %b %b %b",
                  Op, funct4,
                  RegWrite, MemWrite, ResultSrc, Branch, ALUOp);

        // Caso 3: LOAD
        Op = 3'b001; funct4 = 4'b0000; funct2 = 2'b00;
        #10;
        $display("%b %b | %b %b %b %b %b",
                  Op, funct4,
                  RegWrite, MemWrite, ResultSrc, Branch, ALUOp);

        // Caso 4: STORE
        Op = 3'b010; funct4 = 4'b0000; funct2 = 2'b00;
        #10;
        $display("%b %b | %b %b %b %b %b",
                  Op, funct4,
                  RegWrite, MemWrite, ResultSrc, Branch, ALUOp);

        // Caso 5: BRANCH
        Op = 3'b011; funct4 = 4'b0000; funct2 = 2'b00;
        #10;
        $display("%b %b | %b %b %b %b %b",
                  Op, funct4,
                  RegWrite, MemWrite, ResultSrc, Branch, ALUOp);

        // Caso 6: Otra operación R (ej: funct4 = 0100)
        Op = 3'b000; funct4 = 4'b0100; funct2 = 2'b00;
        #10;
        $display("%b %b | %b %b %b %b %b",
                  Op, funct4,
                  RegWrite, MemWrite, ResultSrc, Branch, ALUOp);

        $finish;
    end

endmodule