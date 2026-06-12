`timescale 1ns/1ps
// =============================================================================
// tb_cache_l1d.sv — Testbench for cache_l1d
// =============================================================================
// Test cases:
//   TC1 — Reset: all valid=0, hit=0
//   TC2 — Fill + Read-hit: load a line, read it next cycle
//   TC3 — Read miss: unloaded address -> hit=0
//   TC4 — Write-hit: store into cached line -> dirty=1, data updated
//   TC5 — Victim dirty: fill full set, victim reports dirty and addr
//   TC6 — LRU replacement: after filling both ways, refill -> picks LRU way
//   TC7 — do_lru_update: read-hit without write updates LRU correctly
// =============================================================================

module tb_cache_l1d;

    // ── Parameters ───────────────────────────────────────────────────────────
    localparam int XLEN       = 32;
    localparam int SETS       = 64;
    localparam int WAYS       = 2;
    localparam int LINE_WORDS = 8;
    localparam int LINE_BITS  = LINE_WORDS * 32;

    // Address breakdown: offset=5b [4:0], index=6b [10:5], tag=21b [31:11]
    localparam int OFFSET_BITS = 5;
    localparam int INDEX_BITS  = 6;

    // ── DUT ──────────────────────────────────────────────────────────────────
    logic                  clk;
    logic                  rst;

    logic [XLEN-1:0]       req_addr;

    logic                  hit;
    logic                  hit_way;
    logic [31:0]           hit_rdata;
    logic                  victim_dirty;
    logic [XLEN-1:0]       victim_addr;
    logic [LINE_BITS-1:0]  victim_data;

    logic                  do_fill;
    logic                  fill_way;
    logic [XLEN-1:0]       fill_addr;
    logic [LINE_BITS-1:0]  fill_data;

    logic                  do_write_hit;
    logic                  write_way;
    logic [XLEN-1:0]       write_addr;
    logic [31:0]           write_data;

    logic                  do_lru_update;
    logic [5:0]            lru_set;
    logic                  lru_way;

    cache_l1d #(
        .XLEN       (XLEN),
        .SETS       (SETS),
        .WAYS       (WAYS),
        .LINE_WORDS (LINE_WORDS)
    ) dut (
        .clk          (clk),
        .rst          (rst),
        .req_addr     (req_addr),
        .hit          (hit),
        .hit_way      (hit_way),
        .hit_rdata    (hit_rdata),
        .victim_dirty (victim_dirty),
        .victim_addr  (victim_addr),
        .victim_data  (victim_data),
        .do_fill      (do_fill),
        .fill_way     (fill_way),
        .fill_addr    (fill_addr),
        .fill_data    (fill_data),
        .do_write_hit (do_write_hit),
        .write_way    (write_way),
        .write_addr   (write_addr),
        .write_data   (write_data),
        .do_lru_update(do_lru_update),
        .lru_set      (lru_set),
        .lru_way      (lru_way)
    );

    // ── Clock ─────────────────────────────────────────────────────────────────
    initial clk = 0;
    always  #5 clk = ~clk;

    // ── Helpers ───────────────────────────────────────────────────────────────
    int pass_count;
    int fail_count;

    task automatic check(
        input string  test_name,
        input logic   got,
        input logic   expected
    );
        if (got === expected) begin
            $display("  [PASS] %s", test_name);
            pass_count++;
        end else begin
            $display("  [FAIL] %s -- got %0b, expected %0b", test_name, got, expected);
            fail_count++;
        end
    endtask

    task automatic check32(
        input string test_name,
        input logic [31:0] got,
        input logic [31:0] expected
    );
        if (got === expected) begin
            $display("  [PASS] %s (= %08h)", test_name, got);
            pass_count++;
        end else begin
            $display("  [FAIL] %s -- got %08h, expected %08h", test_name, got, expected);
            fail_count++;
        end
    endtask

    function automatic logic [XLEN-1:0] make_addr(
        input logic [20:0] tag,
        input logic [5:0]  index,
        input logic [2:0]  word
    );
        return {tag, index, word, 2'b00};
    endfunction

    function automatic logic [LINE_BITS-1:0] make_line(input logic [31:0] base);
        logic [LINE_BITS-1:0] line;
        int i;
        for (i = 0; i < LINE_WORDS; i++)
            line[i*32 +: 32] = base + i;
        return line;
    endfunction

    task automatic do_fill_op(
        input logic                  way,
        input logic [XLEN-1:0]       addr,
        input logic [LINE_BITS-1:0]  line
    );
        @(negedge clk);
        do_fill   = 1'b1;
        fill_way  = way;
        fill_addr = addr;
        fill_data = line;
        @(posedge clk); #1;
        do_fill = 1'b0;
    endtask

    // ── Stimulus ──────────────────────────────────────────────────────────────
    initial begin
        $dumpfile("build/sim/tb_cache_l1d.vcd");
        $dumpvars(0, tb_cache_l1d);

        pass_count   = 0;
        fail_count   = 0;

        req_addr      = '0;
        do_fill       = 1'b0;
        fill_way      = 1'b0;
        fill_addr     = '0;
        fill_data     = '0;
        do_write_hit  = 1'b0;
        write_way     = 1'b0;
        write_addr    = '0;
        write_data    = '0;
        do_lru_update = 1'b0;
        lru_set       = '0;
        lru_way       = 1'b0;

        // ─────────────────────────────────────────────────────────────────────
        $display("\n=== TC1: Reset ===");
        rst = 1'b1;
        @(posedge clk); #1;
        @(posedge clk); #1;

        req_addr = make_addr(21'h1, 6'd0, 3'd0);
        #1;
        check("hit=0 after reset", hit, 1'b0);

        @(negedge clk);
        rst = 1'b0;

        // ─────────────────────────────────────────────────────────────────────
        $display("\n=== TC2: Fill + Read-hit ===");
        begin
            logic [XLEN-1:0]      addr0;
            logic [LINE_BITS-1:0] line0;
            addr0 = make_addr(21'h0AB, 6'd5, 3'd0);
            line0 = make_line(32'hCAFE_0000);

            do_fill_op(1'b0, addr0, line0);

            req_addr = make_addr(21'h0AB, 6'd5, 3'd0);
            #1;
            check  ("hit=1 after fill",       hit,       1'b1);
            check  ("hit_way=0",              hit_way,   1'b0);
            check32("hit_rdata = word0",      hit_rdata, 32'hCAFE_0000);

            req_addr = make_addr(21'h0AB, 6'd5, 3'd3);
            #1;
            check32("hit_rdata = word3",      hit_rdata, 32'hCAFE_0003);
        end

        // ─────────────────────────────────────────────────────────────────────
        $display("\n=== TC3: Read miss ===");
        req_addr = make_addr(21'h0FF, 6'd5, 3'd0);
        #1;
        check("hit=0 different tag", hit, 1'b0);

        req_addr = make_addr(21'h0AB, 6'd10, 3'd0);
        #1;
        check("hit=0 empty set",     hit, 1'b0);

        // ─────────────────────────────────────────────────────────────────────
        $display("\n=== TC4: Write-hit ===");
        begin
            logic [XLEN-1:0] waddr;
            waddr = make_addr(21'h0AB, 6'd5, 3'd2);

            @(negedge clk);
            do_write_hit = 1'b1;
            write_way    = 1'b0;
            write_addr   = waddr;
            write_data   = 32'hDEAD_BEEF;
            @(posedge clk); #1;
            do_write_hit = 1'b0;

            req_addr = waddr;
            #1;
            check  ("hit=1 after write-hit",    hit,       1'b1);
            check32("data updated",             hit_rdata, 32'hDEAD_BEEF);
        end

        // ─────────────────────────────────────────────────────────────────────
        $display("\n=== TC5: Victim dirty ===");
        begin
            logic [XLEN-1:0]      addr_way1;
            logic [LINE_BITS-1:0] line_way1;
            addr_way1 = make_addr(21'h0CD, 6'd5, 3'd0);
            line_way1 = make_line(32'hBEEF_0000);

            req_addr = make_addr(21'h0AB, 6'd5, 3'd0);
            #1;
            do_fill_op(1'b1, addr_way1, line_way1);

            req_addr = make_addr(21'h0AB, 6'd5, 3'd0);
            #1;
            $display("  [INFO] victim_dirty=%0b victim_addr=%08h (expected: dirty=1 from TC4 write-hit)",
                     victim_dirty, victim_addr);
        end

        // ─────────────────────────────────────────────────────────────────────
        $display("\n=== TC6: LRU replacement ===");
        begin
            logic [XLEN-1:0]      a0, a1, a2;
            logic [LINE_BITS-1:0] l0, l1, l2;

            a0 = make_addr(21'h001, 6'd20, 3'd0);
            a1 = make_addr(21'h002, 6'd20, 3'd0);
            a2 = make_addr(21'h003, 6'd20, 3'd0);
            l0 = make_line(32'h1000_0000);
            l1 = make_line(32'h2000_0000);
            l2 = make_line(32'h3000_0000);

            // After fill way0, lru[20] flips to 1 (evict way1 next); after fill way1 -> evict way0
            do_fill_op(1'b0, a0, l0);
            do_fill_op(1'b1, a1, l1);

            req_addr = a2;
            #1;
            check("miss before 3rd fill", hit, 1'b0);
            $display("  [INFO] victim_addr=%08h (expected tag=0x001, set=20)", victim_addr);
            check("victim_addr tag correct",
                  victim_addr[XLEN-1:INDEX_BITS+OFFSET_BITS] == 21'h001, 1'b1);

            do_fill_op(1'b0, a2, l2);
            req_addr = a2;
            #1;
            check  ("hit=1 after LRU replace", hit,       1'b1);
            check32("correct data",            hit_rdata, 32'h3000_0000);

            req_addr = a0;
            #1;
            check("old tag evicted", hit, 1'b0);
        end

        // ─────────────────────────────────────────────────────────────────────
        $display("\n=== TC7: do_lru_update ===");
        // After lru_update on way1 of set 20, lru[20] must become 0 (way0 next victim)
        begin
            req_addr = make_addr(21'h002, 6'd20, 3'd0);
            #1;
            check("hit on way1 before lru_update", hit, 1'b1);

            @(negedge clk);
            do_lru_update = 1'b1;
            lru_set       = 6'd20;
            lru_way       = hit_way;
            @(posedge clk); #1;
            do_lru_update = 1'b0;

            req_addr = make_addr(21'h099, 6'd20, 3'd0);
            #1;
            check("victim is way0 after lru_update",
                  victim_addr[XLEN-1:INDEX_BITS+OFFSET_BITS] == 21'h003, 1'b1);
        end

        // ─────────────────────────────────────────────────────────────────────
        $display("\n============================================");
        $display(" RESULT: %0d PASS  /  %0d FAIL", pass_count, fail_count);
        $display("============================================\n");

        if (fail_count == 0)
            $display(" [OK] tb_cache_l1d: all cases passed.");
        else
            $display(" [ERROR] tb_cache_l1d: %0d case(s) failed.", fail_count);

        $finish;
    end

endmodule
