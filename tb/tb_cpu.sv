`timescale 1ns/1ps

module tb_cpu;

    // --- Señales de reloj y reset ---
    logic clk;
    logic rst;

    // --- Instancia del Procesador (DUT) ---
    cpu_top #(
        .PROGRAM_FILE("programs/hex/program.hex") // Ruta corregida según tu estructura
    ) dut (
        .clk(clk),
        .rst(rst)
    );

    // Generación de Reloj (10 MHz)
    always #5 clk = ~clk;

    // ========================================================================
    // BLOQUE FINAL: El salvavidas de los datos
    // ========================================================================
    // Este bloque se ejecuta SIEMPRE al final de la simulación, incluso si 
    // ocurre un $fatal. Esto asegura que el extractor de Python siempre 
    // tenga un archivo que leer.
    final begin
        $writememh("build/sim/memory_dump.txt", dut.u_dmem.memory);
        $display("\n===============================================================");
        $display(" [SISTEMA] Simulación finalizada.");
        $display(" [MEMORIA] Volcado guardado en: build/sim/memory_dump.txt");
        $display("===============================================================");
    end

    // ========================================================================
    // ESTÍMULOS INICIALES
    // ========================================================================
    initial begin
        // Configuración de archivos de ondas para GTKWave
        $dumpfile("build/sim/pipeline_cpu_waves.vcd");
        $dumpvars(0, tb_cpu);
        
        clk = 0;
        rst = 1;

        $display("===============================================================");
        $display(" PIPELINE TESTBENCH: FULL SECURITY COPROCESSOR VERIFICATION");
        $display("===============================================================");

        #15 rst = 0;

        // --- Inyección de estado inicial en el Banco de Registros ---
        // Estas constantes ayudan a que el Programa Supremo corra
        dut.u_rf.registers[1]  = 32'hDEADBEEF; // Llave de Autenticación
        
        dut.u_rf.registers[2]  = 32'h11112222; // Dato para Llave A
        dut.u_rf.registers[3]  = 32'd0;        // Índice Bóveda 0
        
        dut.u_rf.registers[4]  = 32'h33334444; // Dato para Llave B
        dut.u_rf.registers[5]  = 32'd1;        // Índice Bóveda 1
        
        dut.u_rf.registers[6]  = 32'h55556666; // Dato para Llave C (TEA Key)
        dut.u_rf.registers[7]  = 32'd2;        // Índice Bóveda 2
        
        dut.u_rf.registers[9]  = 32'h00000010; // Dato para operación sec.addK
        dut.u_rf.registers[12] = 32'h00000001; // Dato 'a' para TEA
        dut.u_rf.registers[13] = 32'd64;       // Dirección base en RAM (0x40)

        // Monitoreo en tiempo real
        $monitor("T: %0t | PC Fetch: %h | Auth: %b | Vault[0]: %h | Vault[1]: %h | Vault[2]: %h", 
                 $time, dut.if_pc_cur, dut.auth_bit, dut.u_key_vault.vault[0], dut.u_key_vault.vault[1], dut.u_key_vault.vault[2]);

        // Esperamos a que el programa ejecute sus instrucciones.
        // La alarma de seguridad saltará antes de llegar al final del tiempo.
        #400; 
        
        $finish;
    end

    // ========================================================================
    // VERIFICADORES AUTOMÁTICOS
    // ========================================================================
    always @(posedge clk) begin
        // Verificación matemática de la ALU Segura (TEA Core)
        if (dut.u_rf.registers[11] == 32'h00000012) begin
            $display("   [PASS] TEA hardware encryption core verified: %h", dut.u_rf.registers[11]);
        end
        
        // Verificación de exportación a RAM (Dirección 64 = índice 16)
        if (dut.u_dmem.memory[16] == 32'h00000012) begin
            $display("   [PASS] Datos seguros exportados a RAM exitosamente.");
        end
    end

endmodule