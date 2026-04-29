`timescale 1ns/1ps

module tb_cpu_program;

    parameter int XLEN       = 32;
    parameter int IMEM_DEPTH = 65536;
    parameter int DMEM_DEPTH = 65536;

    parameter PROGRAM_FILE = "programs/hex/program.hex";
    parameter INITIAL_MEM  = "";

    parameter int MAX_CYCLES = 200;

    logic clk;
    logic rst;

    int cycle_count;

    cpu_top #(
        .XLEN(XLEN),
        .IMEM_DEPTH(IMEM_DEPTH),
        .DMEM_DEPTH(DMEM_DEPTH),
        .PROGRAM_FILE(PROGRAM_FILE),
        .INITIAL_MEM(INITIAL_MEM)
    ) dut (
        .clk(clk),
        .rst(rst)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        $display("CPU PROGRAM TEST START");
        $display("PROGRAM_FILE = %s", PROGRAM_FILE);
        $display("INITIAL_MEM  = %s", INITIAL_MEM);
        $display("MAX_CYCLES   = %0d", MAX_CYCLES);
        $display("");

        rst = 1'b1;
        cycle_count = 0;

        repeat (3) @(posedge clk);
        #1;
        rst = 1'b0;

        $display("cycle        pc        instr");

        while (cycle_count < MAX_CYCLES) begin

            $display(
                "%5d  %08h  %08h",
                cycle_count,
                dut.if_pc_cur,
                dut.if_instr
            );

            @(posedge clk);
            #1;
            cycle_count++;
        end

        $display("");
        $display("CPU PROGRAM TEST FINISHED");
        $finish;
    end

endmodule