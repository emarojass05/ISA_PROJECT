module control_unit(
    input [2:0] Op,
    input [1:0] funct2,
    input [3:0] funct4,

    output RegWrite,
    output MemWrite,
    output ResultSrc,
    output Branch,
    output [2:0] ALUOp
);




    assign RegWrite = (Op == 3'b000 || Op == 3'b001);

    assign MemWrite = (Op == 3'b010);

    assign ResultSrc = (Op == 3'b001);

    assign Branch = (Op == 3'b011);



    assign ALUOp =                        
                        (Op == 3'b001) ? 3'b000 :                     
                        (Op == 3'b010) ? 3'b000 :       
                        (Op == 3'b011) ? 3'b001 : 
                        (Op == 3'b100) ? 3'b000 : 
                        ((Op == 3'b000) && (funct4 == 4'b0000)) ? 3'b000 : 
                        ((Op == 3'b000) && (funct4 == 4'b0001)) ? 3'b001 :
                        ((Op == 3'b000) && (funct4 == 4'b0010)) ? 3'b010 :
                        ((Op == 3'b000) && (funct4 == 4'b0011)) ? 3'b011 :
                        ((Op == 3'b000) && (funct4 == 4'b0100)) ? 3'b100 :
                        ((Op == 3'b000) && (funct4 == 4'b0101)) ? 3'b101 :
                        ((Op == 3'b000) && (funct4 == 4'b0110)) ? 3'b110 :
                        ((Op == 3'b000) && (funct4 == 4'b0111)) ? 3'b000 :
                                                                      3'b000;

endmodule