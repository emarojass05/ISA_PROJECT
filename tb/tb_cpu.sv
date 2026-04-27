`timescale 1ns/1ps

module tb_cpu;

    // Core testbench signals
    logic clk;
    logic rst;

    cpu_top #(
        .PROGRAM_FILE("programs/hex/program.hex")
    ) dut (
        .clk(clk),
        .rst(rst)
    );

    // Clock generation (10 MHz)
    always #5 clk = ~clk;

    initial begin
        // VCD waveform dumping
        $dumpfile("build/sim/ondas_cpu_pipeline.vcd");
        $dumpvars(0, tb_cpu);
        
        clk = 0;
        rst = 1;

        $display("===============================================================");
        $display(" PIPELINE TESTBENCH: FULL SECURITY COPROCESSOR VERIFICATION");
        $display("===============================================================");

        #15 rst = 0;

        // Register initialization and state injection
        dut.u_rf.registers[1]  = 32'hDEADBEEF; // Auth Key
        
        dut.u_rf.registers[2]  = 32'h11112222; // Key A
        dut.u_rf.registers[3]  = 32'd0;        // Vault Index 0
        
        dut.u_rf.registers[4]  = 32'h33334444; // Key B
        dut.u_rf.registers[5]  = 32'd1;        // Vault Index 1
        
        dut.u_rf.registers[6]  = 32'h55556666; // Key C (TEA Key)
        dut.u_rf.registers[7]  = 32'd2;        // Vault Index 2 & TEA b data
        
        dut.u_rf.registers[9]  = 32'h00000010; // Data for sec.addK
        dut.u_rf.registers[12] = 32'h00000001; // Data for TEA a
        dut.u_rf.registers[13] = 32'd64;       // Base address for RAM storage
        
        // Real-time state monitor (Updated to if_pc_cur for Pipeline)
        $monitor("T: %0t | PC Fetch: %h | Auth: %b | Vault[0]: %h | Vault[1]: %h | Vault[2]: %h", 
                 $time, dut.if_pc_cur, dut.auth_bit, dut.u_key_vault.vault[0], dut.u_key_vault.vault[1], dut.u_key_vault.vault[2]);

        // Esperar suficiente tiempo para que el pipeline completo se vacíe
        #400;
        $finish;
    end

    // Auto-checking hardware verifiers
    always @(posedge clk) begin
        // Verify sec.addK (Expected: 10 + 11112222 = 11112232)
        if (dut.u_rf.registers[8] == 32'h11112232) begin
            $display("   [PASS] sec.addK mathematical verification successful: %h", dut.u_rf.registers[8]);
        end
        
        // Verify sec.xorK (Expected: 11112232 ^ 33334444 = 22226676)
        if (dut.u_rf.registers[10] == 32'h22226676) begin
            $display("   [PASS] sec.xorK chained mathematical verification successful: %h", dut.u_rf.registers[10]);
        end
        
        // Verify TEA Core Algorithm (Expected: 12)
        if (dut.u_rf.registers[11] == 32'h00000012) begin
            $display("   [PASS] TEA hardware encryption core verified: %h", dut.u_rf.registers[11]);
        end
        
        // Verify Main RAM integration
        if (dut.u_dmem.memory[16] == 32'h00000012) begin // Address 64 / 4 bytes = index 16
            $display("   [PASS] Secure data successfully exported to external RAM at index 16");
        end
    end

endmodule