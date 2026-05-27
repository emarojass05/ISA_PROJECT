// =============================================================================
// cache_l2.sv  —  Caché Unificada L2
//
//  Tamaño   : 16 KB
//  Vías     : 4-way set-associative
//  Conjuntos: 128  (16384 / (32 B × 4) = 128)
//  Línea    : 32 B = 8 palabras de 32 bits
//  Etiqueta : 20 bits  (32 − 7 índice − 5 offset = 20)
//  Política : write-back
//  Reemplazo: Pseudo-LRU árbol de 3 bits por conjunto
//
//  Mapa de dirección (32 bits):
//    [31:12] tag (20 b)  |  [11:5] índice (7 b)  |  [4:2] palabra (3 b)  |  [1:0] byte
//
//  Árbol Pseudo-LRU para 4 vías  (bits b2 b1 b0):
//         [b2]
//        /    \
//      [b1]  [b0]
//      / \   / \
//     W0 W1 W2 W3
//
//  Convención:
//    b2=0 → LRU en mitad derecha (W2/W3) → víctima de la derecha
//    b2=1 → LRU en mitad izquierda (W0/W1) → víctima de la izquierda
//    b1=0 → W0 es LRU en izquierda; b1=1 → W1 es LRU
//    b0=0 → W2 es LRU en derecha;   b0=1 → W3 es LRU
//
//  Operaciones registradas:
//    do_write_line : escribe una línea completa en L2 (writeback de L1)
//    do_fill       : instala línea de memoria principal (expulsa víctima)
// =============================================================================

module cache_l2 #(
    parameter int XLEN       = 32,
    parameter int SETS       = 128,
    parameter int WAYS       = 4,
    parameter int LINE_WORDS = 8,
    parameter int TAG_W      = 20,
    parameter int IDX_W      = 7,
    parameter int OFF_W      = 3
)(
    input  logic clk,
    input  logic rst,

    // ── Puerto de consulta combinacional ──────────────────────────────────
    input  logic [31:0] req_addr,

    output logic        hit,
    output logic [1:0]  hit_way,
    output logic [255:0] hit_rdata_line,  // Línea completa (para relleno de L1)

    // Información de víctima
    output logic        victim_dirty,
    output logic [31:0] victim_addr,
    output logic [255:0] victim_data,

    // ── do_write_line: instala/actualiza línea desde L1 (writeback) ───────
    // Siempre se hace write-allocate: si la línea no está, se instala igual
    input  logic        do_write_line,
    input  logic [31:0] wl_addr,
    input  logic [255:0] wl_data,

    // ── do_fill: instala línea desde memoria principal ─────────────────────
    input  logic        do_fill,
    input  logic [31:0] fill_addr,
    input  logic [255:0] fill_data
);

    // ── Arrays de caché ───────────────────────────────────────────────────
    logic [TAG_W-1:0] tags  [0:SETS-1][0:WAYS-1];
    logic [255:0]     data  [0:SETS-1][0:WAYS-1];
    logic             valid [0:SETS-1][0:WAYS-1];
    logic             dirty [0:SETS-1][0:WAYS-1];
    logic [2:0]       plru  [0:SETS-1];  // Árbol Pseudo-LRU

    integer ri, rj;
    initial begin
        for (ri = 0; ri < SETS; ri = ri + 1) begin
            plru[ri] = 3'b000;
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

    assign req_tag = req_addr[31:12];
    assign req_idx = req_addr[11:5];
    assign req_off = req_addr[4:2];

    // ── Extracción por conjunto req_idx (assigns — Icarus-safe) ─────────────
    logic             lv0,lv1,lv2,lv3;
    logic [TAG_W-1:0] lt0,lt1,lt2,lt3;
    logic [255:0]     ld0,ld1,ld2,ld3;
    logic             lb0,lb1,lb2,lb3;
    logic [2:0]       lp_req;

    assign lv0=valid[req_idx][0]; assign lt0=tags[req_idx][0];
    assign ld0=data [req_idx][0]; assign lb0=dirty[req_idx][0];
    assign lv1=valid[req_idx][1]; assign lt1=tags[req_idx][1];
    assign ld1=data [req_idx][1]; assign lb1=dirty[req_idx][1];
    assign lv2=valid[req_idx][2]; assign lt2=tags[req_idx][2];
    assign ld2=data [req_idx][2]; assign lb2=dirty[req_idx][2];
    assign lv3=valid[req_idx][3]; assign lt3=tags[req_idx][3];
    assign ld3=data [req_idx][3]; assign lb3=dirty[req_idx][3];
    assign lp_req = plru[req_idx];

    // ── Lógica de hit combinacional (sólo assigns) ─────────────────────────
    logic lw0,lw1,lw2,lw3;
    assign lw0 = lv0 && (lt0 == req_tag);
    assign lw1 = lv1 && (lt1 == req_tag);
    assign lw2 = lv2 && (lt2 == req_tag);
    assign lw3 = lv3 && (lt3 == req_tag);

    assign hit           = lw0 | lw1 | lw2 | lw3;
    assign hit_way       = lw0 ? 2'd0 : lw1 ? 2'd1 : lw2 ? 2'd2 : 2'd3;
    assign hit_rdata_line = lw0 ? ld0 : lw1 ? ld1 : lw2 ? ld2 : ld3;

    // ── Selección de víctima Pseudo-LRU (sólo assigns) ────────────────────
    logic [1:0] victim_way;
    assign victim_way  = !lp_req[2] ? (lp_req[0] ? 2'd3 : 2'd2)
                                    : (lp_req[1] ? 2'd1 : 2'd0);

    assign victim_dirty = victim_way[1] ? (victim_way[0] ? lb3 : lb2)
                                        : (victim_way[0] ? lb1 : lb0);
    assign victim_data  = victim_way[1] ? (victim_way[0] ? ld3 : ld2)
                                        : (victim_way[0] ? ld1 : ld0);
    assign victim_addr  = {(victim_way[1] ? (victim_way[0] ? lt3 : lt2)
                                          : (victim_way[0] ? lt1 : lt0)),
                           req_idx, 5'b0};

    // ── Función de actualización de Pseudo-LRU ─────────────────────────────
    // Devuelve los nuevos 3 bits de plru tras acceder a la vía `way`
    function automatic logic [2:0] plru_update(
        input logic [2:0] p,
        input logic [1:0] way
    );
        logic [2:0] np;
        np = p;
        case (way)
            2'd0: begin np[2] = 1'b1; np[1] = 1'b1; end  // W0 es MRU
            2'd1: begin np[2] = 1'b1; np[1] = 1'b0; end  // W1 es MRU
            2'd2: begin np[2] = 1'b0; np[0] = 1'b1; end  // W2 es MRU
            2'd3: begin np[2] = 1'b0; np[0] = 1'b0; end  // W3 es MRU
        endcase
        return np;
    endfunction

    // ── Decodificación de operaciones ──────────────────────────────────────
    logic [IDX_W-1:0] wl_idx;
    logic [TAG_W-1:0] wl_tag;
    assign wl_idx = wl_addr[11:5];
    assign wl_tag = wl_addr[31:12];

    logic [IDX_W-1:0] fill_idx;
    logic [TAG_W-1:0] fill_tag;
    assign fill_idx = fill_addr[11:5];
    assign fill_tag = fill_addr[31:12];

    // Variables auxiliares de módulo (sin automatic)
    logic [1:0]       fill_victim_way_l2;
    logic [1:0]       wl_way_found;
    logic             wl_hit_found;
    logic [1:0]       wl_victim_way;
    logic [2:0]       plru_fill;   // plru[fill_idx]
    logic [2:0]       plru_wl;     // plru[wl_idx]

    // Señales intermedias para wl_idx (Icarus-safe — evita índice variable en always_*)
    logic             wlv0, wlv1, wlv2, wlv3;
    logic [TAG_W-1:0] wlt0, wlt1, wlt2, wlt3;

    assign plru_fill = plru[fill_idx];
    assign plru_wl   = plru[wl_idx];

    assign wlv0 = valid[wl_idx][0]; assign wlt0 = tags[wl_idx][0];
    assign wlv1 = valid[wl_idx][1]; assign wlt1 = tags[wl_idx][1];
    assign wlv2 = valid[wl_idx][2]; assign wlt2 = tags[wl_idx][2];
    assign wlv3 = valid[wl_idx][3]; assign wlt3 = tags[wl_idx][3];

    // Víctima para do_fill (combinacional directa)
    assign fill_victim_way_l2 = !plru_fill[2]
                                 ? (plru_fill[0] ? 2'd3 : 2'd2)
                                 : (plru_fill[1] ? 2'd1 : 2'd0);

    // Víctima para do_write_line (combinacional directa)
    assign wl_victim_way = !plru_wl[2]
                            ? (plru_wl[0] ? 2'd3 : 2'd2)
                            : (plru_wl[1] ? 2'd1 : 2'd0);

    // Búsqueda de hit en do_write_line (assigns — Icarus-safe)
    assign wl_hit_found = (wlv0 && wlt0 == wl_tag) ||
                          (wlv1 && wlt1 == wl_tag) ||
                          (wlv2 && wlt2 == wl_tag) ||
                          (wlv3 && wlt3 == wl_tag);

    assign wl_way_found = (wlv0 && wlt0 == wl_tag) ? 2'd0 :
                          (wlv1 && wlt1 == wl_tag) ? 2'd1 :
                          (wlv2 && wlt2 == wl_tag) ? 2'd2 : 2'd3;

    // ── Operaciones registradas ────────────────────────────────────────────
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int i = 0; i < SETS; i++) begin
                plru[i] <= 3'b000;
                for (int j = 0; j < WAYS; j++) begin
                    valid[i][j] <= 1'b0;
                    dirty[i][j] <= 1'b0;
                    tags [i][j] <= '0;
                    data [i][j] <= '0;
                end
            end
        end else begin

            // ── Relleno desde memoria principal ───────────────────────────
            if (do_fill) begin
                valid[fill_idx][fill_victim_way_l2] <= 1'b1;
                dirty[fill_idx][fill_victim_way_l2] <= 1'b0;
                tags [fill_idx][fill_victim_way_l2] <= fill_tag;
                data [fill_idx][fill_victim_way_l2] <= fill_data;
                plru [fill_idx] <= plru_update(plru[fill_idx], fill_victim_way_l2);
            end

            // ── Escritura de línea (writeback de L1) ──────────────────────
            else if (do_write_line) begin
                if (wl_hit_found) begin
                    data [wl_idx][wl_way_found] <= wl_data;
                    dirty[wl_idx][wl_way_found] <= 1'b1;
                    plru [wl_idx] <= plru_update(plru[wl_idx], wl_way_found);
                end else begin
                    // Miss en L2: instala en la vía víctima
                    valid[wl_idx][wl_victim_way] <= 1'b1;
                    dirty[wl_idx][wl_victim_way] <= 1'b1;
                    tags [wl_idx][wl_victim_way] <= wl_tag;
                    data [wl_idx][wl_victim_way] <= wl_data;
                    plru [wl_idx] <= plru_update(plru[wl_idx], wl_victim_way);
                end
            end

        end
    end

endmodule
