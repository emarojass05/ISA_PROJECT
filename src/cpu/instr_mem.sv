module instr_mem (
    input  [31:0] pc,        
    output [31:0] instruction
);
    reg [31:0] memory [0:65535];
    assign instruction = memory[pc];
endmodule