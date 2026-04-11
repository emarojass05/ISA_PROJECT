// -------------------------------------------------------------
// Decoder básico
// Este módulo recibe una instrucción de 32 bits y extrae:
// opcode, rd, rs1, rs2 e inmediato.
// No toma decisiones (eso lo hace el control unit).
// -------------------------------------------------------------

module decoder (

    input  logic [31:0] instruction,

    output logic [5:0]  opcode,
    output logic [2:0]  rd,
    output logic [2:0]  rs1,
    output logic [2:0]  rs2,
    output logic [19:0] imm

);

    // Extraer campos según tu ISA
    assign opcode = instruction[31:26];
    assign rd     = instruction[25:23];
    assign rs1    = instruction[22:20];
    assign rs2    = instruction[19:17];
    assign imm    = instruction[19:0]; // para tipo I

endmodule