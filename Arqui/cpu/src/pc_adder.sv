// -------------------------------------------------------------
// PC Adder
// Este módulo calcula la siguiente dirección de instrucción.
// En una ejecución normal, simplemente suma 4 al PC actual,
// ya que cada instrucción es de 32 bits.
// -------------------------------------------------------------

module pc_adder (
    input  logic [31:0] pc,
    output logic [31:0] next_pc
);

    assign next_pc = pc + 32'd4;

endmodule