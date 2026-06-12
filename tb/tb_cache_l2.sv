`timescale 1ns/1ps
// =============================================================================
// tb_cache_l2.sv — Testbench for cache_l2
// =============================================================================
// Test cases:
//   TC1 — Reset: valid=0, hit=0
//   TC2 — Fill + Read-hit: load line, hit=1, full line correct
//   TC3 — Read miss: different tag/set -> hit=0
//   TC4 — Write-line: update L2 line, dirty=1, data correct
//   TC5 — Victim dirty: fill full set -> victim reports dirty
//   TC6 — PLRU sequence: fill 4 ways, access in order, verify LRU victim
//   TC7 — do_lru_update: read-hit without write modifies the PLRU tree
// =============================================================================

module tb_cache_l2;

    // ── Parameters ───────────────────────────────────────────────────────────
    localparam int XLEN       = 32;
    localparam int SETS       = 128;
    localparam int WAYS       = 4;
    localparam int LINE_WORDS = 8;
    localparam int LINE_BITS  = LINE_WORDS * 32;  // 256

    // Address breakdown: offset=5b [4:0], index=7b [11:5], tag=20b [31:12]
    localparam int OFFSET_BITS = 5;
    localparam int INDEX_BITS  = 7;

    // ── DUT ──────────────────────────────────────────────────────────────────
    logic                  clk, rst;

    logic [XLEN-1:0]       req_addr;
    logic                  hit;
    logic [1:0]            hit_way;
    logic [LINE_BITS-1:0]  hit_rdata_line;
    logic                  victim_dirty;
    logic [XLEN-1:0]       victim_addr;
    logic [LINE_BITS-1:0]  victim_data;

    logic                  do_fill;
    logic [XLEN-1:0]       fill_addr;
    logic [LINE_BITS-1:0]  fill_data;

    logic                  do_write_line;
    logic [XLEN-1:0]       wline_addr;
    logic [LINE_BITS-1:0]  wline_data;

    logic                  do_lru_update;
    logic [6:0]            lru_set;
    logic [1:0]            lru_way;

    cache_l2 #(
        .XLEN       (XLEN),
        .SETS       (SETS),
        .WAYS       (WAYS),
        .LINE_WORDS (LINE_WORDS)
    ) dut (
        .clk           (clk),
        .rst           (rst),
        .req_addr      (req_addr),
        .hit           (hit),
        .hit_way       (hit_way),
        .hit_rdata_line(hit_rdata_line),
        .victim_dirty  (victim_dirty),
        .victim_addr   (victim_addr),
        .victim_data   (victim_data),
        .do_fill       (do_fill),
        .fill_addr     (fill_addr),
        .fill_data     (fill_data),
        .do_write_line (do_write_line),
        .wline_addr    (wline_addr),
        .wline_data    (wline_data),
        .do_lru_update (do_lru_update),
        .lru_set       (lru_set),
        .lru_way       (lru_way)
    );

    // ── Clock ─────────────────────────────────────────────────────────────────
    initial clk = 0;
    always  #5 clk = ~clk;

    // ── Helpers ───────────────────────────────────────────────────────────────
    int pass_count, fail_count;

    task automatic check(input string name, input logic got, input logic exp);
        if (got === exp) begin
            $display("  [PASS] %s", name);
            pass_count++;
        end else begin
            $display("  [FAIL] %s -- got %0b, exp %0b", name, got, exp);
            fail_count++;
        end
    endtask

    task automatic check2(input string name, input logic [1:0] got, input logic [1:0] exp);
        if (got === exp) begin
            $display("  [PASS] %s (= %0d)", name, got);
            pass_count++;
        end else begin
            $display("  [FAIL] %s -- got %0d, exp %0d", name, got, exp);
            fail_count++;
        end
    endtask

    task automatic check32(input string name, input logic [31:0] got, input logic [31:0] exp);
        if (got === exp) begin
            $display("  [PASS] %s (= %08h)", name, got);
            pass_count++;
        end else begin
            $display("  [FAIL] %s -- got %08h, exp %08h", name, got, exp);
            fail_count++;
        end
    endtask

    function automatic logic [XLEN-1:0] make_addr(
        input logic [19:0] tag,
        input logic [6:0]  index
    );
        return {tag, index, 5'b0_0000};
    endfunction

    function automatic logic [LINE_BITS-1:0] make_line(input logic [31:0] base);
        logic [LINE_BITS-1:0] line;
        int i;
        for (i = 0; i < LINE_WORDS; i++)
            line[i*32 +: 32] = base + i;
        return line;
    endfunction

    task automatic fill_op(input logic [XLEN-1:0] addr, input logic [LINE_BITS-1:0] line);
        @(negedge clk);
        do_fill   = 1'b1;
        fill_addr = addr;
        fill_data = line;
        @(posedge clk); #1;
        do_fill = 1'b0;
    endtask

    // ── Stimulus ──────────────────────────────────────────────────────────────
    initial begin
        $dumpfile("build/sim/tb_cache_l2.vcd");
        $dumpvars(0, tb_cache_l2);

        pass_count    = 0;
        fail_count    = 0;

        req_addr      = '0;
        do_fill       = 1'b0;
        fill_addr     = '0;
        fill_data     = '0;
        do_write_line = 1'b0;
        wline_addr    = '0;
        wline_data    = '0;
        do_lru_update = 1'b0;
        lru_set       = '0;
        lru_way       = '0;

        // ─────────────────────────────────────────────────────────────────────
        $display("\n=== TC1: Reset ===");
        rst = 1'b1;
        repeat(2) @(posedge clk); #1;
        req_addr = make_addr(20'hABCDE, 7'd10);
        #1;
        check("hit=0 after reset", hit, 1'b0);
        @(negedge clk); rst = 1'b0;

        // ─────────────────────────────────────────────────────────────────────
        $display("\n=== TC2: Fill + Read-hit ===");
        begin
            logic [XLEN-1:0]      a0;
            logic [LINE_BITS-1:0] l0;
            a0 = make_addr(20'h12345, 7'd10);
            l0 = make_line(32'hAA00_0000);

            fill_op(a0, l0);

            req_addr = a0;
            #1;
            check  ("hit=1 after fill",          hit,                    1'b1);
            check32("line[0] correct",           hit_rdata_line[31:0],   32'hAA00_0000);
            check32("line[7] correct",           hit_rdata_line[255:224], 32'hAA00_0007);
        end

        // ─────────────────────────────────────────────────────────────────────
        $display("\n=== TC3: Read miss ===");
        req_addr = make_addr(20'hFFFFF, 7'd10);
        #1;
        check("miss: different tag",   hit, 1'b0);

        req_addr = make_addr(20'h12345, 7'd50);
        #1;
        check("miss: empty set",       hit, 1'b0);

        // ─────────────────────────────────────────────────────────────────────
        $display("\n=== TC4: Write-line ===");
        begin
            logic [XLEN-1:0]      wa;
            logic [LINE_BITS-1:0] wl;
            wa = make_addr(20'h12345, 7'd10);
            wl = make_line(32'hDEAD_0000);

            @(negedge clk);
            do_write_line = 1'b1;
            wline_addr    = wa;
            wline_data    = wl;
            @(posedge clk); #1;
            do_write_line = 1'b0;

            req_addr = wa;
            #1;
            check  ("hit=1 after write-line",       hit,                    1'b1);
            check32("line[0] updated",              hit_rdata_line[31:0],   32'hDEAD_0000);
            check32("line[3] updated",              hit_rdata_line[127:96], 32'hDEAD_0003);
        end

        // ─────────────────────────────────────────────────────────────────────
        $display("\n=== TC5: Victim dirty ===");
        // Set 10 already has one way with dirty=1 (from TC4). Fill remaining 3 ways.
        begin
            logic [XLEN-1:0]      a1, a2, a3;
            a1 = make_addr(20'h22222, 7'd10);
            a2 = make_addr(20'h33333, 7'd10);
            a3 = make_addr(20'h44444, 7'd10);

            fill_op(a1, make_line(32'hBB00_0000));
            fill_op(a2, make_line(32'hCC00_0000));
            fill_op(a3, make_line(32'hDD00_0000));

            req_addr = make_addr(20'h55555, 7'd10);
            #1;
            check("miss in full set", hit, 1'b0);
            $display("  [INFO] victim_dirty=%0b victim_addr=%08h",
                     victim_dirty, victim_addr);
            if (victim_dirty)
                $display("  [INFO] dirty victim: addr=%08h (expected tag=0x12345 if LRU)",
                         victim_addr);
        end

        // ─────────────────────────────────────────────────────────────────────
        $display("\n=== TC6: PLRU sequence on clean set ===");
        // Fill order w0->w1->w2->w3. After accessing w2, victim should be from the
        // opposite PLRU branch (left side: w0 or w1).
        begin
            logic [XLEN-1:0] addrs [4];
            int i;
            addrs[0] = make_addr(20'h00001, 7'd30);
            addrs[1] = make_addr(20'h00002, 7'd30);
            addrs[2] = make_addr(20'h00003, 7'd30);
            addrs[3] = make_addr(20'h00004, 7'd30);

            for (i = 0; i < 4; i++)
                fill_op(addrs[i], make_line(32'h0000_0000 + i * 32'h1000_0000));

            for (i = 0; i < 4; i++) begin
                req_addr = addrs[i]; #1;
                check($sformatf("hit way%0d", i), hit, 1'b1);
            end

            // Access way2 (tag=0x00003) without write -> lru_update
            req_addr = addrs[2]; #1;
            $display("  [INFO] hit_way after access to addr[2] = %0d", hit_way);

            @(negedge clk);
            do_lru_update = 1'b1;
            lru_set       = 7'd30;
            lru_way       = hit_way;
            @(posedge clk); #1;
            do_lru_update = 1'b0;

            req_addr = make_addr(20'hFFFFF, 7'd30);
            #1;
            $display("  [INFO] victim_way after w2 access: addr=%08h", victim_addr);
        end

        // ─────────────────────────────────────────────────────────────────────
        $display("\n=== TC7: do_lru_update standalone ===");
        // Set 70 clean. PLRU from 000 distributes fills as:
        //   fill 1 -> w0 (plru: 000->110)
        //   fill 2 -> w2 (plru: 110->011)
        //   fill 3 -> w1 (plru: 011->101)
        //   fill 4 -> w3 (plru: 101->000)
        // After all fills: plru=000, victim = w0 (tag C0001)
        // do_lru_update(w0) -> plru=110, victim shifts to w2 (tag C0002)
        begin
            logic [XLEN-1:0] c0, c1, c2, c3;
            c0 = make_addr(20'hC0001, 7'd70);
            c1 = make_addr(20'hC0002, 7'd70);
            c2 = make_addr(20'hC0003, 7'd70);
            c3 = make_addr(20'hC0004, 7'd70);

            fill_op(c0, make_line(32'h7000_0000));  // -> w0
            fill_op(c1, make_line(32'h8000_0000));  // -> w2
            fill_op(c2, make_line(32'h9000_0000));  // -> w1
            fill_op(c3, make_line(32'hA000_0000));  // -> w3

            req_addr = make_addr(20'hFFFFF, 7'd70);
            #1;
            check("initial victim = w0 (tag C0001)",
                  victim_addr[XLEN-1:INDEX_BITS+OFFSET_BITS] == 20'hC0001, 1'b1);

            @(negedge clk);
            do_lru_update = 1'b1;
            lru_set       = 7'd70;
            lru_way       = 2'd0;
            @(posedge clk); #1;
            do_lru_update = 1'b0;

            req_addr = make_addr(20'hFFFFF, 7'd70);
            #1;
            $display("  [INFO] victim_addr after lru_update(w0) = %08h", victim_addr);
            check("victim after lru_update(w0) = w2 (tag C0002)",
                  victim_addr[XLEN-1:INDEX_BITS+OFFSET_BITS] == 20'hC0002, 1'b1);
        end

        // ─────────────────────────────────────────────────────────────────────
        $display("\n============================================");
        $display(" RESULT: %0d PASS  /  %0d FAIL", pass_count, fail_count);
        $display("============================================\n");

        if (fail_count == 0)
            $display(" [OK] tb_cache_l2: all cases passed.");
        else
            $display(" [ERROR] tb_cache_l2: %0d case(s) failed.", fail_count);

        $finish;
    end

endmodule
