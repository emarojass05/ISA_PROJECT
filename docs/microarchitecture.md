# Microarquitectura — SecuRISC-32

> **Versión 1.0** · CE-4301 · I-2026

## 1. Visión general

SecuRISC-32 implementa un **datapath multiciclo de 5 etapas** (sin pipeline en la versión base) sobre una arquitectura **Harvard** (memorias de instrucciones y datos separadas). La separación facilita la simulación con `iverilog` y permite mapear directamente el código del programa a una ROM y los datos del usuario a una RAM independiente.

| Aspecto                | Decisión                                       |
|------------------------|------------------------------------------------|
| Tipo de control        | FSM multiciclo (no pipeline en V1)             |
| Etapas                 | IF → ID → EX → MEM → WB                        |
| Modelo de memoria      | Harvard (IMEM separada de DMEM)                |
| Tamaño DMEM            | 64 KB (16384 × 32 b)                           |
| Tamaño IMEM            | 16 KB (4096 instrucciones)                     |
| Bóveda                 | 4 × 128 bits, módulo aislado                   |
| Unidad funcional cripto| `tea_unit` dedicada (combinacional)            |

> **Justificación de multiciclo vs. pipeline:** Para una primera implementación educativa, multiciclo es más simple de depurar y no introduce hazards. La estructura modular permite migrar a pipeline en una versión futura sin reescribir los módulos individuales.

---

## 2. Diagrama de bloques

```
                         ┌─────────────────────────────────────────┐
                         │              CONTROL UNIT (FSM)         │
                         │   IF → ID → EX → MEM → WB → IF ...      │
                         └────┬───────┬─────┬────────┬────────┬────┘
                              │       │     │        │        │
                   reg_we     │       │   alu_op  mem_we   wb_sel
                   pc_src     │       │   tea_op  mem_size  ksel_we
                              ▼       ▼     ▼        ▼        ▼
  ┌──────────┐         ┌────────┐ ┌─────┐ ┌────┐ ┌────────┐ ┌──────┐
  │   IMEM   │ instr   │ DECODE │ │ REG │ │ALU │ │  DMEM  │ │ WB   │
  │ (ROM 16K)│────────▶│ format │ │FILE │ │32-b│ │ 64 KB  │ │ MUX  │
  └────┬─────┘         │ opcode │ │16x32│ │     │ │ B/H/W │ └──┬───┘
       ▲               └────────┘ └──┬──┘ └──┬─┘ └────┬───┘    │
       │                              │       │       │        │
       │                              │   ┌───┴───────┴──┐     │
   ┌───┴───┐                          │   │  ALU/MEM bus  │    │
   │  PC   │◀────────── pc_next ──────┴───┴───────────────┴────┘
   └───────┘                                       │
                                                   │
                  ┌────────────────────┐           │
                  │   KEY VAULT (RoT)  │           │
                  │   4 × 128 bits     │           │
                  │   + AUTH FSM       │           │
                  └─────────┬──────────┘           │
                            │ k0..k3 (128 b)       │
                            ▼                      │
                  ┌────────────────────┐           │
                  │     TEA UNIT       │           │
                  │  ((rs1<<4)+Kx) ^   │◀──────────┘
                  │  (rs1+rs2)     ^   │ rs1, rs2
                  │  ((rs1>>5)+Ky)     │
                  └─────────┬──────────┘
                            │ tea_result (32 b)
                            ▼
                       (al WB MUX)
```

> Diagrama equivalente en `docs/img/block_diagram.svg`.

---

## 3. Etapas del datapath

### 3.1 Instruction Fetch (IF)

```
PC ────▶ IMEM ────▶ instr (32 b)
 │                       │
 └──── PC + 4 ───────────┘
```

- **PC** (`rtl/core/pc.sv`): registro de 32 bits con reset síncrono.
- **IMEM** (`rtl/memory/imem.sv`): ROM combinacional, inicializada con `$readmemh("program.mem", mem)` en simulación.
- Salida: instrucción lista al final del ciclo.

### 3.2 Instruction Decode (ID)

```
instr ──┬─▶ opcode → CONTROL UNIT → señales de control
        ├─▶ rs1, rs2 → REGFILE.read → A, B
        ├─▶ rd → REGFILE.waddr (latched)
        ├─▶ imm → SIGN-EXT → imm32
        └─▶ ksel/half → KSEL_REG, TEA_HALF
```

- **REGFILE** (`rtl/core/regfile.sv`): banco de 16 × 32 b dual-read / single-write. R0 hardwired a 0 mediante un mux de bypass.
- **CONTROL UNIT** (`rtl/core/control_unit.sv`): FSM principal + decodificador combinacional. Genera todas las señales de control derivadas de `opcode` y `funct`.

### 3.3 Execute (EX)

Caminos posibles:

```
A ──┬──▶ ALU ─────────▶ alu_out
    │   (op = ADD/SUB/AND/OR/XOR/NOT/SLL/SRL/SRA/SLT/CMP)
    │
    ├──▶ TEA_UNIT ────▶ tea_out      (opcode = TEAMIX)
    │      ▲
    │      │ k0..k3 desde KEY_VAULT[KSEL]
    │
    └──▶ ADDR_GEN ────▶ ea           (LW/SW/JALR)
        ea = A + imm32
```

- **ALU** (`rtl/core/alu.sv`): combinacional, 32 bits, opera sobre `A` y `B` o `imm32`.
- **TEA_UNIT** (`rtl/crypto/tea_unit.sv`): combinacional. Recibe `rs1` (`A`), `rs2` (`B`), `half` y dos sub-llaves `K_a`, `K_b` provenientes de la bóveda.
- **Branch unit**: comparador combinacional sobre `A` y `B` que decide `branch_taken` para el next-PC mux.

### 3.4 Memory Access (MEM)

```
Para LOAD:    DMEM[ea] ──▶ load_data
Para STORE:   DMEM[ea] ◀── B (con mask para B/H/W)
Otras:        bypass
```

- **DMEM** (`rtl/memory/dmem.sv`): 16384 × 32 b. Soporta accesos de byte/halfword/word vía señales `mem_size` y máscaras de escritura.

### 3.5 Write Back (WB)

```
                 ┌─ alu_out
                 ├─ tea_out
WB MUX ──────────┼─ load_data
                 ├─ PC + 4   (para JAL/JALR)
                 └─ DELTA    (para TEADELTA)
                 │
                 └──▶ REGFILE[rd]
```

---

## 4. FSM del control unit

```
                            ┌───────────────┐
                  reset    │     IF        │
                  ───────▶ │  IR ← IMEM[PC]│
                            │  PC ← PC + 4 │
                            └──────┬────────┘
                                   │
                                   ▼
                            ┌───────────────┐
                            │      ID       │
                            │  decode op    │
                            │  read regs    │
                            └──────┬────────┘
                                   │
                ┌──────────────────┼──────────────────┐
                │                  │                  │
        ALU R/I │           Mem L/S │            Branch│           Cripto
                ▼                  ▼                  ▼                ▼
        ┌──────────┐         ┌──────────┐    ┌──────────┐      ┌──────────┐
        │   EX     │         │   EX     │    │   EX     │      │   EX     │
        │ ALU calc │         │ ea calc  │    │ compare  │      │TEA/Vault │
        └────┬─────┘         └────┬─────┘    └────┬─────┘      └────┬─────┘
             │                    │               │                  │
             │                    ▼               ▼                  │
             │              ┌──────────┐    ┌──────────┐             │
             │              │   MEM    │    │ NEXT-PC  │             │
             │              │ R/W DMEM │    │  update  │             │
             │              └────┬─────┘    └────┬─────┘             │
             │                   │               │                   │
             ▼                   ▼               │                   ▼
        ┌──────────┐         ┌──────────┐        │              ┌──────────┐
        │    WB    │         │    WB    │        │              │    WB    │
        │ alu→reg  │         │ load→reg │        │              │ tea→reg  │
        └────┬─────┘         └────┬─────┘        │              └────┬─────┘
             └─────┬──────────────┴──────────────┴───────────────────┘
                   │
                   ▼
                  IF (siguiente instrucción)
```

Si en cualquier etapa se levanta `EXC ≠ 0`, la FSM transita al estado **HALT** (excepción no recuperable en V1).

---

## 5. Módulos SystemVerilog

### 5.1 `rtl/pkg/secur_pkg.sv`

Define `parameter`s y `enum`s globales:

```systemverilog
package secur_pkg;
  parameter int XLEN     = 32;
  parameter int IMEM_SZ  = 4096;     // palabras
  parameter int DMEM_SZ  = 16384;    // palabras (= 64 KB)
  parameter int NUM_GPR  = 16;
  parameter int VAULT_N  = 4;
  parameter int KEY_W    = 128;

  parameter logic [31:0] TEA_DELTA = 32'h9E3779B9;

  typedef enum logic [5:0] {
    OP_ALU_R = 6'h00, OP_ALU_I = 6'h01, OP_LUI = 6'h02,
    OP_LOAD  = 6'h04, OP_STORE = 6'h05,
    OP_BR    = 6'h08, OP_JAL   = 6'h09, OP_JALR = 6'h0A,
    OP_VAULT = 6'h10, OP_TEA   = 6'h11, OP_SYS  = 6'h3F
  } opcode_e;

  typedef enum logic [3:0] {
    ALU_ADD, ALU_SUB, ALU_AND, ALU_OR, ALU_XOR,
    ALU_NOT, ALU_SLL, ALU_SRL, ALU_SRA, ALU_SLT, ALU_SLTU
  } alu_op_e;
endpackage
```

### 5.2 `rtl/core/alu.sv`

```systemverilog
module alu import secur_pkg::*; (
    input  logic [XLEN-1:0] a, b,
    input  alu_op_e         op,
    input  logic [4:0]      shamt,
    output logic [XLEN-1:0] y,
    output logic            z, n, c, v
);
  // case sobre 'op' produce 'y'; flags se computan en paralelo.
endmodule
```

### 5.3 `rtl/core/regfile.sv`

```systemverilog
module regfile import secur_pkg::*; (
    input  logic clk, rst_n,
    input  logic [3:0] raddr1, raddr2, waddr,
    input  logic [XLEN-1:0] wdata,
    input  logic we,
    output logic [XLEN-1:0] rdata1, rdata2
);
  logic [XLEN-1:0] regs [NUM_GPR];
  // R0 hardwired a 0
  assign rdata1 = (raddr1 == 0) ? '0 : regs[raddr1];
  assign rdata2 = (raddr2 == 0) ? '0 : regs[raddr2];
  always_ff @(posedge clk) if (we && waddr != 0) regs[waddr] <= wdata;
endmodule
```

### 5.4 `rtl/crypto/key_vault.sv`

```systemverilog
module key_vault import secur_pkg::*; (
    input  logic clk, rst_n,
    input  logic auth,                   // SR.AU
    // puerto de escritura (KLOAD)
    input  logic kload_en,
    input  logic [1:0] kload_idx,
    input  logic [KEY_W-1:0] kload_data,
    // puerto de lectura interno (solo a tea_unit)
    input  logic [1:0] ksel,
    output logic [KEY_W-1:0] active_key,
    // clear
    input  logic kclr_en, [1:0] kclr_idx,
    output logic access_violation
);
  logic [KEY_W-1:0] vault [VAULT_N];
  // …operación protegida por 'auth'.
  // active_key sólo se conecta a tea_unit, NO al WB MUX.
endmodule
```

> **Aislamiento físico:** la salida `active_key` **no se rutea** al `wb_mux` ni al `dmem`; sólo al `tea_unit`. Esto se verifica con un linter (`verilator --xcheck`) y con un test que intenta conectarla.

### 5.5 `rtl/crypto/tea_unit.sv`

```systemverilog
module tea_unit import secur_pkg::*; (
    input  logic [XLEN-1:0]  a,        // rs1
    input  logic [XLEN-1:0]  b,        // rs2 (sum)
    input  logic             half,     // 0 = K[0..1]; 1 = K[2..3]
    input  logic [KEY_W-1:0] key,
    output logic [XLEN-1:0]  y
);
  logic [31:0] ka, kb;
  assign {ka, kb} = half ? key[63:0] : key[127:64];
  assign y = ((a << 4) + ka) ^ (a + b) ^ ((a >> 5) + kb);
endmodule
```

### 5.6 `rtl/core/control_unit.sv`

FSM en `always_ff` + decode combinacional en `always_comb` que produce:
- `pc_src`, `pc_we`
- `reg_we`, `wb_sel`
- `alu_op`, `alu_src_b`
- `mem_we`, `mem_size`
- `tea_en`, `tea_half`
- `vault_op` (`KLOAD`/`KSEL`/`KCLR`)
- `auth_set`/`auth_clr`/`auth_check`

### 5.7 `rtl/top.sv`

Conecta `cpu`, `imem`, `dmem`. Expone señales de debug (`dbg_pc`, `dbg_halt`) para los testbenches.

---

## 6. Flujo de datos: ejecución de TEAMIX

Trazado paso a paso de `TEAMIX R7, R4, R5, 0`:

| Ciclo | Etapa | Acción                                                        |
|-------|-------|---------------------------------------------------------------|
| 1     | IF    | `IR ← IMEM[PC]`; `PC ← PC + 4`                                |
| 2     | ID    | `op = OP_TEA`, `funct = MIX`, `half = 0`; lee `R4 → A`, `R5 → B`; control levanta `tea_en`, comprueba `SR.AU` |
| 3     | EX    | `key_vault.active_key ← Vault[KSEL]`; `tea_unit.y = ((A<<4)+K[0]) ^ (A+B) ^ ((A>>5)+K[1])` |
| 4     | WB    | `R7 ← tea_unit.y` vía `wb_sel = TEA`                          |

> Si `SR.AU = 0`, en la etapa **ID** se setea `EXC = 001`, se omite la escritura de `R7`, se transita a **HALT** y se imprime un mensaje en simulación.

---

## 7. Mapa de memoria

```
0x0000_0000  ─┐
              │   IMEM (ROM, 16 KB)        instrucciones del programa
0x0000_3FFF  ─┘

0x0000_4000  ─┐
              │   DMEM (RAM, 64 KB)        datos / archivos cargados
0x0001_3FFF  ─┘

(las llaves NO ocupan espacio direccionable: viven en el módulo key_vault)
```

---

## 8. Justificación de decisiones

| Decisión                       | Trade-off                                              | Por qué                              |
|--------------------------------|--------------------------------------------------------|--------------------------------------|
| Instrucciones de 32 b fijas    | +código, –complejidad de decoder                       | Decode trivial, sin alineación var.  |
| Multiciclo (no pipeline) en V1 | –throughput, +simplicidad                              | Educativo, debuggeable               |
| Harvard                        | +duplica memoria, +simple                              | Permite `$readmemh` separado         |
| 16 GPRs                        | +código vs. 8, –bits vs. 32                            | Balance común RISC educativo         |
| `TEAMIX` half-round            | +ciclos vs. round-completo, –área                      | 1 sumador + 2 shifters fijos baratos |
| Bóveda fuera del bus de datos  | +seguridad, –lógica de mux                             | Cumple aislamiento estricto          |
| `LOGIN` con password de 32 b   | –seguridad real (32 b es débil para producción)        | Es un proyecto educativo, simulado   |