// =============================================================================
// perf_counters.sv  —  Contadores de Rendimiento por Hardware
//
//  Acumula eventos pulsados por cache_ctrl y el pipeline, y los expone
//  como registros de 32 bits para lectura desde el testbench.
//
//  Métricas:
//    cycles          : ciclos totales desde reset
//    instr_retired   : instrucciones completadas (WB)
//    l1_reads        : lecturas hacia L1
//    l1_writes       : escrituras hacia L1
//    l1_read_hits    : hits de lectura en L1
//    l1_write_hits   : hits de escritura en L1
//    l1_read_misses  : fallos de lectura en L1
//    l1_write_misses : fallos de escritura en L1
//    l2_hits         : hits en L2
//    l2_misses       : fallos en L2
//    mem_accesses    : accesos a memoria principal (cada línea fetched/written)
//    stall_cycles    : ciclos perdidos por fallos de caché
//
//  Al finalizar (done=1) imprime un resumen en consola.
// =============================================================================

module perf_counters (
    input  logic clk,
    input  logic rst,

    // ── Eventos del pipeline ──────────────────────────────────────────────
    input  logic instr_retire,     // 1 ciclo cuando una instrucción completa WB
    input  logic mem_read_req,     // Solicitud de lectura (LOAD) a caché
    input  logic mem_write_req,    // Solicitud de escritura (STORE) a caché
    input  logic cache_stall,      // Pipeline detenido por caché

    // ── Eventos de la jerarquía de caché ──────────────────────────────────
    input  logic ev_l1_hit,        // Pulso: hit en L1
    input  logic ev_l1_miss,       // Pulso: fallo en L1
    input  logic ev_l2_hit,        // Pulso: hit en L2
    input  logic ev_l2_miss,       // Pulso: fallo en L2
    input  logic ev_mem_access,    // Pulso: acceso a memoria principal

    // ── Control ───────────────────────────────────────────────────────────
    input  logic done,             // 1 = fin de programa; imprime reporte

    // ── Salidas (registros de 32 bits) ────────────────────────────────────
    output logic [31:0] cycles,
    output logic [31:0] instr_retired,
    output logic [31:0] l1_reads,
    output logic [31:0] l1_writes,
    output logic [31:0] l1_read_hits,
    output logic [31:0] l1_write_hits,
    output logic [31:0] l1_read_misses,
    output logic [31:0] l1_write_misses,
    output logic [31:0] l2_hits,
    output logic [31:0] l2_misses,
    output logic [31:0] mem_accesses,
    output logic [31:0] stall_cycles
);

    // ── Contadores ────────────────────────────────────────────────────────
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            cycles          <= '0;
            instr_retired   <= '0;
            l1_reads        <= '0;
            l1_writes       <= '0;
            l1_read_hits    <= '0;
            l1_write_hits   <= '0;
            l1_read_misses  <= '0;
            l1_write_misses <= '0;
            l2_hits         <= '0;
            l2_misses       <= '0;
            mem_accesses    <= '0;
            stall_cycles    <= '0;
        end else begin
            cycles <= cycles + 1;

            if (instr_retire)   instr_retired   <= instr_retired + 1;
            if (cache_stall)    stall_cycles    <= stall_cycles  + 1;
            if (ev_mem_access)  mem_accesses    <= mem_accesses  + 1;
            if (ev_l2_hit)      l2_hits         <= l2_hits       + 1;
            if (ev_l2_miss)     l2_misses       <= l2_misses     + 1;

            // Separar hits/misses de L1 por tipo (read/write)
            if (mem_read_req) begin
                l1_reads <= l1_reads + 1;
                if (ev_l1_hit)  l1_read_hits   <= l1_read_hits  + 1;
                if (ev_l1_miss) l1_read_misses  <= l1_read_misses + 1;
            end
            if (mem_write_req) begin
                l1_writes <= l1_writes + 1;
                if (ev_l1_hit)  l1_write_hits   <= l1_write_hits  + 1;
                if (ev_l1_miss) l1_write_misses  <= l1_write_misses + 1;
            end
        end
    end

    // ── Reporte al finalizar ──────────────────────────────────────────────
    // Métricas derivadas calculadas con real para precisión
    real l1_hit_rate_r, l1_miss_rate_r;
    real l2_hit_rate_r, l2_miss_rate_r;
    real ipc_r;

    // Variables auxiliares de módulo para el reporte
    logic [31:0] total_l1_acc;
    logic [31:0] total_l1_hits_acc;
    logic [31:0] total_l1_misses_acc;
    logic [31:0] total_l2_acc;

    always_ff @(posedge clk) begin
        if (done) begin
            total_l1_acc        = l1_reads + l1_writes;
            total_l1_hits_acc   = l1_read_hits + l1_write_hits;
            total_l1_misses_acc = l1_read_misses + l1_write_misses;
            total_l2_acc        = l2_hits + l2_misses;

            l1_hit_rate_r  = (total_l1_acc  > 0) ? real'(total_l1_hits_acc)   / real'(total_l1_acc)  : 0.0;
            l1_miss_rate_r = (total_l1_acc  > 0) ? real'(total_l1_misses_acc) / real'(total_l1_acc)  : 0.0;
            l2_hit_rate_r  = (total_l2_acc  > 0) ? real'(l2_hits)   / real'(total_l2_acc) : 0.0;
            l2_miss_rate_r = (total_l2_acc  > 0) ? real'(l2_misses) / real'(total_l2_acc) : 0.0;
            ipc_r          = (cycles > 0)         ? real'(instr_retired) / real'(cycles) : 0.0;

            $display("========================================");
            $display("  PERFORMANCE COUNTERS REPORT");
            $display("========================================");
            $display("  Cycles total        : %0d", cycles);
            $display("  Instructions retired: %0d", instr_retired);
            $display("  IPC                 : %.4f", ipc_r);
            $display("  Stall cycles (cache): %0d", stall_cycles);
            $display("----------------------------------------");
            $display("  L1 Reads            : %0d", l1_reads);
            $display("  L1 Writes           : %0d", l1_writes);
            $display("  L1 Read  Hits       : %0d", l1_read_hits);
            $display("  L1 Write Hits       : %0d", l1_write_hits);
            $display("  L1 Read  Misses     : %0d", l1_read_misses);
            $display("  L1 Write Misses     : %0d", l1_write_misses);
            $display("  L1 Hit  Rate        : %.4f", l1_hit_rate_r);
            $display("  L1 Miss Rate        : %.4f", l1_miss_rate_r);
            $display("----------------------------------------");
            $display("  L2 Hits             : %0d", l2_hits);
            $display("  L2 Misses           : %0d", l2_misses);
            $display("  L2 Hit  Rate        : %.4f", l2_hit_rate_r);
            $display("  L2 Miss Rate        : %.4f", l2_miss_rate_r);
            $display("----------------------------------------");
            $display("  Main Mem Accesses   : %0d", mem_accesses);
            $display("========================================");
        end
    end

endmodule
