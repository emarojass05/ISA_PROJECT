// -------------------------------------------------------------
// Instruction Memory (ROM)
// Este módulo almacena las instrucciones del programa.
// Recibe una dirección (PC) y devuelve la instrucción correspondiente.
// El acceso es por palabra (PC / 4), ya que cada instrucción es de 32 bits.
// -------------------------------------------------------------

module instruction_memory (

    input  logic [31:0] pc,
    output logic [31:0] instruction

);

    // Memoria de 256 instrucciones (puede escalarse)
    logic [31:0] memory [0:255];

    // Inicialización manual (ejemplo)
    initial begin
        // Ejemplo de instrucciones 
        memory[0] = 32'h00000000; // NOP
        memory[1] = 32'h00000001; // dummy
        memory[2] = 32'h00000002;
        memory[3] = 32'h00000003;
    end

    // Acceso por palabra (PC / 4)
    assign instruction = memory[pc[9:2]];

endmodule