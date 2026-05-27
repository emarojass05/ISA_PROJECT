// =============================================================================
// main_mem_model.sv
// Modelo realista de memoria principal
//   - 64 KB (16384 palabras de 32 bits)
//   - Latencia: LATENCY ciclos de CPU (25 por defecto)
//   - Interfaz burst: lee/escribe una línea completa (8 palabras = 256 bits)
//   - Protocolo: req se pulsa 1 ciclo; ready se pulsa 1 ciclo cuando termina
// =============================================================================

module main_mem_model #(
    parameter int XLEN       = 32,
    parameter int DEPTH      = 16384,   // 64 KB / 4 B = 16384 palabras
    parameter int LATENCY    = 25,      // Ciclos de CPU por acceso
    parameter int LINE_WORDS = 8        // Palabras por línea de caché
)(
    input  logic        clk,
    input  logic        rst,

    // ── Solicitud ──────────────────────────────────────────────────────────
    input  logic        req,            // Pulso de 1 ciclo para iniciar
    input  logic        we,             // 1 = escritura (writeback), 0 = lectura
    input  logic [31:0] addr,           // Dirección byte alineada a línea (addr[4:0]=0)
    input  logic [255:0] wdata,         // Datos a escribir (8×32 bits empaquetados)

    // ── Respuesta ──────────────────────────────────────────────────────────
    output logic [255:0] rdata,         // Línea leída (válida cuando ready=1)
    output logic         ready          // Pulso de 1 ciclo indicando fin de operación
);
    // Parámetro auxiliar para el contador
    localparam int CNT_W = $clog2(LATENCY + 1) + 1;

    // ── Memoria interna ────────────────────────────────────────────────────
    logic [31:0] mem [0:DEPTH-1];

    integer init_i;
    initial begin
        for (init_i = 0; init_i < DEPTH; init_i = init_i + 1)
            mem[init_i] = 32'h0;
    end

    // ── Registros de estado ────────────────────────────────────────────────
    logic [CNT_W-1:0] cnt;
    logic             busy;
    logic             we_r;
    logic [13:0]      base_r;           // Índice de palabra base (addr >> 2)
    logic [255:0]     wdata_r;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            cnt   <= '0;
            busy  <= 1'b0;
            ready <= 1'b0;
            rdata <= '0;
            we_r  <= 1'b0;
            base_r <= '0;
            wdata_r <= '0;
        end else begin
            ready <= 1'b0;             // Pulso de 1 ciclo por defecto

            if (!busy) begin
                if (req) begin
                    busy   <= 1'b1;
                    cnt    <= CNT_W'(LATENCY - 1);
                    we_r   <= we;
                    base_r <= addr[15:2];   // Dirección byte → índice de palabra
                    if (we)
                        wdata_r <= wdata;
                end
            end else begin             // busy == 1
                if (cnt == '0) begin
                    busy  <= 1'b0;
                    ready <= 1'b1;
                    if (we_r) begin
                        // Escritura: almacena las 8 palabras de la línea
                        for (int j = 0; j < LINE_WORDS; j++)
                            mem[base_r + 14'(j)] <= wdata_r[j*32 +: 32];
                    end else begin
                        // Lectura: devuelve las 8 palabras de la línea
                        for (int j = 0; j < LINE_WORDS; j++)
                            rdata[j*32 +: 32] <= mem[base_r + 14'(j)];
                    end
                end else begin
                    cnt <= cnt - 1;
                end
            end
        end
    end

endmodule
