module decoder (

    input  logic [15:0] instruction,
    output logic [2:0] opcode,
    output logic [3:0] funct4,
    output logic [1:0] funct2,
    output logic [3:0] registerAddress1,
    output logic [3:0] registerAddress2,
    output logic [3:0] registerAddress3,
    output logic [10:0] immediate,
    output logic mem,
    output logic eq
);

    assign opcode = instruction[2:0];
    case (opcode)
            OPCODE_R: begin
                assign registerAddress1 = instruction[10:7];
                assign registerAddress2 = instruction[14:11];
                assign funct4 = instruction[6:3];
            end
                           
            OPCODE_I: begin
                assign immediate = instruction[15:8];
                assign registerAddress3 = instruction[7:4];
                assign mem = instruction[3];
            end 
            OPCODE_S: begin
                assign immediate = instruction[15:7];
                assign registerAddress1 = instruction[6:3];
            end    
            OPCODE_B: begin 
                assign registerAddress1 = instruction[9:6];  
                assign registerAddress2 = instruction[13:10];
                assign funct2 = instruction[4:3];
                assign eq = instruction[5]
            end  
            OPCODE_J: begin 
                assign immediate = instruction[15:5];
                assign funct2 = instruction[4:3];    
            default: result = 32'd0;
            end
    endcase
    

endmodule