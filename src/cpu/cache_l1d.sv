// =============================================================================
// cache_l1d.sv — L1 Data Cache
// =============================================================================
// Capacidad   : 4 KB
// Asociatividad: 2-way set-associative
// Sets        : 64
// Línea       : 32 bytes (8 palabras de 32 bits)
// Reemplazo   : LRU (1 bit por set: 0 = way 0 fue usado último, 1 = way 1)
// Escritura   : Write-back + Write-allocate
//
// Interfaz (desde cache_ctrl):
//   Consulta (combinacional, mismo ciclo):
//     req_addr   → dirección de 32 bits
//     hit        → 1 si la línea está en caché
//     hit_way    → qué way tiene el hit (0 ó 1)
//     hit_rdata  → palabra de 32 bits leída (válida solo si hit=1)
//     victim_dirty → la víctima del set tiene dirty bit activo
//     victim_addr  → dirección base de la víctima (para write-back a L2)
//     victim_data  → línea completa de 256 bits de la víctima
//
//   Operaciones (registradas, actúan en el flanco siguiente):
//     do_fill       → escribe una línea nueva (desde L2/mem) en hit_way ^ 1
//     fill_way      → qué way llenar (decide el controlador)
//     fill_addr     → dirección base de la nueva línea
//     fill_data     → 256 bits de datos a escribir
//     do_write_hit  → escribe una palabra en el way del hit (store hit)
//     write_way     → way donde escribir
//     write_addr    → dirección completa (word offset en [4:2])
//     write_data    → 32 bits a escribir
//     do_lru_update → actualiza LRU después de un hit
//     lru_set       → índice del set a actualizar
//     lru_way       → way que se acaba de usar
// =============================================================================

module cache_l1d #(
    parameter int XLEN        = 32,
    parameter int SETS        = 64,      // 2^6
    parameter int WAYS        = 2,
    parameter int LINE_WORDS  = 8,       // 32 bytes / 4 bytes
    parameter int LINE_BITS   = LINE_WORDS * 32  // 256 bits
)(
    input  logic clk,
    input  logic rst,

    // ── Consulta combinacional ────────────────────────────────────────────
    input  logic [XLEN-1:0]      req_addr,

    output logic                 hit,
    output logic                 hit_way,
    output logic [31:0]          hit_rdata,
    output logic                 victim_dirty,
    output logic [XLEN-1:0]      victim_addr,
    output logic [LINE_BITS-1:0] victim_data,

    // ── Fill (traer línea nueva) ──────────────────────────────────────────
    input  logic                 do_fill,
    input  logic                 fill_way,
    input  logic [XLEN-1:0]      fill_addr,
    input  logic [LINE_BITS-1:0] fill_data,

    // ── Write-hit (store que pegó en caché) ──────────────────────────────
    input  logic                 do_write_hit,
    input  logic                 write_way,
    input  logic [XLEN-1:0]      write_addr,
    input  logic [31:0]          write_data,

    // ── Actualización de LRU ─────────────────────────────────────────────
    input  logic                 do_lru_update,
    input  logic [$clog2(SETS)-1:0] lru_set,
    input  logic                    lru_way
);

    // ── Constantes de descomposición de dirección ─────────────────────────
    //   [31:11] tag  (21 bits)
    //   [10:5]  index (6 bits)
    //   [4:2]   word offset (3 bits → 8 palabras)
    //   [1:0]   byte offset (ignorado, acceso word-aligned)
    localparam int OFFSET_BITS = $clog2(LINE_WORDS) + 2;  // 5 bits
    localparam int INDEX_BITS  = $clog2(SETS);             // 6 bits
    localparam int TAG_BITS    = XLEN - INDEX_BITS - OFFSET_BITS; // 21 bits

    // ── Arrays del caché ─────────────────────────────────────────────────
    logic                  valid [WAYS][SETS];
    logic                  dirty [WAYS][SETS];
    logic [TAG_BITS-1:0]   tags  [WAYS][SETS];
    logic [LINE_BITS-1:0]  data  [WAYS][SETS];
    logic                  lru   [SETS];   // 0 = usar way1 next, 1 = usar way0 next

    // ── Descomposición de req_addr ────────────────────────────────────────
    logic [TAG_BITS-1:0]          req_tag;
    logic [INDEX_BITS-1:0]        req_index;
    logic [$clog2(LINE_WORDS)-1:0] req_word;

    assign req_tag   = req_addr[XLEN-1 : INDEX_BITS+OFFSET_BITS];
    assign req_index = req_addr[INDEX_BITS+OFFSET_BITS-1 : OFFSET_BITS];
    assign req_word  = req_addr[OFFSET_BITS-1 : 2];

    // ── Lógica hit combinacional ─────────────────────────────────────────
    logic hit0, hit1;

    assign hit0 = valid[0][req_index] && (tags[0][req_index] == req_tag);
    assign hit1 = valid[1][req_index] && (tags[1][req_index] == req_tag);
    assign hit  = hit0 | hit1;

    assign hit_way = hit1;  // way 1 si hit1, way 0 si hit0 (hit0 toma precedencia)

    // Datos leídos del way correcto
    assign hit_rdata = hit1
        ? data[1][req_index][req_word*32 +: 32]
        : data[0][req_index][req_word*32 +: 32];

    // ── Información de víctima (para write-back al hacer fill) ───────────
    // La víctima es el way que LRU indica reemplazar
    logic victim_way_sel;
    assign victim_way_sel = lru[req_index];  // 0 = reemplazar way0, 1 = reemplazar way1

    // Mux explícito: victim_way_sel sólo como selector, nunca como índice de array
    assign victim_dirty = victim_way_sel ? dirty[1][req_index] : dirty[0][req_index];
    assign victim_addr  = victim_way_sel
        ? {tags[1][req_index], req_index, {OFFSET_BITS{1'b0}}}
        : {tags[0][req_index], req_index, {OFFSET_BITS{1'b0}}};
    assign victim_data  = victim_way_sel ? data[1][req_index] : data[0][req_index];

    // ── Señales auxiliares para operaciones registradas ──────────────────
    logic [INDEX_BITS-1:0]         fill_index;
    logic [TAG_BITS-1:0]           fill_tag;
    logic [$clog2(LINE_WORDS)-1:0] write_word;
    logic [INDEX_BITS-1:0]         write_index;

    assign fill_index  = fill_addr[INDEX_BITS+OFFSET_BITS-1 : OFFSET_BITS];
    assign fill_tag    = fill_addr[XLEN-1 : INDEX_BITS+OFFSET_BITS];
    assign write_word  = write_addr[OFFSET_BITS-1 : 2];
    assign write_index = write_addr[INDEX_BITS+OFFSET_BITS-1 : OFFSET_BITS];

    // ── Operaciones registradas ──────────────────────────────────────────
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
                lru[s] <= 1'b0;

        end else begin

            // Fill: if/else sobre fill_way (1-bit) → primer índice constante
            if (do_fill) begin
                if (fill_way) begin
                    valid[1][fill_index] <= 1'b1; dirty[1][fill_index] <= 1'b0;
                    tags [1][fill_index] <= fill_tag; data[1][fill_index] <= fill_data;
                end else begin
                    valid[0][fill_index] <= 1'b1; dirty[0][fill_index] <= 1'b0;
                    tags [0][fill_index] <= fill_tag; data[0][fill_index] <= fill_data;
                end
                lru[fill_index] <= ~fill_way;
            end

            // Write-hit: if/else sobre write_way → primer índice constante
            if (do_write_hit) begin
                if (write_way) begin
                    data [1][write_index][write_word*32 +: 32] <= write_data;
                    dirty[1][write_index]                       <= 1'b1;
                end else begin
                    data [0][write_index][write_word*32 +: 32] <= write_data;
                    dirty[0][write_index]                       <= 1'b1;
                end
                lru[write_index] <= ~write_way;
            end

            // Actualización de LRU por read-hit (sin escritura)
            if (do_lru_update) begin
                lru[lru_set] <= ~lru_way;
            end

        end
    end

endmodule
