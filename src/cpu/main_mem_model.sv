// =============================================================================
// main_mem_model.sv — Modelo de Memoria Principal
// =============================================================================
// Capacidad  : 64 KB (16384 palabras de 32 bits)
// Latencia   : 25 ciclos desde req hasta ready
// Burst      : 256 bits (8 palabras × 32 bits = 1 línea de caché)
// Inicialización: parámetro INIT_FILE (opcional, formato $readmemh)
//
// Protocolo (desde cache_ctrl):
//   Lectura:
//     1. Cache_ctrl pulsa req=1, we=0, addr=dirección base de la línea
//     2. Este módulo cuenta 25 ciclos (LATENCY)
//     3. Al ciclo 25: ready=1 por UN ciclo, rdata=256 bits de la línea
//
//   Escritura (write-back de línea sucia):
//     1. Cache_ctrl pulsa req=1, we=1, addr=dirección base, wdata=256 bits
//     2. Este módulo cuenta 25 ciclos
//     3. Al ciclo 25: ready=1 por UN ciclo (confirma escritura)
//
//   Regla: cache_ctrl no puede enviar otro req mientras ready no llegue.
//          ready dura exactamente 1 ciclo.
// =============================================================================

module main_mem_model #(
    parameter int    XLEN      = 32,
    parameter int    DEPTH     = 16384,   // 64 KB / 4 bytes
    parameter int    LINE_WORDS = 8,
    parameter int    LINE_BITS  = LINE_WORDS * 32,  // 256
    parameter int    LATENCY   = 25,
    parameter string INIT_FILE = ""
)(
    input  logic                  clk,
    input  logic                  rst,

    // ── Interfaz con cache_ctrl ───────────────────────────────────────────
    input  logic                  req,     // pulso de 1 ciclo: nueva transacción
    input  logic                  we,      // 1 = escritura, 0 = lectura
    input  logic [XLEN-1:0]       addr,    // dirección base de la línea (byte-address)
    input  logic [LINE_BITS-1:0]  wdata,   // datos a escribir (solo cuando we=1)

    output logic                  ready,   // pulso de 1 ciclo: transacción completada
    output logic [LINE_BITS-1:0]  rdata    // línea leída (válida solo cuando ready=1 y we=0)
);

    // ── Memoria ───────────────────────────────────────────────────────────
    logic [31:0] memory [0:DEPTH-1];

    initial begin
        integer i;
        for (i = 0; i < DEPTH; i++)
            memory[i] = 32'h0;
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, memory);
    end

    // ── Registro de la transacción activa ────────────────────────────────
    logic                 active;       // hay una transacción en curso
    logic                 active_we;    // tipo: 0=read, 1=write
    logic [XLEN-1:0]      active_addr;  // dirección base registrada
    logic [LINE_BITS-1:0] active_wdata; // datos a escribir registrados
    logic [$clog2(LATENCY+1)-1:0] count; // contador de ciclos (0..LATENCY)

    // Índice de palabra base (byte_addr → word_addr, alineado a línea)
    logic [$clog2(DEPTH)-1:0] word_base;
    assign word_base = active_addr[$clog2(DEPTH)+1 : 2];  // /4, ignorar byte offset

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            active       <= 1'b0;
            active_we    <= 1'b0;
            active_addr  <= '0;
            active_wdata <= '0;
            count        <= '0;
            ready        <= 1'b0;
            rdata        <= '0;
        end else begin
            ready <= 1'b0;  // por defecto, ready=0

            if (!active) begin
                // Esperar nueva transacción
                if (req) begin
                    active       <= 1'b1;
                    active_we    <= we;
                    active_addr  <= addr;
                    active_wdata <= wdata;
                    count        <= 1;
                end
            end else begin
                if (count == LATENCY - 1) begin
                    // Transacción completada
                    ready  <= 1'b1;
                    active <= 1'b0;
                    count  <= '0;

                    if (active_we) begin
                        // Escritura: volcar los LINE_WORDS palabras a memoria
                        memory[word_base + 0] <= active_wdata[0*32  +: 32];
                        memory[word_base + 1] <= active_wdata[1*32  +: 32];
                        memory[word_base + 2] <= active_wdata[2*32  +: 32];
                        memory[word_base + 3] <= active_wdata[3*32  +: 32];
                        memory[word_base + 4] <= active_wdata[4*32  +: 32];
                        memory[word_base + 5] <= active_wdata[5*32  +: 32];
                        memory[word_base + 6] <= active_wdata[6*32  +: 32];
                        memory[word_base + 7] <= active_wdata[7*32  +: 32];
                        rdata <= '0;
                    end else begin
                        // Lectura: empaquetar LINE_WORDS palabras en rdata
                        rdata[0*32  +: 32] <= memory[word_base + 0];
                        rdata[1*32  +: 32] <= memory[word_base + 1];
                        rdata[2*32  +: 32] <= memory[word_base + 2];
                        rdata[3*32  +: 32] <= memory[word_base + 3];
                        rdata[4*32  +: 32] <= memory[word_base + 4];
                        rdata[5*32  +: 32] <= memory[word_base + 5];
                        rdata[6*32  +: 32] <= memory[word_base + 6];
                        rdata[7*32  +: 32] <= memory[word_base + 7];
                    end
                end else begin
                    count <= count + 1;
                end
            end
        end
    end

endmodule
