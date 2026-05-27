`timescale 1ns/1ps

module tb_memory_hierarchy;

    localparam int XLEN  = 32;
    localparam int DEPTH = 256;

    logic clk;
    logic rst;

    logic              mem_read_enable;
    logic              mem_write_enable;
    logic [XLEN-1:0]   mem_write_data;
    logic [XLEN-1:0]   memory_address;
    logic [XLEN-1:0]   mem_read_data;
    logic              cache_stall;

    logic [63:0] l1_read_accesses;
    logic [63:0] l1_write_accesses;
    logic [63:0] l1_read_hits;
    logic [63:0] l1_read_misses;
    logic [63:0] l1_write_hits;
    logic [63:0] l1_write_misses;

    logic [63:0] l2_read_accesses;
    logic [63:0] l2_write_accesses;
    logic [63:0] l2_read_hits;
    logic [63:0] l2_read_misses;
    logic [63:0] l2_write_hits;
    logic [63:0] l2_write_misses;

    logic [63:0] main_mem_accesses;
    logic [63:0] main_mem_cycles;
    logic [63:0] cache_stall_cycles;

    int errors;

    memory_hierarchy #(
        .XLEN(XLEN),
        .DEPTH(DEPTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .mem_read_enable(mem_read_enable),
        .mem_write_enable(mem_write_enable),
        .mem_write_data(mem_write_data),
        .memory_address(memory_address),
        .mem_read_data(mem_read_data),
        .cache_stall(cache_stall),

        .l1_read_accesses(l1_read_accesses),
        .l1_write_accesses(l1_write_accesses),
        .l1_read_hits(l1_read_hits),
        .l1_read_misses(l1_read_misses),
        .l1_write_hits(l1_write_hits),
        .l1_write_misses(l1_write_misses),

        .l2_read_accesses(l2_read_accesses),
        .l2_write_accesses(l2_write_accesses),
        .l2_read_hits(l2_read_hits),
        .l2_read_misses(l2_read_misses),
        .l2_write_hits(l2_write_hits),
        .l2_write_misses(l2_write_misses),

        .main_mem_accesses(main_mem_accesses),
        .main_mem_cycles(main_mem_cycles),
        .cache_stall_cycles(cache_stall_cycles)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic check_value(
        input logic [XLEN-1:0] actual,
        input logic [XLEN-1:0] expected,
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

    task automatic check_counter(
        input logic [63:0] actual,
        input logic [63:0] expected,
        input string test_name
    );
        begin
            if (actual !== expected) begin
                $display("FAIL %-32s actual=%0d expected=%0d", test_name, actual, expected);
                errors++;
            end else begin
                $display("PASS %-32s value=%0d", test_name, actual);
            end
        end
    endtask

    task automatic read_word(
        input  logic [XLEN-1:0] address,
        output logic [XLEN-1:0] data
    );
        begin
            @(negedge clk);
            memory_address = address;
            mem_write_data = '0;
            mem_write_enable = 1'b0;
            mem_read_enable = 1'b1;
            #1;

            while (cache_stall) begin
                @(posedge clk);
                #1;
            end

            data = mem_read_data;

            @(negedge clk);
            mem_read_enable = 1'b0;
            memory_address = '0;
            #1;
        end
    endtask

    task automatic write_word(
        input logic [XLEN-1:0] address,
        input logic [XLEN-1:0] data
    );
        begin
            @(negedge clk);
            memory_address = address;
            mem_write_data = data;
            mem_write_enable = 1'b1;
            mem_read_enable = 1'b0;
            #1;

            while (cache_stall) begin
                @(posedge clk);
                #1;
            end

            @(negedge clk);
            mem_write_enable = 1'b0;
            mem_write_data = '0;
            memory_address = '0;
            #1;
        end
    endtask

    logic [XLEN-1:0] data;

    initial begin
        $display("MEMORY HIERARCHY TEST START");

        errors = 0;
        rst = 1'b1;

        #1;
        mem_read_enable = 1'b0;
        mem_write_enable = 1'b0;
        mem_write_data = '0;
        memory_address = '0;

        dut.memory[0] = 32'hAAAA_0001;
        dut.memory[1] = 32'hBBBB_0002;
        dut.memory[2] = 32'hCCCC_0003;
        dut.main_memory[0] = 32'hAAAA_0001;
        dut.main_memory[1] = 32'hBBBB_0002;
        dut.main_memory[2] = 32'hCCCC_0003;

        repeat (3) @(posedge clk);
        #1;
        rst = 1'b0;

        read_word(32'h0000_0000, data);
        check_value(data, 32'hAAAA_0001, "first read: L1 miss / L2 miss");
        check_counter(l1_read_misses, 64'd1, "L1 read misses after first read");
        check_counter(l2_read_misses, 64'd1, "L2 read misses after first read");
        check_counter(main_mem_accesses, 64'd1, "main memory accesses after fill");

        read_word(32'h0000_0000, data);
        check_value(data, 32'hAAAA_0001, "second read: L1 hit");
        check_counter(l1_read_hits, 64'd1, "L1 read hits after second read");

        read_word(32'h0000_0004, data);
        check_value(data, 32'hBBBB_0002, "same line read: L1 hit");
        check_counter(l1_read_hits, 64'd2, "L1 read hits after same line");

        write_word(32'h0000_0004, 32'hDEAD_BEEF);
        check_counter(l1_write_hits, 64'd1, "L1 write hit");
        check_counter(l2_write_hits, 64'd1, "L2 write hit");

        read_word(32'h0000_0004, data);
        check_value(data, 32'hDEAD_BEEF, "read after write hit");
        check_value(dut.memory[1], 32'hDEAD_BEEF, "debug memory mirror updated");

        if (cache_stall_cycles == 64'd0) begin
            $display("FAIL cache stall cycles should be greater than zero");
            errors++;
        end else begin
            $display("PASS cache stall cycles value=%0d", cache_stall_cycles);
        end

        $display("L1 reads=%0d hits=%0d misses=%0d", l1_read_accesses, l1_read_hits, l1_read_misses);
        $display("L1 writes=%0d hits=%0d misses=%0d", l1_write_accesses, l1_write_hits, l1_write_misses);
        $display("L2 reads=%0d hits=%0d misses=%0d", l2_read_accesses, l2_read_hits, l2_read_misses);
        $display("L2 writes=%0d hits=%0d misses=%0d", l2_write_accesses, l2_write_hits, l2_write_misses);
        $display("Main memory accesses=%0d cycles=%0d", main_mem_accesses, main_mem_cycles);

        if (errors == 0) begin
            $display("MEMORY HIERARCHY TEST PASSED");
        end else begin
            $display("MEMORY HIERARCHY TEST FAILED: %0d error(s)", errors);
        end

        $finish;
    end

endmodule