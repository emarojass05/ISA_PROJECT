`timescale 1ns/1ps

module tb_data_mem;

    localparam int XLEN  = 32;
    localparam int DEPTH = 16;

    logic            clk;
    logic            mem_write_enable;
    logic [XLEN-1:0] mem_write_data;
    logic [XLEN-1:0] memory_address;
    logic [XLEN-1:0] mem_read_data;

    int errors;

    data_mem #(
        .XLEN(XLEN),
        .DEPTH(DEPTH)
    ) dut (
        .clk(clk),
        .mem_write_enable(mem_write_enable),
        .mem_write_data(mem_write_data),
        .memory_address(memory_address),
        .mem_read_data(mem_read_data)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic write_word(
        input logic [XLEN-1:0] address,
        input logic [XLEN-1:0] data
    );
        begin
            memory_address    = address;
            mem_write_data    = data;
            mem_write_enable  = 1'b1;
            @(posedge clk);
            #1;
            mem_write_enable = 1'b0;
        end
    endtask

    task automatic check_read(
        input logic [XLEN-1:0] address,
        input logic [XLEN-1:0] expected_data,
        input string           test_name
    );
        begin
            memory_address = address;
            #1;

            if (mem_read_data !== expected_data) begin
                $display("FAIL %-24s address=%h data=%h expected=%h",
                         test_name, address, mem_read_data, expected_data);
                errors++;
            end else begin
                $display("PASS %-24s address=%h data=%h",
                         test_name, address, mem_read_data);
            end
        end
    endtask

    initial begin
        errors = 0;

        mem_write_enable = 1'b0;
        mem_write_data   = '0;
        memory_address   = '0;

        #2;

        write_word(32'h0000_0000, 32'hAAAA_0001);
        check_read(32'h0000_0000, 32'hAAAA_0001, "read word 0");

        write_word(32'h0000_0004, 32'hBBBB_0002);
        check_read(32'h0000_0004, 32'hBBBB_0002, "read word 1");

        write_word(32'h0000_0008, 32'hCCCC_0003);
        check_read(32'h0000_0008, 32'hCCCC_0003, "read word 2");

        write_word(32'h0000_0004, 32'hDDDD_0004);
        check_read(32'h0000_0004, 32'hDDDD_0004, "overwrite word 1");

        check_read(32'h0000_0000, 32'hAAAA_0001, "word 0 unchanged");
        check_read(32'h0000_0008, 32'hCCCC_0003, "word 2 unchanged");

        if (errors == 0) begin
            $display("DATA MEM TEST PASSED");
        end else begin
            $display("DATA MEM TEST FAILED: %0d error(s)", errors);
        end

        $finish;
    end

endmodule