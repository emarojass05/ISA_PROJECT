`timescale 1ns/1ps

module tb_cpu_cache;

    localparam int XLEN       = 32;
    localparam int IMEM_DEPTH = 128;
    localparam int DMEM_DEPTH = 256;

    logic clk;
    logic rst;
    int errors;

    cpu_top #(
        .XLEN(XLEN),
        .IMEM_DEPTH(IMEM_DEPTH),
        .DMEM_DEPTH(DMEM_DEPTH),
        .PROGRAM_FILE(""),
        .INITIAL_MEM("")
    ) dut (
        .clk(clk),
        .rst(rst)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    function automatic logic [31:0] enc_addi(
        input logic [4:0] rd,
        input logic [4:0] rs1,
        input logic [11:0] imm
    );
        enc_addi = {imm, rs1, 3'b000, rd, 7'h01};
    endfunction

    function automatic logic [31:0] enc_lw(
        input logic [4:0] rd,
        input logic [4:0] rs1,
        input logic [11:0] imm
    );
        enc_lw = {imm, rs1, 3'b100, rd, 7'h03};
    endfunction

    function automatic logic [31:0] enc_sw(
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [11:0] imm
    );
        enc_sw = {imm[11:5], rs2, rs1, 3'b000, imm[4:0], 7'h02};
    endfunction

    task automatic check_value(
        input logic [31:0] actual,
        input logic [31:0] expected,
        input string test_name
    );
        begin
            if (actual !== expected) begin
                $display("FAIL %-32s actual=%h expected=%h", test_name, actual, expected);
                errors++;
            end else begin
                $display("PASS %-32s value=%h", test_name, actual);
            end
        end
    endtask

    task automatic check_ge(
        input logic [63:0] actual,
        input logic [63:0] minimum,
        input string test_name
    );
        begin
            if (actual < minimum) begin
                $display("FAIL %-32s actual=%0d minimum=%0d", test_name, actual, minimum);
                errors++;
            end else begin
                $display("PASS %-32s value=%0d", test_name, actual);
            end
        end
    endtask

    initial begin
        $display("CPU CACHE INTEGRATION TEST START");

        errors = 0;
        rst = 1'b1;

        #1;

        dut.u_imem.memory[0]  = enc_addi(5'd1, 5'd0, 12'd0);
        dut.u_imem.memory[1]  = 32'h0000_0001;
        dut.u_imem.memory[2]  = 32'h0000_0001;
        dut.u_imem.memory[3]  = enc_lw(5'd2, 5'd1, 12'd0);
        dut.u_imem.memory[4]  = 32'h0000_0001;
        dut.u_imem.memory[5]  = 32'h0000_0001;
        dut.u_imem.memory[6]  = enc_lw(5'd3, 5'd1, 12'd0);
        dut.u_imem.memory[7]  = 32'h0000_0001;
        dut.u_imem.memory[8]  = 32'h0000_0001;
        dut.u_imem.memory[9]  = enc_sw(5'd3, 5'd1, 12'd4);
        dut.u_imem.memory[10] = 32'h0000_0001;
        dut.u_imem.memory[11] = 32'h0000_0001;
        dut.u_imem.memory[12] = enc_lw(5'd4, 5'd1, 12'd4);
        dut.u_imem.memory[13] = 32'h0000_0001;
        dut.u_imem.memory[14] = 32'h0000_0001;
        dut.u_imem.memory[15] = 32'h0000_0007;

        dut.u_dmem.memory[0] = 32'h1111_2222;
        dut.u_dmem.memory[1] = 32'h3333_4444;
        dut.u_dmem.main_memory[0] = 32'h1111_2222;
        dut.u_dmem.main_memory[1] = 32'h3333_4444;

        repeat (4) @(posedge clk);
        #1;
        rst = 1'b0;

        repeat (260) @(posedge clk);
        #1;

        check_value(dut.u_rf.registers[2], 32'h1111_2222, "lw x2 from mem[0]");
        check_value(dut.u_rf.registers[3], 32'h1111_2222, "lw x3 from mem[0]");
        check_value(dut.u_rf.registers[4], 32'h1111_2222, "lw x4 from mem[1]");
        check_value(dut.u_dmem.memory[1], 32'h1111_2222, "store visible in memory mirror");

        check_ge(dut.l1_read_accesses, 64'd3, "L1 read accesses");
        check_ge(dut.l1_read_hits, 64'd2, "L1 read hits");
        check_ge(dut.l1_read_misses, 64'd1, "L1 read misses");
        check_ge(dut.l1_write_hits, 64'd1, "L1 write hits");
        check_ge(dut.l2_read_misses, 64'd1, "L2 read misses");
        check_ge(dut.cache_stall_cycles, 64'd1, "cache stall cycles");
        check_ge(dut.perf_cache_stall_cycles, 64'd1, "CPU stall counter");

        $display("CPU cycles=%0d retired=%0d cache_stalls=%0d",
                 dut.perf_cycles,
                 dut.perf_retired_instructions,
                 dut.perf_cache_stall_cycles);

        if (errors == 0) begin
            $display("CPU CACHE INTEGRATION TEST PASSED");
        end else begin
            $display("CPU CACHE INTEGRATION TEST FAILED: %0d error(s)", errors);
        end

        $finish;
    end

endmodule