// =============================================================================
// cache_ctrl.sv  —  Controlador de Jerarquía de Caché
//
//  Conecta el pipeline (etapa MEM) con L1, L2 y memoria principal.
//  Genera la señal cache_stall que congela el pipeline en caso de fallo.
//
//  Comportamiento:
//    L1 hit           → 0 ciclos extra (cache_stall = 0)
//    L1 miss + L2 hit → ~8 ciclos de stall
//    L1 miss + L2 miss→ ~33 ciclos de stall (25 mem + overhead)
//
//  FSM de estados:
//    IDLE       : sin operación activa
//    L1_WB      : writeback de línea sucia de L1 hacia L2  (1 ciclo)
//    L2_CHECK   : consultar L2 tras fallo de L1            (1 ciclo)
//    L2_FILL    : llenar L1 desde L2                       (8 ciclos)
//    L2_WB      : writeback de línea sucia de L2 a memoria (25 ciclos)
//    MEM_FETCH  : traer línea de memoria principal         (25 ciclos)
//    L2_UPDATE  : instalar línea en L2                     (1 ciclo)
//    L1_UPDATE  : instalar línea en L1                     (1 ciclo)
//
//  Señales de contadores de rendimiento (pulsos de 1 ciclo):
//    ev_l1_hit, ev_l1_miss, ev_l2_hit, ev_l2_miss, ev_mem_access
// =============================================================================

module cache_ctrl #(
    parameter int XLEN        = 32,
    parameter int L2_FILL_CYC = 8,    // Ciclos de stall para hit en L2
    parameter int MEM_LATENCY = 25    // Latencia de memoria principal
)(
    input  logic clk,
    input  logic rst,

    // ── Interfaz con el pipeline (etapa MEM) ──────────────────────────────
    input  logic        mem_req,       // Hay una operación de memoria válida
    input  logic        mem_we,        // 1 = STORE, 0 = LOAD
    input  logic [31:0] mem_addr,      // Dirección (de ex_mem_reg.alu_result)
    input  logic [31:0] mem_wdata,     // Dato a escribir (sólo STORE)

    output logic [31:0] mem_rdata,     // Dato leído (sólo LOAD, válido cuando stall=0)
    output logic        cache_stall,   // 1 = pipeline congelado

    // ── Eventos para contadores de rendimiento ────────────────────────────
    output logic ev_l1_hit,
    output logic ev_l1_miss,
    output logic ev_l2_hit,
    output logic ev_l2_miss,
    output logic ev_mem_access
);

    // =========================================================================
    // Instancia L1
    // =========================================================================
    // Señales hacia/desde L1
    logic        l1_hit;
    logic        l1_hit_way;
    logic [31:0] l1_hit_rdata;
    logic        l1_victim_dirty;
    logic [31:0] l1_victim_addr;
    logic [255:0] l1_victim_data;

    logic        l1_do_write_hit;
    logic [31:0] l1_wh_addr;
    logic [31:0] l1_wh_data;
    logic        l1_wh_way;

    logic        l1_do_lru_update;
    logic [31:0] l1_lu_addr;
    logic        l1_lu_way;

    logic        l1_do_fill;
    logic [31:0] l1_fill_addr;
    logic [255:0] l1_fill_data;
    logic        l1_fill_word_we;
    logic [2:0]  l1_fill_word_off;
    logic [31:0] l1_fill_word_data;

    cache_l1d u_l1 (
        .clk            (clk),
        .rst            (rst),
        .req_addr       (mem_addr),
        .hit            (l1_hit),
        .hit_way        (l1_hit_way),
        .hit_rdata      (l1_hit_rdata),
        .victim_dirty   (l1_victim_dirty),
        .victim_addr    (l1_victim_addr),
        .victim_data    (l1_victim_data),
        .do_write_hit   (l1_do_write_hit),
        .wh_addr        (l1_wh_addr),
        .wh_data        (l1_wh_data),
        .wh_way         (l1_wh_way),
        .do_lru_update  (l1_do_lru_update),
        .lu_addr        (l1_lu_addr),
        .lu_way         (l1_lu_way),
        .do_fill        (l1_do_fill),
        .fill_addr      (l1_fill_addr),
        .fill_data      (l1_fill_data),
        .fill_word_we   (l1_fill_word_we),
        .fill_word_off  (l1_fill_word_off),
        .fill_word_data (l1_fill_word_data)
    );

    // =========================================================================
    // Instancia L2
    // =========================================================================
    logic        l2_hit;
    logic [1:0]  l2_hit_way;
    logic [255:0] l2_hit_line;
    logic        l2_victim_dirty;
    logic [31:0] l2_victim_addr;
    logic [255:0] l2_victim_data;

    logic        l2_do_write_line;
    logic [31:0] l2_wl_addr;
    logic [255:0] l2_wl_data;

    logic        l2_do_fill;
    logic [31:0] l2_fill_addr;
    logic [255:0] l2_fill_data;

    // El req_addr de L2 se actualiza durante la FSM para apuntar a la dirección activa
    logic [31:0] l2_req_addr;

    cache_l2 u_l2 (
        .clk             (clk),
        .rst             (rst),
        .req_addr        (l2_req_addr),
        .hit             (l2_hit),
        .hit_way         (l2_hit_way),
        .hit_rdata_line  (l2_hit_line),
        .victim_dirty    (l2_victim_dirty),
        .victim_addr     (l2_victim_addr),
        .victim_data     (l2_victim_data),
        .do_write_line   (l2_do_write_line),
        .wl_addr         (l2_wl_addr),
        .wl_data         (l2_wl_data),
        .do_fill         (l2_do_fill),
        .fill_addr       (l2_fill_addr),
        .fill_data       (l2_fill_data)
    );

    // =========================================================================
    // Instancia memoria principal
    // =========================================================================
    logic        mm_req;
    logic        mm_we;
    logic [31:0] mm_addr;
    logic [255:0] mm_wdata;
    logic [255:0] mm_rdata;
    logic        mm_ready;

    main_mem_model #(
        .LATENCY   (MEM_LATENCY)
    ) u_mem (
        .clk   (clk),
        .rst   (rst),
        .req   (mm_req),
        .we    (mm_we),
        .addr  (mm_addr),
        .wdata (mm_wdata),
        .rdata (mm_rdata),
        .ready (mm_ready)
    );

    // =========================================================================
    // FSM
    // =========================================================================
    typedef enum logic [3:0] {
        IDLE      = 4'd0,
        L1_WB     = 4'd1,   // Writeback de línea sucia de L1 a L2
        L2_CHECK  = 4'd2,   // Verificar si L2 tiene la línea
        L2_FILL   = 4'd3,   // Contar ciclos para hit en L2
        L2_WB     = 4'd4,   // Writeback de línea sucia de L2 a memoria
        MEM_FETCH = 4'd5,   // Esperar respuesta de memoria principal
        L2_UPDATE = 4'd6,   // Instalar línea en L2
        L1_UPDATE = 4'd7    // Instalar línea en L1
    } state_t;

    state_t state, next_state;

    // Ciclos de penalidad para L2_FILL (descontando el ciclo de L2_CHECK)
    localparam logic [5:0] FILL_INIT = L2_FILL_CYC - 2;

    // Registros de la FSM
    logic [31:0] active_addr;    // Dirección que causó el fallo (latched)
    logic        active_we;      // 1=STORE, 0=LOAD
    logic [31:0] active_wdata;   // Dato del STORE (si aplica)
    logic [5:0]  fill_cnt;       // Contador para L2_FILL (8 ciclos)
    logic [255:0] fetch_line;    // Línea traída desde memoria

    // Dirección de línea (alineada): limpia los 5 bits de offset
    logic [31:0] active_line_addr;
    assign active_line_addr = {active_addr[31:5], 5'b0};

    // ── Función auxiliar: extrae palabra[off] de una línea de 256 bits ────
    function automatic logic [31:0] sel_word(
        input logic [255:0] line,
        input logic [2:0]   off
    );
        case (off)
            3'd0: sel_word = line[ 31:  0];
            3'd1: sel_word = line[ 63: 32];
            3'd2: sel_word = line[ 95: 64];
            3'd3: sel_word = line[127: 96];
            3'd4: sel_word = line[159:128];
            3'd5: sel_word = line[191:160];
            3'd6: sel_word = line[223:192];
            3'd7: sel_word = line[255:224];
            default: sel_word = '0;
        endcase
    endfunction

    // ── Señales pre-calculadas fuera de always_* (Icarus constant-select safe) ──
    logic [2:0]  active_word_off;       // offset de palabra dentro de la línea
    logic [31:0] l2_hit_word;           // palabra a retornar en hit de L2
    logic [31:0] fetch_word;            // palabra a retornar tras fetch de mem
    logic [31:0] l2_victim_line_addr_w; // dirección de línea de la víctima L2

    assign active_word_off       = active_addr[4:2];
    assign l2_hit_word           = sel_word(l2_hit_line, active_word_off);
    assign fetch_word            = sel_word(fetch_line,  active_word_off);
    assign l2_victim_line_addr_w = {l2_victim_addr[31:5], 5'b0};

    // ── L2 siempre consulta la dirección activa ────────────────────────────
    always_comb begin
        if (state == IDLE)
            l2_req_addr = mem_addr;
        else
            l2_req_addr = active_addr;
    end

    // ── Registro de estado ─────────────────────────────────────────────────
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state       <= IDLE;
            active_addr  <= '0;
            active_we    <= 1'b0;
            active_wdata <= '0;
            fill_cnt     <= '0;
            fetch_line   <= '0;
        end else begin
            state <= next_state;

            case (state)
                IDLE: begin
                    if (mem_req && !l1_hit) begin
                        // Latch de la solicitud que causó el fallo
                        active_addr  <= mem_addr;
                        active_we    <= mem_we;
                        active_wdata <= mem_wdata;
                    end
                end

                L2_CHECK: begin
                    // Carga el contador de penalidad al confirmar hit en L2
                    if (l2_hit) fill_cnt <= FILL_INIT;
                end

                L2_FILL: begin
                    if (fill_cnt != '0) fill_cnt <= fill_cnt - 1;
                end

                MEM_FETCH: begin
                    if (mm_ready) fetch_line <= mm_rdata;
                end

                default: ;
            endcase
        end
    end

    // ── Lógica de transición y salidas de la FSM ──────────────────────────
    always_comb begin
        // Defaults: todas las señales a 0 / no-op
        next_state = state;

        l1_do_write_hit  = 1'b0;
        l1_wh_addr       = active_addr;
        l1_wh_data       = active_wdata;
        l1_wh_way        = l1_hit_way;
        l1_do_lru_update = 1'b0;
        l1_lu_addr       = active_addr;
        l1_lu_way        = l1_hit_way;
        l1_do_fill       = 1'b0;
        l1_fill_addr     = active_addr;
        l1_fill_data     = '0;
        l1_fill_word_we  = 1'b0;
        l1_fill_word_off  = active_word_off;
        l1_fill_word_data = active_wdata;

        l2_do_write_line = 1'b0;
        l2_wl_addr       = l1_victim_addr;
        l2_wl_data       = l1_victim_data;
        l2_do_fill       = 1'b0;
        l2_fill_addr     = active_addr;
        l2_fill_data     = fetch_line;

        mm_req   = 1'b0;
        mm_we    = 1'b0;
        mm_addr  = '0;
        mm_wdata = '0;

        mem_rdata   = l1_hit_rdata;
        cache_stall = 1'b0;

        ev_l1_hit    = 1'b0;
        ev_l1_miss   = 1'b0;
        ev_l2_hit    = 1'b0;
        ev_l2_miss   = 1'b0;
        ev_mem_access = 1'b0;

        case (state)

            // ────────────────────────────────────────────────────────────────
            IDLE: begin
                if (mem_req) begin
                    if (l1_hit) begin
                        // ── Hit en L1 ───────────────────────────────────────
                        mem_rdata    = l1_hit_rdata;
                        ev_l1_hit    = 1'b1;

                        if (mem_we) begin
                            // STORE hit: actualiza L1 y marca dirty
                            l1_do_write_hit = 1'b1;
                            l1_wh_addr      = mem_addr;
                            l1_wh_data      = mem_wdata;
                            l1_wh_way       = l1_hit_way;
                        end else begin
                            // LOAD hit: actualiza LRU
                            l1_do_lru_update = 1'b1;
                            l1_lu_addr       = mem_addr;
                            l1_lu_way        = l1_hit_way;
                        end
                        // Sin stall, permanecemos en IDLE
                    end else begin
                        // ── Fallo en L1 ─────────────────────────────────────
                        ev_l1_miss  = 1'b1;
                        cache_stall = 1'b1;

                        if (l1_victim_dirty) begin
                            // La víctima es dirty → escribirla en L2 primero
                            next_state = L1_WB;
                        end else begin
                            // Víctima limpia → consultar L2 directamente
                            next_state = L2_CHECK;
                        end
                    end
                end
            end

            // ────────────────────────────────────────────────────────────────
            L1_WB: begin
                // Escribe la línea sucia de L1 en L2 (1 ciclo)
                cache_stall      = 1'b1;
                l2_do_write_line = 1'b1;
                l2_wl_addr       = l1_victim_addr;
                l2_wl_data       = l1_victim_data;
                next_state       = L2_CHECK;
            end

            // ────────────────────────────────────────────────────────────────
            L2_CHECK: begin
                // Ciclo de verificación de L2 (combinacional sobre l2_hit)
                cache_stall = 1'b1;

                if (l2_hit) begin
                    // Hit en L2: fill_cnt se carga en always_ff al entrar a L2_FILL
                    ev_l2_hit  = 1'b1;
                    next_state = L2_FILL;
                end else begin
                    // Fallo en L2
                    ev_l2_miss = 1'b1;
                    if (l2_victim_dirty) begin
                        // Necesita writeback de L2 a memoria
                        next_state = L2_WB;
                    end else begin
                        // Fetch directo desde memoria
                        next_state = MEM_FETCH;
                    end
                end
            end

            // ────────────────────────────────────────────────────────────────
            L2_FILL: begin
                // Cuenta ciclos de penalidad por hit en L2
                cache_stall = 1'b1;

                if (fill_cnt == '0) begin
                    // Instalar línea de L2 en L1
                    l1_do_fill       = 1'b1;
                    l1_fill_addr     = active_addr;
                    l1_fill_data     = l2_hit_line;
                    l1_fill_word_we  = active_we;
                    l1_fill_word_off  = active_word_off;
                    l1_fill_word_data = active_wdata;

                    // Dato disponible para el pipeline
                    if (!active_we)
                        mem_rdata = l2_hit_word;

                    cache_stall = 1'b0;
                    next_state  = IDLE;
                end
            end

            // ────────────────────────────────────────────────────────────────
            L2_WB: begin
                // Writeback de línea sucia de L2 a memoria principal
                cache_stall  = 1'b1;
                mm_req       = !mm_ready;
                mm_we        = 1'b1;
                mm_addr      = l2_victim_line_addr_w;
                mm_wdata     = l2_victim_data;
                ev_mem_access = mm_req;

                if (mm_ready) begin
                    next_state = MEM_FETCH;
                end
            end

            // ────────────────────────────────────────────────────────────────
            MEM_FETCH: begin
                // Trae la línea solicitada desde memoria principal
                cache_stall   = 1'b1;
                mm_req        = !mm_ready;
                mm_we         = 1'b0;
                mm_addr       = active_line_addr;
                ev_mem_access = mm_req;

                if (mm_ready) begin
                    next_state = L2_UPDATE;
                end
            end

            // ────────────────────────────────────────────────────────────────
            L2_UPDATE: begin
                // Instala la línea traída de memoria en L2
                cache_stall  = 1'b1;
                l2_do_fill   = 1'b1;
                l2_fill_addr = active_addr;
                l2_fill_data = fetch_line;
                next_state   = L1_UPDATE;
            end

            // ────────────────────────────────────────────────────────────────
            L1_UPDATE: begin
                // Instala la línea en L1 (desde fetch_line)
                l1_do_fill       = 1'b1;
                l1_fill_addr     = active_addr;
                l1_fill_data     = fetch_line;
                l1_fill_word_we  = active_we;
                l1_fill_word_off  = active_word_off;
                l1_fill_word_data = active_wdata;

                if (!active_we)
                    mem_rdata = fetch_word;

                cache_stall = 1'b0;
                next_state  = IDLE;
            end

        endcase
    end

endmodule
