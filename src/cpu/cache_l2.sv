// =============================================================================
// cache_l2.sv — L2 Unified Cache
// =============================================================================
// Capacidad    : 16 KB
// Asociatividad: 4-way set-associative
// Sets         : 128
// Línea        : 32 bytes (8 palabras × 32 bits = 256 bits)
// Reemplazo    : Pseudo-LRU (árbol binario de 3 bits por set)
// Escritura    : Write-back (sin write-allocate — eso es responsabilidad de L1)
//
// L2 trabaja con LÍNEAS COMPLETAS de 256 bits, no con palabras individuales.
// El cache_ctrl es el que descompone la línea en la palabra que necesita L1.
//
// Pseudo-LRU (árbol de 3 nodos internos para 4 ways):
//
//          b[2]
//         /    \
//       b[1]   b[0]
//       / \    / \
//      w0  w1 w2  w3
//
//   Cada bit apunta al lado que fue MRU → el LRU está en el lado opuesto.
//   LRU way:
//     b[2]=0 → ir a izquierda: b[1]=0→w0, b[1]=1→w1
//     b[2]=1 → ir a derecha:   b[0]=0→w2, b[0]=1→w3
//
//   Al acceder al way X, los bits se actualizan apuntando LEJOS de X:
//     w0: b[2]=1, b[1]=1     w1: b[2]=1, b[1]=0
//     w2: b[2]=0, b[0]=1     w3: b[2]=0, b[0]=0
//
// Interfaz (desde cache_ctrl):
//   Consulta (combinacional):
//     req_addr       → dirección de 32 bits
//     hit            → 1 si la línea está en L2
//     hit_way        → 2 bits indicando el way
//     hit_rdata_line → línea completa de 256 bits (válida si hit=1)
//     victim_dirty   → la víctima tiene dirty bit activo
//     victim_addr    → dirección base de la víctima
//     victim_data    → línea completa de 256 bits de la víctima
//
//   Operaciones (registradas):
//     do_fill        → escribe una línea nueva (de main_mem) en el way LRU
//     fill_addr      → dirección base de la línea nueva
//     fill_data      → 256 bits a escribir
//     do_write_line  → actualiza una línea entera (write-back desde L1)
//     wline_addr     → dirección base de la línea a actualizar
//     wline_data     → 256 bits con el contenido nuevo
//     do_lru_update  → actualiza PLRU tras un hit
//     lru_set        → índice del set (7 bits)
//     lru_way        → way que se acaba de usar (2 bits)
// =============================================================================

module cache_l2 #(
    parameter int XLEN        = 32,
    parameter int SETS        = 128,     // 2^7
    parameter int WAYS        = 4,
    parameter int LINE_WORDS  = 8,
    parameter int LINE_BITS   = LINE_WORDS * 32   // 256 bits
)(
    input  logic clk,
    input  logic rst,

    // ── Consulta combinacional ────────────────────────────────────────────
    input  logic [XLEN-1:0]       req_addr,

    output logic                  hit,
    output logic [1:0]            hit_way,
    output logic [LINE_BITS-1:0]  hit_rdata_line,
    output logic                  victim_dirty,
    output logic [XLEN-1:0]       victim_addr,
    output logic [LINE_BITS-1:0]  victim_data,

    // ── Fill (traer línea de main_mem) ────────────────────────────────────
    input  logic                  do_fill,
    input  logic [XLEN-1:0]       fill_addr,
    input  logic [LINE_BITS-1:0]  fill_data,

    // ── Write-line (write-back desde L1) ─────────────────────────────────
    input  logic                  do_write_line,
    input  logic [XLEN-1:0]       wline_addr,
    input  logic [LINE_BITS-1:0]  wline_data,

    // ── Actualización de PLRU ─────────────────────────────────────────────
    input  logic                  do_lru_update,
    input  logic [6:0]            lru_set,
    input  logic [1:0]            lru_way
);

    // ── Constantes de descomposición de dirección ─────────────────────────
    //   [31:12] tag    (20 bits)
    //   [11:5]  index  (7 bits)
    //   [4:0]   offset (5 bits)
    localparam int OFFSET_BITS = $clog2(LINE_WORDS) + 2;  // 5
    localparam int INDEX_BITS  = $clog2(SETS);             // 7
    localparam int TAG_BITS    = XLEN - INDEX_BITS - OFFSET_BITS; // 20

    // ── Arrays del caché ─────────────────────────────────────────────────
    logic                  valid [WAYS][SETS];
    logic                  dirty [WAYS][SETS];
    logic [TAG_BITS-1:0]   tags  [WAYS][SETS];
    logic [LINE_BITS-1:0]  data  [WAYS][SETS];
    logic [2:0]            plru  [SETS];   // árbol PLRU de 3 bits (unpacked)

    // ── Descomposición de req_addr ────────────────────────────────────────
    logic [TAG_BITS-1:0]   req_tag;
    logic [INDEX_BITS-1:0] req_index;

    assign req_tag   = req_addr[XLEN-1 : INDEX_BITS+OFFSET_BITS];
    assign req_index = req_addr[INDEX_BITS+OFFSET_BITS-1 : OFFSET_BITS];

    // ── Extraer por-way para req_index (genvar = índice constante, req_index = variable) ──
    logic                  req_valid_w [WAYS];
    logic                  req_dirty_w [WAYS];
    logic [TAG_BITS-1:0]   req_tag_w   [WAYS];
    logic [LINE_BITS-1:0]  req_data_w  [WAYS];

    genvar gw;
    generate
        for (gw = 0; gw < WAYS; gw++) begin : gen_req_extract
            assign req_valid_w[gw] = valid[gw][req_index];
            assign req_dirty_w[gw] = dirty[gw][req_index];
            assign req_tag_w[gw]   = tags [gw][req_index];
            assign req_data_w[gw]  = data [gw][req_index];
        end
    endgenerate

    // ── Lógica hit combinacional (assign, sin always_comb) ───────────────
    logic hit_w [WAYS];
    assign hit_w[0] = req_valid_w[0] && (req_tag_w[0] == req_tag);
    assign hit_w[1] = req_valid_w[1] && (req_tag_w[1] == req_tag);
    assign hit_w[2] = req_valid_w[2] && (req_tag_w[2] == req_tag);
    assign hit_w[3] = req_valid_w[3] && (req_tag_w[3] == req_tag);

    assign hit = hit_w[0] | hit_w[1] | hit_w[2] | hit_w[3];

    // Mux explícito: victim_way sólo se usa como selector ternario, nunca como índice
    assign hit_way = hit_w[3] ? 2'd3 : hit_w[2] ? 2'd2 : hit_w[1] ? 2'd1 : 2'd0;

    assign hit_rdata_line = hit_w[3] ? req_data_w[3] :
                            hit_w[2] ? req_data_w[2] :
                            hit_w[1] ? req_data_w[1] : req_data_w[0];

    // ── Selección de víctima por PLRU (assign sobre unpacked 1D → OK en Icarus) ──
    logic [2:0]  req_plru;
    logic [1:0]  victim_way;

    assign req_plru    = plru[req_index];
    assign victim_way  = !req_plru[2] ? (req_plru[1] ? 2'd1 : 2'd0)
                                      : (req_plru[0] ? 2'd3 : 2'd2);

    assign victim_dirty = (victim_way == 2'd3) ? req_dirty_w[3] :
                          (victim_way == 2'd2) ? req_dirty_w[2] :
                          (victim_way == 2'd1) ? req_dirty_w[1] : req_dirty_w[0];

    assign victim_addr  = (victim_way == 2'd3) ? {req_tag_w[3], req_index, {OFFSET_BITS{1'b0}}} :
                          (victim_way == 2'd2) ? {req_tag_w[2], req_index, {OFFSET_BITS{1'b0}}} :
                          (victim_way == 2'd1) ? {req_tag_w[1], req_index, {OFFSET_BITS{1'b0}}} :
                                                 {req_tag_w[0], req_index, {OFFSET_BITS{1'b0}}};

    assign victim_data  = (victim_way == 2'd3) ? req_data_w[3] :
                          (victim_way == 2'd2) ? req_data_w[2] :
                          (victim_way == 2'd1) ? req_data_w[1] : req_data_w[0];

    // ── Función PLRU update ───────────────────────────────────────────────
    // Devuelve el nuevo valor de plru[set] tras acceder al way dado.
    // w0: b[2]=1, b[1]=1    w1: b[2]=1, b[1]=0
    // w2: b[2]=0, b[0]=1    w3: b[2]=0, b[0]=0
    function automatic logic [2:0] plru_update(
        input logic [2:0] old_plru,
        input logic [1:0] used_way
    );
        logic [2:0] np;
        np = old_plru;
        case (used_way)
            2'd0: begin np[2] = 1'b1; np[1] = 1'b1; end
            2'd1: begin np[2] = 1'b1; np[1] = 1'b0; end
            2'd2: begin np[2] = 1'b0; np[0] = 1'b1; end
            2'd3: begin np[2] = 1'b0; np[0] = 1'b0; end
            default: np = old_plru;
        endcase
        return np;
    endfunction

    // ── Señales auxiliares para operaciones registradas ───────────────────
    logic [INDEX_BITS-1:0] fill_index;
    logic [TAG_BITS-1:0]   fill_tag;
    logic [INDEX_BITS-1:0] wline_index;
    logic [TAG_BITS-1:0]   wline_tag;

    assign fill_index  = fill_addr[INDEX_BITS+OFFSET_BITS-1 : OFFSET_BITS];
    assign fill_tag    = fill_addr[XLEN-1 : INDEX_BITS+OFFSET_BITS];
    assign wline_index = wline_addr[INDEX_BITS+OFFSET_BITS-1 : OFFSET_BITS];
    assign wline_tag   = wline_addr[XLEN-1 : INDEX_BITS+OFFSET_BITS];

    // ── Víctima para fill_index (assign sobre unpacked 1D → OK) ─────────
    logic [2:0]  fill_plru;
    logic [1:0]  fill_victim_way;

    assign fill_plru       = plru[fill_index];
    assign fill_victim_way = !fill_plru[2] ? (fill_plru[1] ? 2'd1 : 2'd0)
                                           : (fill_plru[0] ? 2'd3 : 2'd2);

    // ── Way que contiene wline_addr (extraer con genvar, luego mux) ──────
    logic                wl_valid_w [WAYS];
    logic [TAG_BITS-1:0] wl_tag_w   [WAYS];
    generate
        for (gw = 0; gw < WAYS; gw++) begin : gen_wl_extract
            assign wl_valid_w[gw] = valid[gw][wline_index];
            assign wl_tag_w[gw]   = tags [gw][wline_index];
        end
    endgenerate

    logic [1:0] wline_way;
    assign wline_way = (wl_valid_w[3] && wl_tag_w[3] == wline_tag) ? 2'd3 :
                       (wl_valid_w[2] && wl_tag_w[2] == wline_tag) ? 2'd2 :
                       (wl_valid_w[1] && wl_tag_w[1] == wline_tag) ? 2'd1 : 2'd0;

    // ── Operaciones registradas ───────────────────────────────────────────
    integer s, w;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (w = 0; w < WAYS; w++) begin
                for (s = 0; s < SETS; s++) begin
                    valid[w][s] <= 1'b0;
                    dirty[w][s] <= 1'b0;
                    tags [w][s] <= '0;
                    data [w][s] <= '0;
                end
            end
            for (s = 0; s < SETS; s++)
                plru[s] <= 3'b000;

        end else begin

            // Fill: case sobre fill_victim_way → primer índice constante
            if (do_fill) begin
                case (fill_victim_way)
                    2'd0: begin valid[0][fill_index]<=1'b1; dirty[0][fill_index]<=1'b0; tags[0][fill_index]<=fill_tag; data[0][fill_index]<=fill_data; end
                    2'd1: begin valid[1][fill_index]<=1'b1; dirty[1][fill_index]<=1'b0; tags[1][fill_index]<=fill_tag; data[1][fill_index]<=fill_data; end
                    2'd2: begin valid[2][fill_index]<=1'b1; dirty[2][fill_index]<=1'b0; tags[2][fill_index]<=fill_tag; data[2][fill_index]<=fill_data; end
                    2'd3: begin valid[3][fill_index]<=1'b1; dirty[3][fill_index]<=1'b0; tags[3][fill_index]<=fill_tag; data[3][fill_index]<=fill_data; end
                endcase
                plru[fill_index] <= plru_update(plru[fill_index], fill_victim_way);
            end

            // Write-line: case sobre wline_way → primer índice constante
            if (do_write_line) begin
                case (wline_way)
                    2'd0: begin data[0][wline_index]<=wline_data; dirty[0][wline_index]<=1'b1; end
                    2'd1: begin data[1][wline_index]<=wline_data; dirty[1][wline_index]<=1'b1; end
                    2'd2: begin data[2][wline_index]<=wline_data; dirty[2][wline_index]<=1'b1; end
                    2'd3: begin data[3][wline_index]<=wline_data; dirty[3][wline_index]<=1'b1; end
                endcase
                plru[wline_index] <= plru_update(plru[wline_index], wline_way);
            end

            // Actualización de PLRU por hit (sin escritura)
            if (do_lru_update) begin
                plru[lru_set] <= plru_update(plru[lru_set], lru_way);
            end

        end
    end

endmodule
