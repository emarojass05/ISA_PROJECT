`timescale 1ns/1ps

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

                dump_register_line(file,  0, 32'h00000000);
                dump_register_line(file,  1, dut.u_rf.registers[1]);
                dump_register_line(file,  2, dut.u_rf.registers[2]);
                dump_register_line(file,  3, dut.u_rf.registers[3]);
                dump_register_line(file,  4, dut.u_rf.registers[4]);
                dump_register_line(file,  5, dut.u_rf.registers[5]);
                dump_register_line(file,  6, dut.u_rf.registers[6]);
                dump_register_line(file,  7, dut.u_rf.registers[7]);
                dump_register_line(file,  8, dut.u_rf.registers[8]);
                dump_register_line(file,  9, dut.u_rf.registers[9]);
                dump_register_line(file, 10, dut.u_rf.registers[10]);
                dump_register_line(file, 11, dut.u_rf.registers[11]);
                dump_register_line(file, 12, dut.u_rf.registers[12]);
                dump_register_line(file, 13, dut.u_rf.registers[13]);
                dump_register_line(file, 14, dut.u_rf.registers[14]);
                dump_register_line(file, 15, dut.u_rf.registers[15]);
                dump_register_line(file, 16, dut.u_rf.registers[16]);
                dump_register_line(file, 17, dut.u_rf.registers[17]);
                dump_register_line(file, 18, dut.u_rf.registers[18]);
                dump_register_line(file, 19, dut.u_rf.registers[19]);
                dump_register_line(file, 20, dut.u_rf.registers[20]);
                dump_register_line(file, 21, dut.u_rf.registers[21]);
                dump_register_line(file, 22, dut.u_rf.registers[22]);
                dump_register_line(file, 23, dut.u_rf.registers[23]);
                dump_register_line(file, 24, dut.u_rf.registers[24]);
                dump_register_line(file, 25, dut.u_rf.registers[25]);
                dump_register_line(file, 26, dut.u_rf.registers[26]);
                dump_register_line(file, 27, dut.u_rf.registers[27]);
                dump_register_line(file, 28, dut.u_rf.registers[28]);
                dump_register_line(file, 29, dut.u_rf.registers[29]);
                dump_register_line(file, 30, 32'h9E3779B9);
                dump_register_line(file, 31, dut.u_rf.registers[31]);

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

            // Detecta PROGRAM_END cuando aparece j 0x0.
            // Se usa cycle_count > 10 para evitar falso positivo durante el llenado del pipeline.
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