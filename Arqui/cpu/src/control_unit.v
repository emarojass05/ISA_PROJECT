`include "cpu_defs.vh"

module control_unit(
    input [2:0] opcode,
    input [1:0] funct2,
    input [3:0] funct4,

    output registerWriteEnable,
    output memoryWriteEnable,
    output resultSrc,
    output branch,
    output [3:0] aluOp
);

    assign regWrite = (opcode == OPCODE_R || opcode == OPCODE_I);

    assign memWrite = (opcode == OPCODE_S);

    assign resultSrc = (opcode == OPCODE_S);

    assign branch = (opcode == OPCODE_B);

    assign aluOp =                        
                        (opcode == OPCODE_I) ? ALU_ADD :                     
                        (opcode == OPCODE_S) ? ALU_ADD :       
                        (opcode == OPCODE_B) ? ALU_SUB : 
                        (opcode == OPCODE_J) ? ALU_ADD : 
                        ((opcode == OPCODE_R) && (funct4 == 4'b0000)) ? ALU_ADD : 
                        ((opcode == OPCODE_R) && (funct4 == 4'b0001)) ? ALU_SUB :
                        ((opcode == OPCODE_R) && (funct4 == 4'b0010)) ? ALU_MUL :
                        ((opcode == OPCODE_R) && (funct4 == 4'b0011)) ? ALU_DIV :
                        ((opcode == OPCODE_R) && (funct4 == 4'b0100)) ? ALU_REM :
                        ((opcode == OPCODE_R) && (funct4 == 4'b0101)) ? ALU_AND :
                        ((opcode == OPCODE_R) && (funct4 == 4'b0110)) ? ALU_OR :
                        ((opcode == OPCODE_R) && (funct4 == 4'b0111)) ? ALU_XOR :
                        ((opcode == OPCODE_R) && (funct4 == 4'b1000)) ? ALU_SLL :
                        ((opcode == OPCODE_R) && (funct4 == 4'b1001)) ? ALU_SRL :
                                                                      4'b0000;

endmodule