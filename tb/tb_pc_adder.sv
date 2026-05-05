`timescale 1ns/1ps

module tb_pc_adder;

    localparam int XLEN = 32;

    logic [XLEN-1:0] pc;
    logic [XLEN-1:0] imm;
    logic [XLEN-1:0] next_pc;
    logic [XLEN-1:0] pc_imm;

    int errors;

    pc_adder #(
        .XLEN(XLEN)
    ) dut (
        .pc(pc),
        .imm(imm),
        .next_pc(next_pc),
        .pc_imm(pc_imm)
    );

    task automatic check_pc_adder(
        input logic [XLEN-1:0] test_pc,
        input logic [XLEN-1:0] test_imm,
        input logic [XLEN-1:0] expected_next_pc,
        input logic [XLEN-1:0] expected_pc_imm,
        input string           test_name
    );
        begin
            pc  = test_pc;
            imm = test_imm;
            #1;

            if (next_pc !== expected_next_pc) begin
                $display("FAIL %-24s next_pc=%h expected=%h", test_name, next_pc, expected_next_pc);
                errors++;
            end

            if (pc_imm !== expected_pc_imm) begin
                $display("FAIL %-24s pc_imm=%h expected=%h", test_name, pc_imm, expected_pc_imm);
                errors++;
            end

            if (next_pc === expected_next_pc && pc_imm === expected_pc_imm) begin
                $display("PASS %-24s next_pc=%h pc_imm=%h", test_name, next_pc, pc_imm);
            end
        end
    endtask

    initial begin
        errors = 0;

        check_pc_adder(
            32'h0000_0000,
            32'h0000_0008,
            32'h0000_0004,
            32'h0000_0008,
            "pc zero positive imm"
        );

        check_pc_adder(
            32'h0000_0004,
            32'h0000_000C,
            32'h0000_0008,
            32'h0000_0010,
            "pc 4 positive imm"
        );

        check_pc_adder(
            32'h0000_0010,
            32'hFFFF_FFFC,
            32'h0000_0014,
            32'h0000_000C,
            "negative imm"
        );

        check_pc_adder(
            32'hFFFF_FFFC,
            32'h0000_0004,
            32'h0000_0000,
            32'h0000_0000,
            "wraparound"
        );

        if (errors == 0) begin
            $display("PC ADDER TEST PASSED");
        end else begin
            $display("PC ADDER TEST FAILED: %0d error(s)", errors);
        end

        $finish;
    end

endmodule