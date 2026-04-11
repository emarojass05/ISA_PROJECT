// -------------------------------------------------------------
// Program Counter (PC)
// Este módulo guarda la dirección de la siguiente instrucción.
// En cada ciclo de reloj, actualiza el PC con next_pc.
// Si reset está activo, el PC se reinicia a 0.
// -------------------------------------------------------------

module program_counter (
    input  logic        clk,
    input  logic        reset,
    input  logic [31:0] next_pc,
    output logic [31:0] pc
);

    always_ff @(posedge clk or posedge reset) begin
        if (reset)
            pc <= 32'd0;
        else
            pc <= next_pc;
    end

endmodule