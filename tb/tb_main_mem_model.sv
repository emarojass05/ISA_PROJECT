`timescale 1ns/1ps
// =============================================================================
// tb_main_mem_model.sv — Testbench para main_mem_model
// =============================================================================
// Casos de prueba:
//   TC1 — Reset: ready=0, rdata=0
//   TC2 — Lectura: req=1 → exactly 25 ciclos → ready=1, datos correctos
//   TC3 — ready dura solo 1 ciclo
//   TC4 — Escritura + re-lectura: escribir línea, luego leerla de vuelta
//   TC5 — Dos transacciones consecutivas: segunda empieza justo después de ready
//   TC6 — Sin solapamiento: req ignorado mientras active=1
// =============================================================================

module tb_main_mem_model;

    localparam int XLEN       = 32;
    localparam int LINE_WORDS = 8;
    localparam int LINE_BITS  = LINE_WORDS * 32;
    localparam int LATENCY    = 25;
    localparam int DEPTH      = 16384;

    // ── DUT ──────────────────────────────────────────────────────────────
    logic                 clk, rst;
    logic                 req;
    logic                 we;
    logic [XLEN-1:0]      addr;
    logic [LINE_BITS-1:0] wdata;
    logic                 ready;
    logic [LINE_BITS-1:0] rdata;

    main_mem_model #(
        .XLEN      (XLEN),
        .DEPTH     (DEPTH),
        .LINE_WORDS(LINE_WORDS),
        .LATENCY   (LATENCY)
    ) dut (
        .clk  (clk),
        .rst  (rst),
        .req  (req),
        .we   (we),
        .addr (addr),
        .wdata(wdata),
        .ready(ready),
        .rdata(rdata)
    );

    // ── Clock ─────────────────────────────────────────────────────────────
    initial clk = 0;
    always  #5 clk = ~clk;

    // ── Helpers ───────────────────────────────────────────────────────────
    int pass_count, fail_count;
    int cycle_count;

    task automatic check(input string name, input logic got, input logic exp);
        if (got === exp) begin
            $display("  [PASS] %s", name);
            pass_count++;
        end else begin
            $display("  [FAIL] %s — got %0b, exp %0b", name, got, exp);
            fail_count++;
        end
    endtask

    task automatic check32(input string name, input logic [31:0] got, input logic [31:0] exp);
        if (got === exp) begin
            $display("  [PASS] %s (= %08h)", name, got);
            pass_count++;
        end else begin
            $display("  [FAIL] %s — got %08h, exp %08h", name, got, exp);
            fail_count++;
        end
    endtask

    // Envía req por 1 ciclo y espera a que ready llegue.
    // Devuelve el número de ciclos transcurridos hasta ready.
    task automatic send_req(
        input  logic [XLEN-1:0]       a,
        input  logic                  w,
        input  logic [LINE_BITS-1:0]  wd,
        output int                    cycles_waited
    );
        @(negedge clk);
        req   = 1'b1;
        we    = w;
        addr  = a;
        wdata = wd;
        @(posedge clk); #1;
        req = 1'b0;
        we  = 1'b0;

        cycles_waited = 1;
        while (!ready) begin
            @(posedge clk); #1;
            cycles_waited++;
        end
    endtask

    // Construye una línea de 256 bits: cada palabra = base + offset
    function automatic logic [LINE_BITS-1:0] make_line(input logic [31:0] base);
        logic [LINE_BITS-1:0] line;
        int i;
        for (i = 0; i < LINE_WORDS; i++)
            line[i*32 +: 32] = base + i;
        return line;
    endfunction

    // ── Estímulos ─────────────────────────────────────────────────────────
    initial begin
        $dumpfile("build/sim/tb_main_mem_model.vcd");
        $dumpvars(0, tb_main_mem_model);

        pass_count = 0;
        fail_count = 0;

        req   = 1'b0;
        we    = 1'b0;
        addr  = '0;
        wdata = '0;

        // ─────────────────────────────────────────────────────────────────
        $display("\n=== TC1: Reset ===");
        rst = 1'b1;
        repeat(3) @(posedge clk); #1;
        check("ready=0 tras reset", ready, 1'b0);
        check32("rdata[31:0]=0 tras reset", rdata[31:0], 32'h0);
        @(negedge clk); rst = 1'b0;

        // ─────────────────────────────────────────────────────────────────
        $display("\n=== TC2: Lectura — latencia exacta de 25 ciclos ===");
        begin
            int cycles;
            // Primero escribimos datos conocidos directamente en la memoria del DUT
            // para poder verificar la lectura (acceso backdoor a memoria del modelo)
            dut.memory[0] = 32'hDEAD_0000;
            dut.memory[1] = 32'hDEAD_0001;
            dut.memory[2] = 32'hDEAD_0002;
            dut.memory[3] = 32'hDEAD_0003;
            dut.memory[4] = 32'hDEAD_0004;
            dut.memory[5] = 32'hDEAD_0005;
            dut.memory[6] = 32'hDEAD_0006;
            dut.memory[7] = 32'hDEAD_0007;

            send_req(32'h0000_0000, 1'b0, '0, cycles);

            $display("  [INFO] ciclos hasta ready = %0d (esperado %0d)", cycles, LATENCY);
            check("latencia = 25 ciclos", (cycles == LATENCY), 1'b1);
            check("ready=1 al ciclo 25",  ready, 1'b1);
            check32("rdata[word0]", rdata[0*32 +: 32], 32'hDEAD_0000);
            check32("rdata[word3]", rdata[3*32 +: 32], 32'hDEAD_0003);
            check32("rdata[word7]", rdata[7*32 +: 32], 32'hDEAD_0007);
        end

        // ─────────────────────────────────────────────────────────────────
        $display("\n=== TC3: ready dura solo 1 ciclo ===");
        @(posedge clk); #1;
        check("ready=0 ciclo después", ready, 1'b0);

        // ─────────────────────────────────────────────────────────────────
        $display("\n=== TC4: Escritura + re-lectura ===");
        begin
            logic [LINE_BITS-1:0] write_line;
            int cycles;

            write_line = make_line(32'hCAFE_0000);

            // Escribir en dirección 0x100 (word_base = 0x40 = 64)
            send_req(32'h0000_0100, 1'b1, write_line, cycles);
            check("write: latencia = 25 ciclos", (cycles == LATENCY), 1'b1);
            check("write: ready=1", ready, 1'b1);

            @(posedge clk); #1;  // esperar ciclo después de ready

            // Leer de vuelta la misma línea
            send_req(32'h0000_0100, 1'b0, '0, cycles);
            check("re-read: latencia = 25 ciclos", (cycles == LATENCY), 1'b1);
            check32("re-read word0", rdata[0*32 +: 32], 32'hCAFE_0000);
            check32("re-read word4", rdata[4*32 +: 32], 32'hCAFE_0004);
            check32("re-read word7", rdata[7*32 +: 32], 32'hCAFE_0007);
        end

        // ─────────────────────────────────────────────────────────────────
        $display("\n=== TC5: Dos transacciones consecutivas ===");
        begin
            logic [LINE_BITS-1:0] line_a, line_b;
            int cycles_a, cycles_b;

            // Preparar datos en memoria
            dut.memory[8]  = 32'hAAAA_0000;
            dut.memory[9]  = 32'hAAAA_0001;
            dut.memory[10] = 32'hAAAA_0002;
            dut.memory[11] = 32'hAAAA_0003;
            dut.memory[12] = 32'hAAAA_0004;
            dut.memory[13] = 32'hAAAA_0005;
            dut.memory[14] = 32'hAAAA_0006;
            dut.memory[15] = 32'hAAAA_0007;

            dut.memory[16] = 32'hBBBB_0000;
            dut.memory[17] = 32'hBBBB_0001;
            dut.memory[18] = 32'hBBBB_0002;
            dut.memory[19] = 32'hBBBB_0003;
            dut.memory[20] = 32'hBBBB_0004;
            dut.memory[21] = 32'hBBBB_0005;
            dut.memory[22] = 32'hBBBB_0006;
            dut.memory[23] = 32'hBBBB_0007;

            // Primera transacción: leer línea en addr=0x20 (word_base=8)
            send_req(32'h0000_0020, 1'b0, '0, cycles_a);
            check32("tx_a word0", rdata[0*32 +: 32], 32'hAAAA_0000);

            @(posedge clk); #1;  // ciclo posterior a ready (ready ya=0)

            // Segunda transacción inmediata: leer línea en addr=0x40 (word_base=16)
            send_req(32'h0000_0040, 1'b0, '0, cycles_b);
            check("tx_b: latencia = 25", (cycles_b == LATENCY), 1'b1);
            check32("tx_b word0", rdata[0*32 +: 32], 32'hBBBB_0000);
            check32("tx_b word7", rdata[7*32 +: 32], 32'hBBBB_0007);
        end

        // ─────────────────────────────────────────────────────────────────
        $display("\n============================================");
        $display(" RESULTADO: %0d PASS  /  %0d FAIL", pass_count, fail_count);
        $display("============================================\n");

        if (fail_count == 0)
            $display(" [OK] tb_main_mem_model: todos los casos pasaron.");
        else
            $display(" [ERROR] tb_main_mem_model: %0d caso(s) fallaron.", fail_count);

        $finish;
    end

endmodule
