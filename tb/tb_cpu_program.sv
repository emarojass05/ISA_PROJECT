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

    parameter string REGISTER_DUMP_FILE = "build/sim/register_dump.txt";
    parameter string MEMORY_DUMP_FILE   = "build/sim/memory_dump.txt";
    parameter string CYCLE_COUNT_FILE   = "build/sim/cycle_count.txt";
    parameter string METRICS_FILE       = "build/sim/metrics.txt";

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

    task automatic dump_metrics;
        input integer cycles;
        integer file;
        real ipc;
        real l1_hit_rate;
        real l2_hit_rate;
        real mm_bytes;
        real bw_bytes_per_cycle;
        begin
            file = $fopen(METRICS_FILE, "w");

            if (file == 0) begin
                $display("[ERR] Could not open metrics file: %0s", METRICS_FILE);
            end else begin
                ipc = (cycles > 0) ?
                      ($itor(dut.perf_instr_retired) / $itor(cycles)) : 0.0;

                l1_hit_rate = (dut.perf_l1_accesses > 0) ?
                              ($itor(dut.perf_l1_hits) / $itor(dut.perf_l1_accesses) * 100.0) : 0.0;

                l2_hit_rate = ((dut.perf_l2_hits + dut.perf_l2_misses) > 0) ?
                              ($itor(dut.perf_l2_hits) /
                               $itor(dut.perf_l2_hits + dut.perf_l2_misses) * 100.0) : 0.0;

                // Each main-memory fetch transfers one 256-bit (32-byte) cache line.
                mm_bytes           = $itor(dut.perf_mm_accesses) * 32.0;
                bw_bytes_per_cycle = (cycles > 0) ? (mm_bytes / $itor(cycles)) : 0.0;

                $fdisplay(file, "PERFORMANCE METRICS");
                $fdisplay(file, "===================");
                $fdisplay(file, "");
                $fdisplay(file, "Cycles total         : %0d", cycles);
                $fdisplay(file, "Instructions retired : %0d", dut.perf_instr_retired);
                $fdisplay(file, "IPC                  : %.4f", ipc);
                $fdisplay(file, "");
                $fdisplay(file, "Cache stall cycles   : %0d", dut.perf_cache_stall_cycles);
                $fdisplay(file, "Control stall slots  : %0d", dut.perf_ctrl_stall_cycles);
                $fdisplay(file, "");
                $fdisplay(file, "L1 accesses          : %0d", dut.perf_l1_accesses);
                $fdisplay(file, "L1 hits              : %0d", dut.perf_l1_hits);
                $fdisplay(file, "L1 misses            : %0d", dut.perf_l1_misses);
                $fdisplay(file, "L1 hit rate          : %.2f%%", l1_hit_rate);
                $fdisplay(file, "");
                $fdisplay(file, "L2 hits              : %0d", dut.perf_l2_hits);
                $fdisplay(file, "L2 misses            : %0d", dut.perf_l2_misses);
                $fdisplay(file, "L2 hit rate          : %.2f%%", l2_hit_rate);
                $fdisplay(file, "");
                $fdisplay(file, "Main memory fetches  : %0d", dut.perf_mm_accesses);
                $fdisplay(file, "MM bytes transferred : %.0f B", mm_bytes);
                $fdisplay(file, "BW utilization       : %.4f B/cycle", bw_bytes_per_cycle);

                $fclose(file);
                $display("[OK] Metrics written to %0s", METRICS_FILE);

                $display("");
                $display("========= PERFORMANCE SUMMARY =========");
                $display("  Cycles total         : %0d", cycles);
                $display("  Instructions retired : %0d", dut.perf_instr_retired);
                $display("  IPC                  : %.4f", ipc);
                $display("---------------------------------------");
                $display("  Cache stall cycles   : %0d", dut.perf_cache_stall_cycles);
                $display("  Control stall slots  : %0d", dut.perf_ctrl_stall_cycles);
                $display("---------------------------------------");
                $display("  L1 accesses          : %0d", dut.perf_l1_accesses);
                $display("  L1 hit rate          : %.2f%%", l1_hit_rate);
                $display("  L1 misses -> L2      : %0d", dut.perf_l1_misses);
                $display("  L2 hit rate          : %.2f%%", l2_hit_rate);
                $display("  Main memory fetches  : %0d", dut.perf_mm_accesses);
                $display("  BW utilization       : %.4f B/cycle", bw_bytes_per_cycle);
                $display("=======================================");
            end
        end
    endtask

    task automatic dump_and_finish;
        input [8*80-1:0] reason;
        input integer cycles;
        begin
            $display("");
            $display("[STOP] %0s", reason);
            $display("[INFO] Dumping register file, data memory and metrics...");

            dump_cycle_count(cycles);
            dump_metrics(cycles);
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

            // PC stability distinguishes the real self-loop from a speculative fetch.
            // A speculative capture of j PROGRAM_END (from the jal shadow in ENTRY)
            // appears for exactly one cycle: if_pc_cur != prev_pc that cycle.
            // The real self-loop has a stable PC: if_pc_cur == prev_pc every cycle.
            if (dut.if_instr == HALT_INSTR && dut.if_pc_cur == prev_pc) begin
                $display("[HALT] PROGRAM_END detected at cycle %0d (pc=%08h)",
                         cycle_count,
                         dut.if_pc_cur);

                // HALT is detected in IF; an in-flight MEM-stage load stalling on a
                // cache miss would not complete its WB within DRAIN_CYCLES otherwise.
                while (dut.cache_stall) begin
                    @(posedge clk);
                    #1;
                end

                // Drain the write buffer before the memory dump so that dirty
                // evictions from L2 are visible in main memory. Required for
                // verify-cache-modes correctness when CACHE_ENABLE=1.
                while (CACHE_ENABLE != 0 && !dut.wb_empty) begin
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