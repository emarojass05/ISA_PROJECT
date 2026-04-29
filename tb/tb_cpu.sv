`timescale 1ns/1ps

module tb_cpu;

    // --- Clock and reset signals ---
    logic clk;
    logic rst;

    // --- Processor Instance (DUT) ---
    cpu_top #(
        .PROGRAM_FILE("programs/hex/program.hex") // Corrected path according to your structure
    ) dut (
        .clk(clk),
        .rst(rst)
    );

    // Clock Generation (10 MHz)
    always #5 clk = ~clk;

    // ========================================================================
    // FINAL BLOCK: Data lifesaver
    // ========================================================================
    // This block ALWAYS executes at the end of the simulation, even if 
    // a $fatal occurs. This ensures that the Python extractor always 
    // has a file to read.
    final begin
        $writememh("build/sim/memory_dump.txt", dut.u_dmem.memory);
        $display("\n===============================================================");
        $display(" [SYSTEM] Simulation finished.");
        $display(" [MEMORY] Dump saved in: build/sim/memory_dump.txt");
        $display("===============================================================");
    end

    // ========================================================================
    // INITIAL STIMULI
    // ========================================================================
    initial begin
        // Waveform file configuration for GTKWave
        $dumpfile("build/sim/pipeline_cpu_waves.vcd");
        $dumpvars(0, tb_cpu);
        
        clk = 0;
        rst = 1;

        $display("===============================================================");
        $display(" PIPELINE TESTBENCH: FULL SECURITY COPROCESSOR VERIFICATION");
        $display("===============================================================");

        #15 rst = 0;

        // --- Initial state injection into the Register File ---
        // These constants help the Supreme Program run
        dut.u_rf.registers[1]  = 32'hDEADBEEF; // Authentication Key
        
        dut.u_rf.registers[2]  = 32'h11112222; // Data for Key A
        dut.u_rf.registers[3]  = 32'd0;        // Vault Index 0
        
        dut.u_rf.registers[4]  = 32'h33334444; // Data for Key B
        dut.u_rf.registers[5]  = 32'd1;        // Vault Index 1
        
        dut.u_rf.registers[6]  = 32'h55556666; // Data for Key C (TEA Key)
        dut.u_rf.registers[7]  = 32'd2;        // Vault Index 2
        
        dut.u_rf.registers[9]  = 32'h00000010; // Data for sec.addK operation
        dut.u_rf.registers[12] = 32'h00000001; // Data 'a' for TEA
        dut.u_rf.registers[13] = 32'd64;       // Base address in RAM (0x40)

        // Real-time monitoring
        $monitor("T: %0t | PC Fetch: %h | Auth: %b | Vault[0]: %h | Vault[1]: %h | Vault[2]: %h", 
                 $time, dut.if_pc_cur, dut.auth_bit, dut.u_key_vault.vault[0], dut.u_key_vault.vault[1], dut.u_key_vault.vault[2]);

        // Wait for the program to execute its instructions.
        // The security alarm will trigger before reaching the end of the time limit.
        #500000; 
        
        $finish;
    end

    // ========================================================================
    // AUTOMATIC VERIFIERS
    // ========================================================================
    always @(posedge clk) begin
        // Mathematical verification of the Secure ALU (TEA Core)
        if (dut.u_rf.registers[11] == 32'h00000012) begin
            $display("   [PASS] TEA hardware encryption core verified: %h", dut.u_rf.registers[11]);
        end
        
        // RAM export verification (Address 64 = index 16)
        if (dut.u_dmem.memory[16] == 32'h00000012) begin
            $display("   [PASS] Secure data successfully exported to RAM.");
        end
    end

endmodule