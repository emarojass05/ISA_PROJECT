module instr_mem (
    input  [15:0] pc,        
    output [15:0] instruction
);
    reg [15:0] memory [0:65535];
    assign instruction = memory[pc];
endmodule