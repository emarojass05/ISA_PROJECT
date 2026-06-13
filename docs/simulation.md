# Modelado de Simulación — SecuRISC-32

## 1. Objetivo del modelo de simulación

Este documento describe cómo se simula SecuRISC-32 con Icarus Verilog, cómo se inicializan sus memorias, cómo se ejecutan programas `.hex`, cómo se habilita o deshabilita la jerarquía de caché, cómo se generan dumps de salida y cómo se extraen métricas de rendimiento.

El modelo de simulación es funcional ciclo a ciclo. Su objetivo no es sintetizar un sistema físico completo, sino permitir observar el comportamiento del pipeline, la jerarquía de caché, los stalls por misses, los contadores de rendimiento y la equivalencia funcional entre ejecución con caché y sin caché.

---

## 2. Estructura del top de simulación

El testbench principal para ejecutar programas completos es:

```text
tb/tb_cpu_program.sv
```

Estructura general:

```text
tb_cpu_program.sv
   │
   ├── instancia dut: cpu_top.sv
   │       ├── pc / pc_adder
   │       ├── instr_mem
   │       ├── decoder / control_unit
   │       ├── register_file
   │       ├── alu / sec_alu
   │       ├── key_vault
   │       ├── hazard_unit / forwarding_unit
   │       └── cache_hierarchy
   │              ├── cache_ctrl
   │              ├── cache_l1d
   │              ├── cache_l2
   │              ├── mem_write_buffer
   │              └── main_mem_model
   │
   ├── generador de reloj de 10 ns
   ├── reset inicial
   ├── monitor de ciclo, PC, instrucción y cache_stall
   ├── detección de HALT mediante instrucción j offset=0
   └── generación de dumps y métricas
```

El testbench puede ejecutarse en dos modos:

| Modo                  | Valor                  | Descripción                                      |
| --------------------- | ---------------------- | ------------------------------------------------ |
| Sin caché             | `CACHE_ENABLE=0`       | Usa memoria de bypass dentro de `cache_hierarchy` |
| Con caché             | `CACHE_ENABLE=1`       | Usa L1-D, L2, write buffer y memoria principal    |

---

## 3. Parámetros principales de simulación

`tb_cpu_program.sv` define los siguientes parámetros:

| Parámetro            | Descripción                                                           |
| -------------------- | --------------------------------------------------------------------- |
| `XLEN`               | Ancho de palabra, 32 bits                                             |
| `IMEM_DEPTH`         | Profundidad de memoria de instrucciones                               |
| `DMEM_DEPTH`         | Profundidad de memoria de datos/memoria principal                     |
| `CACHE_ENABLE`       | Habilita o deshabilita jerarquía de caché                             |
| `PROGRAM_FILE`       | Archivo de programa `.hex`                                            |
| `INITIAL_MEM`        | Archivo `.mem` opcional para inicializar datos                        |
| `MAX_CYCLES`         | Límite de ciclos para evitar simulaciones infinitas                   |
| `DRAIN_CYCLES`       | Ciclos extra después de HALT para permitir vaciado del pipeline        |

El Makefile permite sobreescribir varios de estos valores:

```bash
make sv-cpu-exec PROGRAM=programs/hex/program.hex MAX_CYCLES=2000 CACHE_ENABLE=1
```

Con memoria inicial:

```bash
make sv-cpu-exec PROGRAM=programs/hex/encrypt.hex INITIAL_MEM=build/memory.mem CACHE_ENABLE=1
```

---

## 4. Inicialización de programa y memoria

### 4.1 Memoria de instrucciones

La memoria de instrucciones se implementa en:

```text
src/cpu/instr_mem.sv
```

El programa se carga con `$readmemh` desde `PROGRAM_FILE`. El flujo normal usa archivos `.hex` ubicados en:

```text
programs/hex/
```

Ejemplos disponibles:

| Archivo             | Uso esperado                                      |
| ------------------- | ------------------------------------------------- |
| `program.hex`       | Programa activo por defecto                       |
| `auth_test.hex`     | Prueba de autenticación y bóveda                  |
| `sec_test.hex`      | Prueba de instrucciones de seguridad              |
| `encrypt.hex`       | Rutina de cifrado                                 |
| `decrypt.hex`       | Rutina de descifrado                              |
| `cache_stress.hex`  | Prueba orientada a accesos de memoria/caché       |
| `div_o0.hex`        | Benchmark de división sin optimización            |
| `div_o1.hex`        | Benchmark de división con optimización O1         |
| `div_o2.hex`        | Benchmark de división con optimización O2         |
| `fact_o0.hex`       | Benchmark de factorial sin optimización           |
| `fact_o1.hex`       | Benchmark de factorial con optimización O1        |
| `fact_o2.hex`       | Benchmark de factorial con optimización O2        |
| `primo_o0.hex`      | Benchmark de primalidad sin optimización          |
| `primo_o1.hex`      | Benchmark de primalidad con optimización O1       |
| `primo_o2.hex`      | Benchmark de primalidad con optimización O2       |

### 4.2 Memoria de datos

La memoria de datos puede inicializarse mediante `INITIAL_MEM`. El modelo de memoria principal (`main_mem_model.sv`) también acepta el plusarg:

```text
+INITIAL_MEM=<archivo.mem>
```

Cuando `CACHE_ENABLE=0`, los accesos se dirigen a la memoria de bypass. Cuando `CACHE_ENABLE=1`, se utiliza la jerarquía de caché y la memoria principal modelada.

---

## 5. Detección de fin de programa

El testbench principal detecta el final del programa mediante una instrucción de salto a sí misma:

```systemverilog
localparam logic [31:0] HALT_INSTR = 32'h00000007;
```

Esta codificación representa:

```asm
j 0
```

Cuando el testbench detecta esta instrucción después del llenado inicial del pipeline, espera a que:

1. `cache_stall` esté en cero.
2. El write buffer esté vacío si la caché está habilitada.
3. Transcurran algunos ciclos de drenaje del pipeline.

Después de esto se generan los archivos de salida.

---

## 6. Archivos generados por simulación

`tb_cpu_program.sv` genera los siguientes archivos:

| Archivo                         | Descripción                                      |
| ------------------------------- | ------------------------------------------------ |
| `build/sim/register_dump.txt`   | Estado final del banco de registros              |
| `build/sim/memory_dump.txt`     | Estado final de memoria                          |
| `build/sim/cycle_count.txt`     | Ciclos ejecutados                                |
| `build/sim/metrics.txt`         | Métricas de rendimiento                          |
| `tb_cpu_program.vcd`            | Señales para inspección en GTKWave               |

El dump de memoria se obtiene desde:

| Modo              | Fuente del dump                                  |
| ----------------- | ------------------------------------------------ |
| `CACHE_ENABLE=0`  | `dut.u_cache.bypass_mem`                         |
| `CACHE_ENABLE=1`  | `dut.u_cache.u_main_mem.memory`                  |

En modo caché, el testbench espera a que el write buffer esté vacío antes de escribir el dump para que las evictions sucias hayan alcanzado memoria principal.

---

## 7. Métricas generadas

El archivo:

```text
build/sim/metrics.txt
```

contiene métricas como:

```text
Cycles total
Instructions retired
IPC
Cache stall cycles
Control stall slots
L1 accesses
L1 hits
L1 misses
L1 hit rate
L2 hits
L2 misses
L2 hit rate
Main memory fetches
MM bytes transferred
BW utilization
```

El testbench calcula:

```text
IPC = Instructions retired / Cycles total
L1 hit rate = L1 hits / L1 accesses
L2 hit rate = L2 hits / (L2 hits + L2 misses)
MM bytes transferred = Main memory fetches * 32
BW utilization = MM bytes transferred / Cycles total
```

Cada acceso a memoria principal transfiere una línea completa de caché:

```text
32 bytes = 8 palabras de 32 bits = 256 bits
```

---

## 8. Ejecución con Makefile

### 8.1 Ayuda

```bash
make help
```

Lista los objetivos disponibles del proyecto.

### 8.2 Compilar y ejecutar un testbench unitario

```bash
make sv-run-alu
make sv-run-decoder
make sv-run-cache_l1d
make sv-run-cache_l2
make sv-run-cache_ctrl
make sv-run-cache_hierarchy
make sv-run-main_mem_model
make sv-run-mem_write_buffer
```

El patrón usado es:

```bash
make sv-run-NOMBRE
```

Donde debe existir:

```text
tb/tb_NOMBRE.sv
```

### 8.3 Ejecutar programa completo en CPU

Sin caché:

```bash
make sv-cpu-exec PROGRAM=programs/hex/program.hex CACHE_ENABLE=0 MAX_CYCLES=2000
```

Con caché:

```bash
make sv-cpu-exec PROGRAM=programs/hex/program.hex CACHE_ENABLE=1 MAX_CYCLES=2000
```

Con memoria inicial:

```bash
make sv-cpu-exec PROGRAM=programs/hex/encrypt.hex INITIAL_MEM=build/memory.mem CACHE_ENABLE=1 MAX_CYCLES=5000
```

### 8.4 Comparar ejecución con y sin caché

```bash
make verify-cache-modes PROGRAM=programs/hex/cache_stress.hex MAX_CYCLES=5000
```

Este objetivo ejecuta el programa con `CACHE_ENABLE=0` y `CACHE_ENABLE=1`, guarda ambos dumps de registros y los compara. Si coinciden, se valida que la jerarquía de caché preserva la semántica funcional del programa.

### 8.5 Flujo de cifrado y descifrado

```bash
make encrypt-flow FILE=test2.png ADDRESS=0x1000
make decrypt-flow FILE=enc_test2.png ADDRESS=0x1000
make verify-roundtrip FILE=test2.png
make verify-roundtrip-tea FILE=test2.png
```

Estos objetivos cargan un archivo en memoria, ejecutan rutinas de cifrado/descifrado y extraen el resultado desde el dump final de memoria.

---

## 9. Herramienta de carga de archivos (`tools/load_file.py`)

### 9.1 Funcionalidad

Convierte un archivo binario externo en un archivo `.mem` compatible con `$readmemh`.

Interfaz:

```bash
./tools/load_file.py --input <FILE> --output <FILE.mem> --address <HEX>
```

Ejemplo:

```bash
./tools/load_file.py --input examples/test2.png --output build/memory.mem --address 0x1000
```

### 9.2 Formato del archivo `.mem`

El formato usa una cabecera de dirección:

```text
@1000
DEADBEEF
CAFEBABE
12345678
```

La dirección se interpreta como dirección de palabra para `$readmemh`.

### 9.3 Manejo de archivos no múltiplos de 4

Si el archivo no tiene tamaño múltiplo de 4 bytes, se rellena con ceros al final hasta completar la última palabra. El tamaño original se conserva para que `extract_data.py` pueda reconstruir exactamente la cantidad de bytes requerida.

---

## 10. Herramienta de extracción (`tools/extract_data.py`)

### 10.1 Funcionalidad

Reconstruye un archivo binario a partir del dump de memoria generado por la simulación.

Interfaz:

```bash
./tools/extract_data.py --memory <DUMP> --address <HEX> --size <BYTES> --output <FILE>
```

Ejemplo:

```bash
./tools/extract_data.py --memory build/sim/memory_dump.txt --address 0x1000 --size 4096 --output build/out/enc_test2.png
```

### 10.2 Pseudocódigo

```text
1. Leer memory_dump.txt como palabras de 32 bits
2. Calcular índice inicial a partir de address / 4
3. Leer ceil(size / 4) palabras
4. Convertir palabras a bytes
5. Truncar a size bytes
6. Escribir archivo de salida
```

---

## 11. Flujo end-to-end de cifrado de archivo

```text
examples/test2.png
      │
      │ load_file.py --address 0x1000
      ▼
build/memory.mem
      │
      │ $readmemh mediante INITIAL_MEM
      ▼
Simulación con cpu_top + cache_hierarchy
      │
      │ HALT + dump de memoria
      ▼
build/sim/memory_dump.txt
      │
      │ extract_data.py --address 0x1000 --size <bytes>
      ▼
build/out/enc_test2.png
```

La validación de roundtrip compara el archivo original con el archivo descifrado final:

```bash
cmp examples/test2.png build/out/dec_enc_test2.png
```

---

## 12. Testbenches específicos

| Testbench                   | Componente validado                        | Casos principales                                                          |
| --------------------------- | ------------------------------------------ | -------------------------------------------------------------------------- |
| `tb_alu.sv`                 | ALU                                        | Operaciones aritméticas/lógicas y flags                                    |
| `tb_decoder.sv`             | Decoder                                    | Extracción de campos e inmediatos                                          |
| `tb_control_unit.sv`        | Unidad de control                          | Señales para cada clase de instrucción                                     |
| `tb_register_file.sv`       | Banco de registros                         | Lectura, escritura, `x0`, `x30` constante                                  |
| `tb_pc.sv`                  | PC                                         | Reset y actualización                                                      |
| `tb_pc_adder.sv`            | Sumador de PC                              | `PC + 4` y `PC + imm`                                                      |
| `tb_instr_mem.sv`           | Memoria de instrucciones                   | Lectura de instrucciones por PC                                            |
| `tb_data_mem.sv`            | Memoria de datos simple                    | Lectura/escritura de palabras                                              |
| `tb_key_vault.sv`           | Bóveda de llaves                           | Acceso autorizado/no autorizado                                            |
| `tb_sec_alu.sv`             | ALU de seguridad                           | `ADDK`, `XORK`, `TEA`, bloqueo sin auth, zero-attack                       |
| `tb_main_mem_model.sv`      | Memoria principal                          | Latencia exacta de 25 ciclos, read/write, transacciones consecutivas       |
| `tb_mem_write_buffer.sv`    | Write buffer                               | Enqueue, full, drenaje, conflictos read-after-write                        |
| `tb_cache_l1d.sv`           | Caché L1-D                                 | Reset, fill, hit, miss, write-hit, dirty victim, LRU                       |
| `tb_cache_l2.sv`            | Caché L2                                   | Fill, hit, miss, write-line, dirty victim, pseudo-LRU                      |
| `tb_cache_ctrl.sv`          | Controlador de caché                       | Bypass, L1 hit, L1 miss, L2 hit/miss, write-allocate, dirty evictions      |
| `tb_cache_hierarchy.sv`     | Jerarquía completa                         | Bypass, cold miss, hit posterior, sets múltiples, write-hit, reset, WB     |
| `tb_cpu_top.sv`             | Integración básica del CPU                 | Flujo de instrucciones y write back                                        |
| `tb_cpu_program.sv`         | Ejecución completa de programas            | Programas `.hex`, HALT, métricas, dumps, comparación con/sin caché         |

---

## 13. Visualización con GTKWave

Los testbenches generan archivos `.vcd`. Señales recomendadas para inspección:

| Señal                                      | Uso                                              |
| ------------------------------------------ | ------------------------------------------------ |
| `dut.if_pc_cur`                            | PC actual                                        |
| `dut.if_instr`                             | Instrucción en IF                                |
| `dut.cache_stall`                          | Stalls generados por la jerarquía de caché       |
| `dut.if_id_reg`                            | Registro IF/ID                                   |
| `dut.id_ex_reg`                            | Registro ID/EX                                   |
| `dut.ex_mem_reg`                           | Registro EX/MEM                                  |
| `dut.mem_wb_reg`                           | Registro MEM/WB                                  |
| `dut.u_cache.u_l1d.valid`                  | Validez de líneas L1                             |
| `dut.u_cache.u_l1d.dirty`                  | Dirty bits L1                                    |
| `dut.u_cache.u_l2.valid`                   | Validez de líneas L2                             |
| `dut.u_cache.u_l2.dirty`                   | Dirty bits L2                                    |
| `dut.u_cache.u_cache_ctrl.state`           | Estado de la FSM del controlador de caché        |
| `dut.u_cache.u_main_mem.active`            | Transacción activa en memoria principal          |
| `dut.u_cache.u_write_buffer.empty`         | Estado del write buffer                          |

---

## 14. Resumen del modelo

| Recurso             | Cómo se modela                                      | Inicialización / salida                       |
| ------------------- | --------------------------------------------------- | --------------------------------------------- |
| Banco de registros  | 32 registros de 32 bits, `x0` cero, `x30` constante | Inicializado en cero                          |
| IMEM                | Array de instrucciones de 32 bits                   | `$readmemh(PROGRAM_FILE)`                     |
| L1-D                | 4 KB, 2-way, línea de 32 bytes                      | Inválida en reset                             |
| L2                  | 16 KB, 4-way, línea de 32 bytes                     | Inválida en reset                             |
| Write buffer        | FIFO de líneas dirty hacia memoria principal        | Vacío en reset                                |
| Memoria principal   | Array de palabras de 32 bits                        | `$readmemh(INITIAL_MEM)` opcional             |
| Bóveda              | 16 palabras de 32 bits                              | Protegida por `auth_bit`                      |
| Métricas            | Contadores internos                                 | Exportadas a `build/sim/metrics.txt`         |
| Dumps               | Registros y memoria final                           | `register_dump.txt`, `memory_dump.txt`        |

---

## 15. Notas y limitaciones

- El modelo de memoria principal usa latencia multiciclo en el mismo reloj de simulación. Esto reproduce el costo temporal de memoria externa, aunque no implementa un cruce físico explícito de dominios de reloj.
- Los contadores de caché actuales se reportan de forma agregada. El desglose read/write puede añadirse con contadores separados condicionados por `mem_read` y `mem_write`.
- `CACHE_ENABLE=0` no elimina `cache_hierarchy.sv`; simplemente activa la ruta de bypass.
- Para comparar correctamente memoria en modo caché, el testbench espera a que `wb_empty = 1` antes de generar el dump.
- Si el programa no contiene una instrucción `j 0` como HALT, la simulación termina por `MAX_CYCLES`.