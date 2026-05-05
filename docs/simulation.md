# Modelado de Simulación — SecuRISC-32


## 1. Objetivo del modelo de simulación

Este documento describe **cómo se materializa** la microarquitectura de SecuRISC-32 dentro de una simulación con **Icarus Verilog**, cómo se inicializan los recursos del procesador (memorias, banco de registros, bóveda), cómo se ejecuta el ciclo de instrucción, y cómo el simulador interactúa con la **herramienta de carga de archivos** y la **utilidad de extracción**.

El modelo sigue una filosofía de **simulación funcional ciclo a ciclo**, no time-accurate. Cada estado de la FSM avanza con un flanco de reloj y produce salidas observables (PC, registros, RAM, estado de la bóveda) que el testbench inspecciona y vuelca a archivos de salida.

---

## 2. Estructura del top de simulación

```
tb/tb_top.sv
   │
   ├── instancia top (rtl/top.sv)
   │       ├── cpu        ← datapath + control
   │       ├── imem       ← ROM, $readmemh("program.mem")
   │       ├── dmem       ← RAM, $readmemh("memory.mem") (opcional)
   │       └── key_vault  ← bóveda, reset = todas las llaves a 0
   │
   ├── generador de reloj (period = 10 ns)
   ├── reset (low por 2 ciclos al inicio)
   ├── monitor: $monitor de PC, IR, registros relevantes
   └── al ver dbg_halt = 1:
        ├── dump de DMEM a "memory_dump.txt"
        └── $finish
```

### 2.1 Inicialización

```systemverilog
initial begin
    // 1. Cargar programa en IMEM
    $readmemh("program.mem", top.imem.mem);

    // 2. Cargar datos del usuario (archivo) en DMEM si existe
    if ($value$plusargs("DATA_FILE=%s", data_file))
        $readmemh(data_file, top.dmem.mem);

    // 3. Configurar señales
    rst_n = 0; clk = 0;
    #20 rst_n = 1;

    // 4. Habilitar volcado de waveforms
    $dumpfile("sim/tb_top.vcd");
    $dumpvars(0, tb_top);
end
```

### 2.2 Volcado al finalizar

```systemverilog
always @(posedge clk) begin
    if (top.cpu.dbg_halt) begin
        $display("==== Simulation HALT @ time %0t ====", $time);
        // Volcar DMEM a archivo de texto
        $writememh("sim/memory_dump.txt", top.dmem.mem);
        // Volcar registros
        for (int i = 0; i < 16; i++)
            $display("R%0d = 0x%08h", i, top.cpu.regfile.regs[i]);
        $finish;
    end
end
```

---

## 3. Modelado de los componentes

### 3.1 Banco de registros

```systemverilog
logic [31:0] regs [16];
```

- 16 entradas inferidas como **registros LUT** en la simulación (no array de flip-flops sintetizable; en simulación es indistinguible).
- `R0` siempre se lee como `0` con un mux combinacional, y las escrituras a `R0` se ignoran con la condición `if (we && waddr != 0)`.
- Dual-port read combinacional: ambas salidas `rdata1`/`rdata2` están disponibles en el mismo ciclo en que se decodifica la instrucción.
- En simulación se inicializan a `0` con `for (int i=0; i<16; i++) regs[i] = 0;` dentro del `initial` del banco para evitar `X` propagados.

### 3.2 Memoria RAM (DMEM)

```systemverilog
logic [31:0] mem [16384];      // 64 KB
```

- Direccionada por palabra: `addr[15:2]` indexa el array.
- Soporta accesos a byte/halfword vía máscara generada en el control:
```systemverilog
  case (mem_size)
    BYTE: write_mask = 4'b0001 << addr[1:0];
    HALF: write_mask = (addr[1]) ? 4'b1100 : 4'b0011;
    WORD: write_mask = 4'b1111;
  endcase
```
- En simulación se carga al inicio con `$readmemh("memory.mem", mem)` si se proporciona el archivo desde `+DATA_FILE=...`.
- Al finalizar la simulación, se vuelca con `$writememh("memory_dump.txt", mem)` para que la herramienta de extracción la procese.

### 3.3 Bóveda de llaves

```systemverilog
logic [127:0] vault [4];
```

- 4 entradas de 128 bits.
- En reset se inicializan a `'0`, garantizando que la simulación no parta con llaves residuales.
- La señal de salida `active_key` se conecta **únicamente** a `tea_unit`; nunca a la red de write-back ni al puerto de DMEM. Esto se verifica con un `assert` SVA:
```systemverilog
  assert property (@(posedge clk) wb_sel != WB_KEY)
      else $fatal("Vault leak: active_key reached WB MUX");
```
- El estado de autenticación se modela como un único bit `auth` mantenido en el `status_reg` y consultado por la FSM antes de toda operación de bóveda/TEA.

### 3.4 Unidad funcional TEA

```systemverilog
assign tea_y = ((rs1 << 4) + Ka) ^ (rs1 + rs2) ^ ((rs1 >> 5) + Kb);
```

Combinacional pura. Latencia = `0` ciclos lógicos: la salida está estable al final del mismo ciclo de **EX**. El testbench `tb_tea_unit.sv` la valida contra el modelo de referencia en Python (`tools/tea_reference.py`) usando vectores aleatorios.

### 3.5 Status Register

Se modela como un registro de 32 bits con escritura selectiva:
- Las flags `Z/N/C/V` se actualizan **sólo** por instrucciones que las afectan (ver columna "Flags" en `isa.md`).
- El bit `AU` se modifica únicamente por `LOGIN`/`LOGOUT` o por una excepción que lo limpia automáticamente.

---

## 4. Ciclo de ejecución (modelo conceptual)

```
loop forever:
    1. IF:    fetch instrucción desde imem[PC>>2]; PC ← PC + 4
    2. ID:    decode → señales de control + lectura de regfile
    3. EX:    una de:
                 - alu(a, b)             si ALU
                 - tea_unit(a, b, half)  si TEA  → requiere AU=1
                 - addr = a + imm        si LW/SW/JALR
                 - branch_taken          si BR
              si EXC ≠ 0 → goto HALT
    4. MEM:   acceso a dmem si LW/SW; bypass si no
    5. WB:    write-back según wb_sel a regfile[rd] (excepto rd=R0)
    6. NEXT:  PC ← pc_src ? branch_target : PC + 4
```

El testbench `tb_top.sv` instrumenta este ciclo imprimiendo en cada paso:

```
[CYCLE 042] IF  : PC=0x00000010  IR=0x10300004  (KLOAD R0, R3, ksel=0)
[CYCLE 043] ID  : op=VAULT funct=KLOAD  AU=1  → permitido
[CYCLE 044] EX  : ea = R3 = 0x4000
[CYCLE 045] MEM : leyendo 128b desde DMEM[0x4000..0x400F]
[CYCLE 046] WB  : Vault[0] ← 0x0123456789ABCDEFFEDCBA9876543210
```

---

## 5. Herramienta de carga de archivos (`tools/load_file.py`)

### 5.1 Pseudocódigo

```
def load_file(input_path, output_path, address):
    1. Leer archivo en modo binario
    2. Determinar tamaño en bytes y mostrarlo
    3. Detectar tipo MIME (módulo 'mimetypes')
    4. Empacar bytes en palabras de 32 bits little-endian
    5. Para cada palabra W_i:
         escribir línea hexadecimal en output_path
         con offset (address + 4*i) como comentario
    6. Imprimir resumen: dirección inicial, final, tamaño
```

### 5.2 Formato del archivo `.mem`

El simulador usa `$readmemh`, que acepta:

```
@1000     // dirección hex del primer dato (palabras desde 0x1000)
DEADBEEF
CAFEBABE
12345678
...
```

`load_file.py` produce esta cabecera `@<addr>` y luego una palabra por línea.

### 5.3 Manejo de archivos no múltiplos de 4

Se rellenan con `0x00` al final hasta completar la última palabra. El usuario recibe el tamaño exacto del archivo original para que pueda guardarlo en un registro/constante y procesarlo correctamente desde el programa.

### 5.4 Interfaz CLI

```
load_file.py --input <FILE> --output <FILE.mem> --address <HEX>
```

Salida típica:

```
[load_file] Tipo detectado : image/jpeg
[load_file] Tamaño         : 4096 bytes (1024 palabras)
[load_file] Rango de carga : 0x00002000 — 0x00002FFC
[load_file] Salida         : sim/memory.mem
```

---

## 6. Herramienta de extracción (`tools/extract_data.py`)

### 6.1 Funcionalidad

Lee `memory_dump.txt` (generado por `$writememh` al final de la simulación) y reconstruye un binario:

```
extract_data.py --memory <DUMP> --address <HEX> --size <BYTES> --output <FILE>
```

### 6.2 Pseudocódigo

```
def extract(dump, addr, size, out):
    1. Parsear dump → array de palabras de 32 b
    2. start_word = addr / 4
    3. n_words   = ceil(size / 4)
    4. Tomar palabras [start_word .. start_word+n_words]
    5. Convertir de palabras de 32 b LE a stream de bytes
    6. Truncar a 'size' bytes y escribir en 'out'
```

Salida típica:

```
[extract_data] Leyendo  : sim/memory_dump.txt
[extract_data] Rango    : 0x00001000 — 0x00001FFF (4096 bytes)
[extract_data] Escrito  : hello.enc
```

---

## 7. Flujo end-to-end de cifrado de archivo

```
┌─────────────────┐
│ examples/       │  hello.txt (1024 bytes)
│   input/        │
└────────┬────────┘
         │ load_file.py --address 0x1000
         ▼
┌─────────────────┐
│ sim/memory.mem  │  @1000 + 256 palabras
└────────┬────────┘
         │ $readmemh en testbench
         ▼
┌─────────────────┐    programa (programs/06_file_encrypt.s):
│  Simulación     │      LOGIN R1
│  iverilog       │      KLOAD ksel=0, addr_key
│                 │      KSEL  0
│  CPU ejecuta    │ ─▶   loop: TEAMIX … sobre cada bloque de 64 b
│                 │      HALT
└────────┬────────┘
         │ $writememh al detectar HALT
         ▼
┌─────────────────┐
│ memory_dump.txt │  estado final de DMEM (incluye datos cifrados)
└────────┬────────┘
         │ extract_data.py --address 0x1000 --size 1024
         ▼
┌─────────────────┐
│   hello.enc     │  archivo cifrado de 1024 bytes
└─────────────────┘
```

La validación cruzada se realiza ejecutando `tea_reference.py decrypt --in hello.enc --key <KEY>` y comparando con `hello.txt` original (`diff`).

---

## 8. Testbenches específicos

| Testbench               | Estrategia                                                                 |
|-------------------------|----------------------------------------------------------------------------|
| `tb_alu.sv`             | Tabla de vectores `(a, b, op) → (y, flags)` + 1000 vectores aleatorios     |
| `tb_regfile.sv`         | Escribe/lee todas las posiciones; verifica R0 hardwired                    |
| `tb_dmem.sv`            | Patrón "marcha" + accesos B/H/W; chequea endianness                        |
| `tb_key_vault.sv`       | KLOAD con AU=0 → debe levantar excepción; con AU=1 → carga correcta        |
| `tb_tea_unit.sv`        | DUT vs. modelo Python sobre 10 000 vectores aleatorios                     |
| `tb_tea_fullblock.sv`   | Cifrado completo de un bloque; descifrado debe dar el bloque original      |
| `tb_top.sv`             | Programa real (`programs/06_file_encrypt.s`) sobre `hello.txt` cargado     |

Cada testbench:
1. Genera reloj y reset.
2. Carga el `.mem` correspondiente.
3. Ejecuta hasta `HALT` o un timeout (`#1_000_000`).
4. Compara registros/memoria contra el oráculo (`examples/expected/`).
5. Imprime `PASS`/`FAIL` y termina con `$finish(0)` o `$finish(1)`.

---

## 9. Visualización con GTKWave

Cada testbench produce un `sim/<tb>.vcd`. Señales recomendadas para inspección:

- `top.cpu.pc.PC`
- `top.cpu.regfile.regs[*]`
- `top.cpu.control_unit.state`
- `top.cpu.alu.y` y flags
- `top.cpu.tea_unit.y`
- `top.key_vault.vault[*]`
- `top.cpu.status_reg.SR`


---

## 10. Resumen del modelo

| Recurso          | Cómo se modela                                                | Inicialización                  |
|------------------|---------------------------------------------------------------|---------------------------------|
| Banco de regs    | Array `logic [31:0] regs[16]`, R0 hardwired                   | Todos a 0 en reset              |
| RAM 64 KB        | Array `logic [31:0] mem[16384]`                               | `$readmemh("memory.mem")`       |
| ROM instr.       | Array `logic [31:0] mem[4096]`                                | `$readmemh("program.mem")`      |
| Bóveda           | Array `logic [127:0] vault[4]`, aislado del bus               | Todas a 0 en reset              |
| Status Register  | `logic [31:0] SR`                                             | 0 en reset (AU=0)               |
| TEA unit         | Lógica combinacional (sin estado)                             | —                               |
| FSM control      | `enum logic [2:0] state` con transiciones síncronas           | `IF` en reset                   |
| I/O usuario      | `$readmemh` (entrada) + `$writememh` (salida) + scripts Py    | —                               |