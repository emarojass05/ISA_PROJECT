// =============================================================================
// cache_l1d.sv  —  Caché de Datos L1
//
//  Tamaño   : 4 KB
//  Vías     : 2-way set-associative
//  Conjuntos: 64  (4096 / (32 B × 2) = 64)
//  Línea    : 32 B = 8 palabras de 32 bits
//  Etiqueta : 21 bits  (32 − 6 índice − 5 offset = 21)
//  Política : write-back + write-allocate
//  Reemplazo: LRU 1 bit por conjunto (0 = vía 0 es LRU, 1 = vía 1 es LRU)
//
//  Mapa de dirección (32 bits):
//    [31:11] tag (21 b)  |  [10:5] índice (6 b)  |  [4:2] palabra (3 b)  |  [1:0] byte
//
//  Operaciones registradas (se ejecutan en flanco de reloj):
//    do_write_hit  : escribe una palabra en la vía que hizo hit (marca dirty)
//    do_lru_update : actualiza LRU tras un hit de lectura
//    do_fill       : instala una línea nueva (expulsa víctima LRU)
//                    si fill_word_we=1, también escribe la palabra indicada
//                    (write-allocate) y marca la línea dirty
// =============================================================================

module cache_l1d #(
    parameter int XLEN       = 32,
    parameter int SETS       = 64,
    parameter int WAYS       = 2,
    parameter int LINE_WORDS = 8,
    parameter int TAG_W      = 21,
    parameter int IDX_W      = 6,
    parameter int OFF_W      = 3    // $clog2(LINE_WORDS)
)(
    input  logic clk,
    input  logic rst,

    // ── Puerto de consulta combinacional ──────────────────────────────────
    input  logic [31:0] req_addr,   // Dirección de la solicitud actual

    output logic        hit,        // 1 si hay hit en L1
    output logic        hit_way,    // Vía que hizo hit
    output logic [31:0] hit_rdata,  // Palabra leída en caso de hit

    // Información de víctima (LRU del conjunto)
    output logic        victim_dirty,
    output logic [31:0] victim_addr,    // Dirección byte de la línea víctima
    output logic [255:0] victim_data,   // Datos de la línea víctima

    // ── Operaciones registradas (sólo 1 activa por ciclo) ─────────────────

    // Escritura sobre hit (STORE que pega en L1)
    input  logic        do_write_hit,
    input  logic [31:0] wh_addr,        // Misma dirección que req_addr en ese ciclo
    input  logic [31:0] wh_data,
    input  logic        wh_way,

    // Actualización de LRU tras hit de lectura (LOAD)
    input  logic        do_lru_update,
    input  logic [31:0] lu_addr,
    input  logic        lu_way,

    // Relleno de línea tras fallo
    input  logic        do_fill,
    input  logic [31:0] fill_addr,
    input  logic [255:0] fill_data,
    // Escritura adicional (write-allocate: STORE que falló en L1)
    input  logic        fill_word_we,
    input  logic [2:0]  fill_word_off,
    input  logic [31:0] fill_word_data
);

    // ── Arrays de caché ───────────────────────────────────────────────────
    logic [TAG_W-1:0] tags  [0:SETS-1][0:WAYS-1];
    logic [255:0]     data  [0:SETS-1][0:WAYS-1];
    logic             valid [0:SETS-1][0:WAYS-1];
    logic             dirty [0:SETS-1][0:WAYS-1];
    logic             lru   [0:SETS-1];  // 0=vía0 es LRU, 1=vía1 es LRU

    integer ri, rj;
    initial begin
        for (ri = 0; ri < SETS; ri = ri + 1) begin
            lru[ri] = 1'b0;
            for (rj = 0; rj < WAYS; rj = rj + 1) begin
                valid[ri][rj] = 1'b0;
                dirty[ri][rj] = 1'b0;
                tags [ri][rj] = '0;
                data [ri][rj] = '0;
            end
        end
    end

    // ── Decodificación de req_addr ─────────────────────────────────────────
    logic [TAG_W-1:0] req_tag;
    logic [IDX_W-1:0] req_idx;
    logic [OFF_W-1:0] req_off;

    assign req_tag = req_addr[31:11];
    assign req_idx = req_addr[10:5];
    assign req_off = req_addr[4:2];

    // ── Extracción de arreglos por conjunto (assigns — Icarus-safe) ─────────
    // valid, tags, data y dirty para el conjunto req_idx (2 vías)
    logic             rv0, rv1;          // valid
    logic [TAG_W-1:0] rt0, rt1;          // tags
    logic [255:0]     rd0, rd1;          // data
    logic             rb0, rb1;          // dirty

    assign rv0 = valid[req_idx][0];
    assign rv1 = valid[req_idx][1];
    assign rt0 = tags [req_idx][0];
    assign rt1 = tags [req_idx][1];
    assign rd0 = data [req_idx][0];
    assign rd1 = data [req_idx][1];
    assign rb0 = dirty[req_idx][0];
    assign rb1 = dirty[req_idx][1];

    // ── Lógica de hit combinacional (sólo assigns) ─────────────────────────
    logic w0_hit, w1_hit;
    assign w0_hit = rv0 && (rt0 == req_tag);
    assign w1_hit = rv1 && (rt1 == req_tag);

    assign hit       = w0_hit | w1_hit;
    assign hit_way   = w1_hit ? 1'b1 : 1'b0;
    assign hit_rdata = sel_word(w1_hit ? rd1 : rd0, req_off);

    // ── Información de víctima (combinacional) ─────────────────────────────
    logic victim_way;
    assign victim_way   = lru[req_idx];
    assign victim_dirty = victim_way ? rb1 : rb0;
    assign victim_data  = victim_way ? rd1 : rd0;
    assign victim_addr  = {(victim_way ? rt1 : rt0), req_idx, 5'b0};
    // Nota: victim_addr es la dirección byte de la línea (offset = 0)

    // ── Decodificación de fill_addr ────────────────────────────────────────
    logic [IDX_W-1:0] fill_idx;
    logic [TAG_W-1:0] fill_tag;
    assign fill_idx = fill_addr[10:5];
    assign fill_tag = fill_addr[31:11];

    // ── Decodificación de write-hit ────────────────────────────────────────
    logic [IDX_W-1:0] wh_idx;
    logic [OFF_W-1:0] wh_off;
    assign wh_idx = wh_addr[10:5];
    assign wh_off = wh_addr[4:2];

    // ── Decodificación de lru-update ──────────────────────────────────────
    logic [IDX_W-1:0] lu_idx;
    assign lu_idx = lu_addr[10:5];

    // ── Función auxiliar: extrae palabra[off] de una línea de 256 bits ─────
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

    // ── Función auxiliar: inserta una palabra en posición off de una línea ─
    function automatic logic [255:0] insert_word(
        input logic [255:0] line,
        input logic [2:0]   off,
        input logic [31:0]  word
    );
        logic [255:0] tmp;
        tmp = line;
        case (off)
            3'd0: tmp[ 31:  0] = word;
            3'd1: tmp[ 63: 32] = word;
            3'd2: tmp[ 95: 64] = word;
            3'd3: tmp[127: 96] = word;
            3'd4: tmp[159:128] = word;
            3'd5: tmp[191:160] = word;
            3'd6: tmp[223:192] = word;
            3'd7: tmp[255:224] = word;
        endcase
        return tmp;
    endfunction

    // Variable auxiliar para la lógica de relleno
    logic fill_victim_way;

    assign fill_victim_way = lru[fill_idx];

    // ── Operaciones registradas ────────────────────────────────────────────
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int i = 0; i < SETS; i++) begin
                lru[i]   <= 1'b0;
                for (int j = 0; j < WAYS; j++) begin
                    valid[i][j] <= 1'b0;
                    dirty[i][j] <= 1'b0;
                    tags [i][j] <= '0;
                    data [i][j] <= '0;
                end
            end
        end else begin

            // ── Relleno de línea (do_fill tiene prioridad) ─────────────────
            if (do_fill) begin
                valid[fill_idx][fill_victim_way] <= 1'b1;
                tags [fill_idx][fill_victim_way] <= fill_tag;

                if (fill_word_we) begin
                    // Write-allocate: instala la línea Y escribe la palabra de STORE
                    data [fill_idx][fill_victim_way] <=
                        insert_word(fill_data, fill_word_off, fill_word_data);
                    dirty[fill_idx][fill_victim_way] <= 1'b1;
                end else begin
                    data [fill_idx][fill_victim_way] <= fill_data;
                    dirty[fill_idx][fill_victim_way] <= 1'b0;
                end

                // La línea recién instalada es MRU → la otra vía pasa a ser LRU
                lru[fill_idx] <= ~fill_victim_way;
            end

            // ── Write-hit: actualiza palabra y marca dirty ─────────────────
            else if (do_write_hit) begin
                data [wh_idx][wh_way][wh_off*32 +: 32] <= wh_data;
                dirty[wh_idx][wh_way] <= 1'b1;
                lru  [wh_idx]         <= ~wh_way;
            end

            // ── LRU update tras hit de lectura ─────────────────────────────
            else if (do_lru_update) begin
                lru[lu_idx] <= ~lu_way;
            end

        end
    end

endmodule
