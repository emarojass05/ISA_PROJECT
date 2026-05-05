`timescale 1ns/1ps

module tb_key_vault;

    parameter int XLEN = 32;
    parameter int KEYS = 4;
    parameter int WORDS_PER_KEY = 4;

    logic            clk;
    logic            vault_we;
    logic            auth_en;
    logic [3:0]      addr;
    logic [XLEN-1:0] wdata;
    logic [XLEN-1:0] k_out;

    int errors = 0;

    // DUT
    key_vault #(
        .XLEN(XLEN),
        .KEYS(KEYS),
        .WORDS_PER_KEY(WORDS_PER_KEY)
    ) dut (
        .clk(clk),
        .vault_we(vault_we),
        .auth_en(auth_en),
        .addr(addr),
        .wdata(wdata),
        .k_out(k_out)
    );

    // Clock: 10ns period
    initial clk = 0;
    always #5 clk = ~clk;

    // Helper task: try to write, then read back to verify
    task automatic write_word(input logic [3:0] a, input logic [XLEN-1:0] data);
        @(negedge clk);
        addr     = a;
        wdata    = data;
        vault_we = 1'b1;
        @(posedge clk);
        @(negedge clk);
        vault_we = 1'b0;
    endtask

    task automatic check_read(
        input string label,
        input logic  auth,
        input logic [3:0] a,
        input logic [XLEN-1:0] expected
    );
        @(negedge clk);
        auth_en = auth;
        addr    = a;
        #1;
        if (k_out === expected) begin
            $display("PASS %-40s addr=%h auth=%b k_out=%h", label, a, auth, k_out);
        end else begin
            $display("FAIL %-40s addr=%h auth=%b k_out=%h (expected %h)",
                     label, a, auth, k_out, expected);
            errors++;
        end
    endtask

    initial begin
        // Default values
        addr     = 4'h0;
        wdata    = 32'h0;
        vault_we = 1'b0;
        auth_en  = 1'b0;

        @(posedge clk);

        // ---------- TEST 1: estado inicial (todo en 0) ----------
        check_read("initial state addr=0 (auth on)",   1'b1, 4'h0, 32'h0);
        check_read("initial state addr=15 (auth on)",  1'b1, 4'hF, 32'h0);

        // ---------- TEST 2: lectura sin auth devuelve 0 ----------
        check_read("read with auth_en=0",              1'b0, 4'h0, 32'h0);

        // ---------- TEST 3: write sin auth NO debe escribir ----------
        auth_en = 1'b0;
        write_word(4'h0, 32'hDEADBEEF);
        check_read("write blocked when auth_en=0",     1'b1, 4'h0, 32'h0);

        // ---------- TEST 4: write con auth, read con auth ----------
        auth_en = 1'b1;
        write_word(4'h0, 32'hAAAA1111);
        check_read("write/read addr=0 auth=1",         1'b1, 4'h0, 32'hAAAA1111);

        // ---------- TEST 5: leer la misma celda sin auth da 0 ----------
        check_read("locked read after authorized write", 1'b0, 4'h0, 32'h0);

        // ---------- TEST 6: escribir las 4 llaves x 4 words ----------
        auth_en = 1'b1;
        write_word(4'h1, 32'h11111111);
        write_word(4'h2, 32'h22222222);
        write_word(4'h3, 32'h33333333);
        write_word(4'h4, 32'h44444444);
        write_word(4'h8, 32'h88888888);
        write_word(4'hC, 32'hCCCCCCCC);
        write_word(4'hF, 32'hFFFFFFFF);

        check_read("read addr=1",                       1'b1, 4'h1, 32'h11111111);
        check_read("read addr=2",                       1'b1, 4'h2, 32'h22222222);
        check_read("read addr=3",                       1'b1, 4'h3, 32'h33333333);
        check_read("read addr=4 (key1 word0)",          1'b1, 4'h4, 32'h44444444);
        check_read("read addr=8 (key2 word0)",          1'b1, 4'h8, 32'h88888888);
        check_read("read addr=12 (key3 word0)",         1'b1, 4'hC, 32'hCCCCCCCC);
        check_read("read addr=15 (last word)",          1'b1, 4'hF, 32'hFFFFFFFF);

        // ---------- TEST 7: lockdown - des-autenticarse y verificar bloqueo ----------
        check_read("lockdown after unauth: addr=1",     1'b0, 4'h1, 32'h0);
        check_read("lockdown after unauth: addr=15",    1'b0, 4'hF, 32'h0);

        $display("");
        if (errors == 0) begin
            $display("KEY VAULT TEST PASSED");
        end else begin
            $display("KEY VAULT TEST FAILED — %0d errors", errors);
        end

        $finish;
    end

endmodule