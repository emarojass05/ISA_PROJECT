`timescale 1ns/1ps

module tb_cpu;

    // Clock and reset signals
    logic clk;
    logic rst;

    // DUT instance
    cpu_top #(
            .PROGRAM_FILE("programs/hex/program.hex"),
            .INITIAL_MEM("build/memory.mem")
        ) dut (
            .clk(clk),
            .rst(rst)
        );

    always #5 clk = ~clk;

    // Final memory dump
    final begin
        $writememh("build/sim/memory_dump.txt", dut.u_dmem.memory);
        $display("\n===============================================================");
        $display(" [SYSTEM] Simulation finished.");
        $display(" [MEMORY] Dump saved to: build/sim/memory_dump.txt");
        $display("===============================================================");
    end

    // Initial stimuli
    initial begin
        $dumpfile("build/sim/pipeline_cpu_waves.vcd");
        $dumpvars(0, tb_cpu);
        
        clk = 0;
        rst = 1;

        $display("===============================================================");
        $display(" PIPELINE TESTBENCH: FULL SECURITY COPROCESSOR VERIFICATION");
        $display("===============================================================");

        #15 rst = 0;

        // Register file initial state
        dut.u_rf.registers[1]  = 32'hDEADBEEF;
        
        dut.u_rf.registers[2]  = 32'h11112222;
        dut.u_rf.registers[3]  = 32'd0;
        
        dut.u_rf.registers[4]  = 32'h33334444;
        dut.u_rf.registers[5]  = 32'd1;
        
        dut.u_rf.registers[6]  = 32'h55556666;
        dut.u_rf.registers[7]  = 32'd2;
        
        dut.u_rf.registers[9]  = 32'h00000010;
        dut.u_rf.registers[12] = 32'h00000001;
        dut.u_rf.registers[13] = 32'd64;

        #2000000; 
        
        $finish;
    end

    // Automatic checks
    always @(posedge clk) begin
        if (dut.u_rf.registers[11] == 32'h00000012) begin
            $display("   [PASS] TEA hardware encryption core verified: %h", dut.u_rf.registers[11]);
        end
        
        if (dut.u_dmem.memory[16] == 32'h00000012) begin
            $display("   [PASS] Secure data exported to RAM successfully.");
        end
    end

endmodule