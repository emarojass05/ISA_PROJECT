`timescale 1ns/1ps

import isa_defs::*;

module tb_sec_alu;

    parameter int XLEN = 32;

    logic [XLEN-1:0] a;
    logic [XLEN-1:0] b;
    logic [XLEN-1:0] key;
    sec_op_t         sec_op;
    logic            auth_en;
    logic [XLEN-1:0] result;
    logic            exception;

    int errors = 0;

    sec_alu #(
        .XLEN(XLEN)
    ) dut (
        .a(a),
        .b(b),
        .key(key),
        .sec_op(sec_op),
        .auth_en(auth_en),
        .result(result),
        .exception(exception)
    );

    task automatic check(
        input string label,
        input logic [XLEN-1:0] expected
    );
        #1;
        if (result === expected) begin
            $display("PASS %-45s result=%h", label, result);
        end else begin
            $display("FAIL %-45s result=%h (expected %h)", label, result, expected);
            errors++;
        end
    endtask

    initial begin
        // Default
        a       = 32'h0;
        b       = 32'h0;
        key     = 32'h0;
        sec_op  = SEC_NONE;
        auth_en = 1'b0;

        // ---------- TEST 1: SEC_NONE always returns 0 ----------
        a = 32'hAAAAAAAA; b = 32'hBBBBBBBB; key = 32'hCCCCCCCC;
        sec_op = SEC_NONE; auth_en = 1'b0;
        check("SEC_NONE no auth",                      32'h0);

        sec_op = SEC_NONE; auth_en = 1'b1;
        check("SEC_NONE with auth",                    32'h0);

        // ---------- TEST 2: SEC_AUTH/SEC_LDK do not produce result ----------
        sec_op = SEC_AUTH; auth_en = 1'b1;
        check("SEC_AUTH produces no arithmetic result", 32'h0);

        sec_op = SEC_LDK; auth_en = 1'b1;
        check("SEC_LDK produces no arithmetic result",  32'h0);

        // ---------- TEST 3: SEC_ADDK without auth = locked ----------
        a = 32'h00000010; key = 32'h00000020;
        sec_op = SEC_ADDK; auth_en = 1'b0;
        check("SEC_ADDK locked when auth=0",            32'h0);

        // ---------- TEST 4: SEC_ADDK with auth = a + key ----------
        a = 32'h00000010; key = 32'h00000020;
        sec_op = SEC_ADDK; auth_en = 1'b1;
        check("SEC_ADDK 0x10 + 0x20",                   32'h00000030);

        a = 32'hFFFFFFF0; key = 32'h00000010;
        sec_op = SEC_ADDK; auth_en = 1'b1;
        check("SEC_ADDK overflow wrap",                 32'h00000000);

        // ---------- TEST 5: SEC_XORK with auth = a ^ key ----------
        a = 32'hAAAAAAAA; key = 32'h55555555;
        sec_op = SEC_XORK; auth_en = 1'b1;
        check("SEC_XORK 0xAAAA ^ 0x5555",               32'hFFFFFFFF);

        a = 32'hFFFFFFFF; key = 32'hFFFFFFFF;
        sec_op = SEC_XORK; auth_en = 1'b1;
        check("SEC_XORK all ones cancel",               32'h00000000);

        // ---------- TEST 6: SEC_XORK without auth = 0 ----------
        a = 32'hAAAAAAAA; key = 32'h55555555;
        sec_op = SEC_XORK; auth_en = 1'b0;
        check("SEC_XORK locked when auth=0",            32'h0);

        // ---------- TEST 7: Zero-attack defense (ADDK with a=0) ----------
        // Should return 0 instead of the key
        a = 32'h0; key = 32'hABCD1234;
        sec_op = SEC_ADDK; auth_en = 1'b1;
        check("SEC_ADDK a=0 (zero-attack blocked)",     32'h0);

        sec_op = SEC_XORK; auth_en = 1'b1;
        check("SEC_XORK a=0 (zero-attack blocked)",     32'h0);

        // ---------- TEST 8: SEC_TEA with auth ----------
        // result = ((a<<4) + key) ^ b ^ ((a>>5) + key)
        a = 32'h00000001; b = 32'h00000000; key = 32'h00000000;
        sec_op = SEC_TEA; auth_en = 1'b1;
        // ((1<<4)+0) ^ 0 ^ ((1>>5)+0) = 0x10 ^ 0 ^ 0 = 0x10
        check("SEC_TEA simple a=1 b=0 k=0",             32'h00000010);

        a = 32'h00000020; b = 32'h00000000; key = 32'h00000000;
        sec_op = SEC_TEA; auth_en = 1'b1;
        // ((0x20<<4)+0) ^ 0 ^ ((0x20>>5)+0) = 0x200 ^ 0 ^ 0x1 = 0x201
        check("SEC_TEA a=0x20 b=0 k=0",                 32'h00000201);

        // ---------- TEST 9: SEC_TEA without auth = 0 ----------
        sec_op = SEC_TEA; auth_en = 1'b0;
        check("SEC_TEA locked when auth=0",             32'h0);

        $display("");
        if (errors == 0) begin
            $display("SEC ALU TEST PASSED");
        end else begin
            $display("SEC ALU TEST FAILED — %0d errors", errors);
        end

        $finish;
    end

endmodule