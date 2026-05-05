# Modelado de Simulación — SecuRISC-32

## 1. Objetivo

Este documento describe cómo se materializa la microarquitectura de SecuRISC-32 dentro de una simulación con Icarus Verilog (`iverilog`), cómo se inicializan los recursos del procesador (memorias, banco de registros, bóveda), y cómo el simulador interactúa con la herramienta de carga de archivos y la utilidad de extracción.

El modelo es una simulación funcional ciclo a ciclo. Cada flanco de reloj avanza el pipeline y produce salidas observables (PC, registros, memoria, bóveda) que los testbenches inspeccionan y vuelcan a archivos de salida.

---

## 2. Estructura general de la simulación

El proyecto incluye varios testbenches en `tb/`. Los dos principales para validación integral del CPU son:

| Testbench | Propósito |
|---|---|
| `tb/tb_cpu.sv` | Ejecución integral con preconfiguración de registros y generación de VCD |
| `tb/tb_cpu_program.sv` | Ejecución parametrizable con `PROGRAM_FILE`, `INITIAL_MEM` y `MAX_CYCLES` |

### 2.1 `tb_cpu_program.sv`

Acepta tres parámetros que se pasan desde el Makefile:

| Parámetro | Descripción |
|---|---|
| `PROGRAM_FILE` | Archivo `.hex` cargado en la memoria de instrucciones |
| `INITIAL_MEM` | Archivo `.mem` cargado en la memoria de datos (opcional) |
| `MAX_CYCLES` | Número máximo de ciclos a simular |

Al final de la simulación, vuelca a `build/sim/`:

- `register_dump.txt`: estado final del banco de registros
- `memory_dump.txt`: estado final de la memoria de datos

Ejemplo de uso:

    make sv-cpu-exec PROGRAM=programs/hex/factorial.hex MAX_CYCLES=300

### 2.2 `tb_cpu.sv`

Tiene una sección de pre-carga de registros (con la contraseña `0xDEADBEEF` en `x1` y datos para la bóveda) que facilita la ejecución de programas que esperan ese estado inicial. Genera un archivo VCD para GTKWave:

    build/sim/pipeline_cpu_waves.vcd

Se ejecuta con:

    make sv-run-cpu

---

## 3. Inicialización de recursos

### 3.1 Memoria de instrucciones (`instr_mem.sv`)

    if (PROGRAM_FILE != "") begin
        $readmemh(PROGRAM_FILE, memory);
    end

Carga el archivo `.hex` línea por línea como palabras de 32 bits.

### 3.2 Memoria de datos (`data_mem.sv`)

Inicializada a cero en `initial`, y opcionalmente cargada desde un archivo `.mem` generado por `tools/load_file.py`:

    if (INITIAL_MEM != "") begin
        $display("Loading data memory from: %s", INITIAL_MEM);
        $readmemh(INITIAL_MEM, memory);
    end

### 3.3 Banco de registros (`register_file.sv`)

32 registros de 32 bits, inicializados a cero. El registro `x0` siempre lee como cero y las escrituras a `x0` se ignoran.

### 3.4 Bóveda de llaves (`key_vault.sv`)

Arreglo interno de 16 palabras de 32 bits (4 llaves × 4 words = 128 bits cada una), inicializadas a cero. Solo accesible mediante las instrucciones `ldk`, `addk`, `xork` y `tea`, todas gateadas por la señal `auth_en`.

### 3.5 Estado de autenticación

El bit `auth_bit` se inicializa a cero en reset. Se activa solo cuando la instrucción `auth` se ejecuta con el valor `0xDEADBEEF` en su operando.

---

## 4. Ciclo de ejecución

El procesador ejecuta el siguiente ciclo conceptual en cada instrucción, distribuido en cinco etapas de pipeline:

1. **IF**: lectura desde `instr_mem[PC>>2]`, cálculo de `PC + 4`.
2. **ID**: decodificación, lectura del banco de registros, generación de señales de control.
3. **EX**: operación de ALU o sec_alu, evaluación de branches.
4. **MEM**: acceso a memoria de datos para `lw`/`sw`.
5. **WB**: escritura del resultado en el banco de registros.

Las instrucciones de seguridad (`SEC_*`) viajan por el mismo pipeline; la lectura de la bóveda ocurre en ID y la operación criptográfica en EX.

---

## 5. Herramienta de carga (`tools/load_file.py`)

Convierte un archivo binario en un archivo `.mem` apto para `$readmemh`:

    ./tools/load_file.py --input examples/test1.png \
                         --output memory.mem \
                         --address 0x1000

Genera un encabezado con la dirección inicial:

    @400
    474E5089
    0A1A0A0D
    ...

Donde `@400` es el índice de palabra correspondiente a la dirección de byte `0x1000` (división entera por 4).

---

## 6. Herramienta de extracción (`tools/extract_data.py`)

Lee `memory_dump.txt` y reconstruye un archivo binario:

    ./tools/extract_data.py --memory build/sim/memory_dump.txt \
                            --address 0x1000 \
                            --size 4096 \
                            --output resultado.bin

Permite verificar que el contenido cifrado de la memoria corresponde al esperado, o restaurar archivos descifrados después de un roundtrip.

---

## 7. Flujo end-to-end de cifrado

El Makefile automatiza el flujo completo:

    examples/test1.png
            │ load_file.py
            ▼
    memory.mem
            │ $readmemh en simulación
            ▼
    DMEM cargada en 0x1000+
            │ programa de cifrado en programs/hex/encrypt.hex
            ▼
    DMEM modificada (datos cifrados)
            │ $writememh al final
            ▼
    build/sim/memory_dump.txt
            │ extract_data.py
            ▼
    examples/enc_test1.png

Y para la verificación:

    make verify-roundtrip FILE=test1.png
    make verify-roundtrip-tea FILE=test1.png

El primero valida cifrado XOR (auto-inverso), el segundo el flujo completo TEA.

---

## 8. Testbenches específicos

| Testbench | Cobertura |
|---|---|
| `tb_alu.sv` | Operaciones aritméticas y lógicas, flags Z/N/C/V |
| `tb_control_unit.sv` | Generación de señales de control |
| `tb_decoder.sv` | Extracción de campos y extensión de inmediatos |
| `tb_pc.sv` | Registro del Program Counter |
| `tb_pc_adder.sv` | Cálculo de PC + 4 |
| `tb_register_file.sv` | Lectura/escritura del banco de registros, x0 hardwired |
| `tb_data_mem.sv` | Memoria de datos: lectura, escritura, alineación |
| `tb_instr_mem.sv` | Memoria de instrucciones, carga inicial |
| `tb_key_vault.sv` | Bóveda: gating por `auth_en`, escritura/lectura, lockdown |
| `tb_sec_alu.sv` | Operaciones SEC: ADDK, XORK, TEA, defensa zero-attack |
| `tb_cpu.sv` | Sistema completo con setup de registros y VCD |
| `tb_cpu_program.sv` | Sistema completo parametrizable |
| `tb_cpu_top.sv` | Integración general |

Cada testbench se ejecuta con:

    make sv-run-<modulo>

Por ejemplo:

    make sv-run-alu
    make sv-run-key_vault
    make sv-run-sec_alu

---

## 9. Visualización con GTKWave

El testbench `tb_cpu.sv` genera un archivo VCD:

    build/sim/pipeline_cpu_waves.vcd

Se abre con:

    gtkwave build/sim/pipeline_cpu_waves.vcd

Señales recomendadas para inspección:

- `dut.if_pc_cur` - PC actual
- `dut.u_rf.registers[*]` - banco de registros
- `dut.auth_bit` - estado de autenticación
- `dut.u_key_vault.vault[*]` - bóveda de llaves
- `dut.u_alu.result` - resultado de la ALU
- `dut.u_sec_alu.result` - resultado de la sec_alu
- `dut.u_dmem.memory[*]` - memoria de datos

---

## 10. Resumen del modelo

| Recurso | Modelado | Inicialización |
|---|---|---|
| Banco de registros | `logic [31:0] registers[32]`, x0 hardwired | Todos a 0 |
| RAM (DMEM) | `logic [31:0] memory[65536]` | `$readmemh(INITIAL_MEM)` opcional |
| ROM (IMEM) | `logic [31:0] memory[65536]` | `$readmemh(PROGRAM_FILE)` |
| Bóveda | `logic [31:0] vault[16]`, aislada | Todas a 0 |
| Estado autenticación | `auth_bit` (1 bit) | 0 en reset |
| sec_alu | Lógica combinacional | — |
| Pipeline | Registros IF/ID, ID/EX, EX/MEM, MEM/WB | Reset síncrono |
| I/O usuario | `$readmemh` (entrada) + `$writememh` (salida) + scripts Python | — |