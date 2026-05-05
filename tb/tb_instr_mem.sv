`timescale 1ns/1ps

module tb_instr_mem;

    localparam int XLEN  = 32;
    localparam int DEPTH = 16;

    logic [XLEN-1:0] pc;
    logic [31:0]     instruction;

    int errors;

    instr_mem #(
        .XLEN(XLEN),
        .DEPTH(DEPTH),
        .PROGRAM_FILE("programs/hex/test_instr_mem.hex")
    ) dut (
        .pc(pc),
        .instruction(instruction)
    );

    task automatic check_instruction(
        input logic [XLEN-1:0] test_pc,
        input logic [31:0]     expected_instruction,
        input string           test_name
    );
        begin
            pc = test_pc;
            #1;

            if (instruction !== expected_instruction) begin
                $display("FAIL %-24s pc=%h instruction=%h expected=%h",
                         test_name, pc, instruction, expected_instruction);
                errors++;
            end else begin
                $display("PASS %-24s pc=%h instruction=%h",
                         test_name, pc, instruction);
            end
        end
    endtask

    initial begin
        errors = 0;
        pc = '0;

        #1;

        check_instruction(32'h0000_0000, 32'h1111_1111, "read word 0");
        check_instruction(32'h0000_0004, 32'h2222_2222, "read word 1");
        check_instruction(32'h0000_0008, 32'h3333_3333, "read word 2");
        check_instruction(32'h0000_000C, 32'h4444_4444, "read word 3");

        if (errors == 0) begin
            $display("INSTR MEM TEST PASSED");
        end else begin
            $display("INSTR MEM TEST FAILED: %0d error(s)", errors);
        end

        $finish;
    end

endmodule