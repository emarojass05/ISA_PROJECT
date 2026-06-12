`timescale 1ns/1ps
import isa_defs::*;

module tb_cpu_program;

    parameter int XLEN         = 32;
    parameter int IMEM_DEPTH   = 65536;
    parameter int DMEM_DEPTH   = 65536;
    parameter int CACHE_ENABLE = 0;

    parameter [1023:0] PROGRAM_FILE = "programs/hex/program.hex";
    parameter [1023:0] INITIAL_MEM  = "";

    parameter int MAX_CYCLES   = 200;
    parameter int DRAIN_CYCLES = 10;

    parameter [1023:0] REGISTER_DUMP_FILE = "build/sim/register_dump.txt";
    parameter [1023:0] MEMORY_DUMP_FILE   = "build/sim/memory_dump.txt";
    parameter [1023:0] CYCLE_COUNT_FILE   = "build/sim/cycle_count.txt";

    // j offset=0, opcode=0x07
    localparam logic [31:0] HALT_INSTR = 32'h00000007;

    logic clk;
    logic rst;

    integer cycle_count;
    integer drain_count;
    logic [31:0] prev_pc;

    cpu_top #(
        .XLEN        (XLEN),
        .IMEM_DEPTH  (IMEM_DEPTH),
        .DMEM_DEPTH  (DMEM_DEPTH),
        .CACHE_ENABLE(CACHE_ENABLE),
        .PROGRAM_FILE(PROGRAM_FILE),
        .INITIAL_MEM (INITIAL_MEM)
    ) dut (
        .clk(clk),
        .rst(rst)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic dump_register_line;
        input integer file;
        input integer index;
        input logic [XLEN-1:0] value;
        begin
            $fdisplay(file, "x%0d = %08h", index, value);
        end
    endtask

    task automatic dump_register_file;
        integer file;
        begin
            file = $fopen(REGISTER_DUMP_FILE, "w");

            if (file == 0) begin
                $display("[ERR] Could not open register dump file: %0s", REGISTER_DUMP_FILE);
            end else begin
                $fdisplay(file, "REGISTER FILE DUMP");
                $fdisplay(file, "==================");
                $fdisplay(file, "");

                begin : dump_loop
                    integer ri;
                    for (ri = 0; ri < 32; ri = ri + 1) begin
                        if (ri == 0)
                            dump_register_line(file, ri, 32'h0);
                        else if (ri == 30)
                            // x30 (R_DELTA) is hardwired — reads return DELTA_CONSTANT
                            dump_register_line(file, ri, DELTA_CONSTANT);
                        else
                            dump_register_line(file, ri, dut.u_rf.registers[ri]);
                    end
                end

                $fclose(file);
                $display("[OK] Register dump written to %0s", REGISTER_DUMP_FILE);
            end
        end
    endtask

    task automatic dump_data_memory;
        begin
            if (CACHE_ENABLE == 0) begin
                $writememh(MEMORY_DUMP_FILE, dut.u_cache.bypass_mem);
            end else begin
                $writememh(MEMORY_DUMP_FILE, dut.u_cache.u_main_mem.memory);
            end

            $display("[OK] Memory dump written to %0s", MEMORY_DUMP_FILE);
        end
    endtask

    task automatic dump_cycle_count;
        input integer cycles;
        integer file;
        begin
            file = $fopen(CYCLE_COUNT_FILE, "w");

            if (file == 0) begin
                $display("[ERR] Could not open cycle count file: %0s", CYCLE_COUNT_FILE);
            end else begin
                $fdisplay(file, "%0d", cycles);
                $fclose(file);
                $display("[OK] Cycle count (%0d) written to %0s", cycles, CYCLE_COUNT_FILE);
            end
        end
    endtask

    task automatic dump_and_finish;
        input [8*80-1:0] reason;
        input integer cycles;
        begin
            $display("");
            $display("[STOP] %0s", reason);
            $display("[INFO] Dumping register file and data memory...");

            dump_cycle_count(cycles);
            dump_register_file();
            dump_data_memory();

            $display("");
            $display("CPU PROGRAM TEST FINISHED");
            $finish;
        end
    endtask

    initial begin
        $dumpfile("tb_cpu_program.vcd");
        $dumpvars(0, tb_cpu_program);

        $display("CPU PROGRAM TEST START");
        $display("PROGRAM_FILE = %0s", PROGRAM_FILE);
        $display("INITIAL_MEM  = %0s", INITIAL_MEM);
        $display("CACHE_ENABLE = %0d", CACHE_ENABLE);
        $display("MAX_CYCLES   = %0d", MAX_CYCLES);
        $display("DRAIN_CYCLES = %0d", DRAIN_CYCLES);
        $display("");

        rst         = 1'b1;
        cycle_count = 0;
        prev_pc     = 32'hFFFFFFFF;

        repeat (3) @(posedge clk);
        #1;
        rst = 1'b0;

        $display("cycle        pc        instr        cache_stall");

        while (cycle_count < MAX_CYCLES) begin
            $display(
                "%5d  %08h  %08h  %b",
                cycle_count,
                dut.if_pc_cur,
                dut.if_instr,
                dut.cache_stall
            );

            // cycle_count > 10 avoids a false positive while the pipeline is filling
            if (dut.if_instr == HALT_INSTR && cycle_count > 10) begin
                $display("[HALT] PROGRAM_END detected at cycle %0d (pc=%08h)",
                         cycle_count,
                         dut.if_pc_cur);

                // HALT is detected in IF; an in-flight MEM-stage load stalling on a
                // cache miss would not complete its WB within DRAIN_CYCLES otherwise.
                while (dut.cache_stall) begin
                    @(posedge clk);
                    #1;
                end

                for (drain_count = 0; drain_count < DRAIN_CYCLES; drain_count = drain_count + 1) begin
                    @(posedge clk);
                    #1;
                end

                dump_and_finish("PROGRAM_END detected", cycle_count);
            end

            prev_pc = dut.if_pc_cur;

            @(posedge clk);
            #1;
            cycle_count = cycle_count + 1;
        end

        for (drain_count = 0; drain_count < DRAIN_CYCLES; drain_count = drain_count + 1) begin
            @(posedge clk);
            #1;
        end

        dump_and_finish("MAX_CYCLES reached", MAX_CYCLES);
    end

endmodule