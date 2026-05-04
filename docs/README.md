# SecuRISC-32 — Procesador RISC con Extensiones de Seguridad

> Proyecto Grupal I — CE-4301 Arquitectura de Computadores I
> Instituto Tecnológico de Costa Rica · Escuela de Ingeniería en Computadores
> I Semestre 2026

SecuRISC-32 es una **ISA tipo RISC de 32 bits** diseñada e implementada en SystemVerilog para acelerar aplicaciones de **seguridad informática**. Incluye soporte nativo para el algoritmo de cifrado de bloque **TEA (Tiny Encryption Algorithm)** y una **bóveda de llaves criptográficas (Root of Trust)** con control de acceso por autenticación. El procesador se simula con **Icarus Verilog (`iverilog`)** sin necesidad de síntesis en FPGA.

---

## Propósito del proyecto

Aplicar los conceptos de arquitectura de computadores en el diseño e implementación de:

1. Una **ISA RISC propia** con instrucciones aritméticas, lógicas, de memoria y de control de flujo.
2. Extensiones criptográficas para **acelerar TEA** (cifrado/descifrado) con clave de 128 bits, bloques de 64 bits y 32 rondas.
3. Una **bóveda de llaves** (Key Vault) que almacena al menos 4 llaves de 128 bits, accesible solo por instrucciones específicas y protegida por un mecanismo de autenticación.
4. Una **herramienta de carga/extracción** que permite inyectar archivos arbitrarios (texto, imágenes, binarios) en la RAM simulada y recuperar los datos cifrados a un archivo de salida.

---

## Dependencias

| Herramienta      | Versión mínima | Uso                                              |
|------------------|----------------|--------------------------------------------------|
| Icarus Verilog   | 11.0+          | Compilación y simulación                         |
| GTKWave          | 3.3+           | Visualización de waveforms (`.vcd`)              |
| Python           | 3.9+           | Herramienta de carga/extracción de archivos      |
| GNU Make         | 4.0+           | Automatización de la compilación y testbenches   |
| Git              | 2.30+          | Control de versiones                             |

### Instalación rápida (Ubuntu/Debian)

```bash
sudo apt update
sudo apt install iverilog gtkwave python3 python3-pip make git
```

### Instalación en macOS

```bash
brew install icarus-verilog gtkwave python3 make git
```

### Instalación en Windows

Se recomienda usar **WSL2** (Ubuntu) y seguir las instrucciones de Linux.

---

## Estructura del repositorio

```
SecuRISC-32/
├── README.md                  ← este archivo
├── Makefile                   ← compila y ejecuta todos los testbenches
├── LICENSE
├── .gitignore
│
├── docs/                      ← Documentación de diseño (15%)
│   ├── isa.md                 ← Arquitectura del set de instrucciones
│   ├── microarchitecture.md   ← Organización interna y diagramas
│   ├── simulation.md          ← Modelado del software / simulación
│   └── img/                   ← Diagramas (block diagram, datapath, FSM)
│
├── rtl/                       ← Código RTL en SystemVerilog
│   ├── top.sv                 ← Módulo top-level del SoC simulado
│   ├── core/
│   │   ├── cpu.sv             ← CPU integrado (datapath + control)
│   │   ├── datapath.sv
│   │   ├── control_unit.sv
│   │   ├── alu.sv
│   │   ├── regfile.sv
│   │   ├── pc.sv
│   │   └── status_reg.sv
│   ├── crypto/
│   │   ├── key_vault.sv       ← Bóveda de 4×128 bits + auth
│   │   ├── tea_unit.sv        ← Unidad funcional TEA (TEAMIX)
│   │   └── auth_fsm.sv        ← FSM de autenticación (LOGIN/LOGOUT)
│   ├── memory/
│   │   ├── imem.sv            ← Memoria de instrucciones (ROM)
│   │   └── dmem.sv            ← Memoria RAM 64 KB
│   └── pkg/
│       └── secur_pkg.sv       ← Parámetros y opcodes (SystemVerilog package)
│
├── tb/                        ← Testbenches
│   ├── tb_top.sv              ← Test integral del sistema
│   ├── tb_alu.sv
│   ├── tb_regfile.sv
│   ├── tb_dmem.sv
│   ├── tb_key_vault.sv
│   ├── tb_tea_unit.sv
│   └── tb_tea_fullblock.sv    ← Cifra/descifra bloque 64-bit
│
├── tools/                     ← Herramientas Python
│   ├── load_file.py           ← Carga archivo → memory.mem
│   ├── extract_data.py        ← Memory dump → archivo binario
│   ├── assembler.py           ← Ensamblador SecuRISC-32 (.s → .mem)
│   └── tea_reference.py       ← Implementación de referencia TEA
│
├── programs/                  ← Programas de ejemplo en ASM SecuRISC-32
│   ├── 01_alu_basic.s
│   ├── 02_memory_test.s
│   ├── 03_branches.s
│   ├── 04_tea_encrypt.s
│   ├── 05_tea_decrypt.s
│   └── 06_file_encrypt.s      ← Cifra todo un archivo cargado en RAM
│
├── examples/                  ← Archivos de prueba
│   ├── input/
│   │   ├── hello.txt
│   │   ├── lena.bmp
│   │   └── data.bin
│   └── expected/              ← Resultados esperados (oráculos)
│       └── hello_encrypted.bin
│
└── sim/                       ← Salidas de simulación (vcd, logs)
    └── .gitkeep
```

---

## Compilación y ejecución rápida

```bash
# 1. Clonar el repositorio
git clone https://github.com/<usuario>/SecuRISC-32.git
cd SecuRISC-32

# 2. Compilar y ejecutar todos los tests
make all

# 3. Ejecutar un testbench específico
make tb_alu        # solo la ALU
make tb_top        # sistema completo
make tb_tea_fullblock

# 4. Visualizar waveforms
make wave TB=tb_top    # abre GTKWave con sim/tb_top.vcd

# 5. Limpiar artefactos de compilación
make clean
```

### Targets disponibles del Makefile

| Target            | Descripción                                             |
|-------------------|---------------------------------------------------------|
| `all`             | Compila y ejecuta todos los testbenches                 |
| `tb_<modulo>`     | Compila y ejecuta un testbench específico               |
| `wave TB=<tb>`    | Abre GTKWave con el `.vcd` correspondiente              |
| `lint`            | Pasa linter (verilator) sobre el RTL                    |
| `program PROG=<>` | Ensambla `programs/<>.s` a `programs/<>.mem`            |
| `clean`           | Borra binarios y archivos de simulación                 |

---

## Uso de la herramienta de carga de archivos

### Cargar un archivo en RAM

```bash
# Texto plano
./tools/load_file.py --input examples/input/hello.txt \
                     --output sim/memory.mem \
                     --address 0x1000

# Imagen
./tools/load_file.py --input examples/input/lena.bmp \
                     --output sim/memory.mem \
                     --address 0x2000
```

**Salida:**
```
[load_file] Tipo detectado: text/plain
[load_file] Tamaño del archivo: 1024 bytes
[load_file] Dirección inicial: 0x1000
[load_file] Dirección final:   0x13FF
[load_file] Archivo .mem generado: sim/memory.mem
```

### Extraer datos cifrados de la memoria

```bash
./tools/extract_data.py --memory sim/memory_dump.txt \
                        --address 0x2000 \
                        --size   4096 \
                        --output resultado.bin
```

### Ensamblar un programa

```bash
./tools/assembler.py programs/04_tea_encrypt.s -o programs/04_tea_encrypt.mem
```

---

## Ejemplo end-to-end: cifrar un archivo

Este flujo cifra `hello.txt` con TEA usando una llave precargada en la bóveda y guarda el resultado en `hello.enc`:

```bash
# 1. Cargar el archivo en RAM a partir de 0x1000
./tools/load_file.py --input examples/input/hello.txt \
                     --output sim/memory.mem --address 0x1000

# 2. Ensamblar el programa de cifrado
./tools/assembler.py programs/06_file_encrypt.s -o sim/program.mem

# 3. Ejecutar la simulación
make tb_top

# 4. Extraer el bloque cifrado
./tools/extract_data.py --memory sim/memory_dump.txt \
                        --address 0x1000 --size 16 \
                        --output hello.enc

# 5. Verificar con la implementación de referencia
./tools/tea_reference.py decrypt --in hello.enc --key 0x0123456789ABCDEFFEDCBA9876543210
```

---

## Test cases incluidos

| Testbench               | Cobertura                                                    |
|-------------------------|--------------------------------------------------------------|
| `tb_alu.sv`             | ADD, SUB, AND, OR, XOR, NOT, SLL/SRL/SRA, SLT, CMP, flags    |
| `tb_regfile.sv`         | Lectura/escritura, R0 hardwired a 0, dual-port read          |
| `tb_dmem.sv`            | LW/LH/LB, SW/SH/SB, alineación, cobertura 64 KB              |
| `tb_key_vault.sv`       | KLOAD, KSEL, KCLR, intentos no autorizados → excepción       |
| `tb_tea_unit.sv`        | TEAMIX vs. modelo de referencia (cobertura aleatoria)        |
| `tb_tea_fullblock.sv`   | Cifrado/descifrado completo de un bloque de 64 bits          |
| `tb_top.sv`             | Programa completo: carga, login, cifra, valida en RAM        |

---

## Documentación de diseño

| Documento                            | Contenido                                       |
|--------------------------------------|-------------------------------------------------|
| [`docs/isa.md`](docs/isa.md)         | ISA, modos de direccionamiento, green card      |
| [`docs/microarchitecture.md`](docs/microarchitecture.md) | Diagrama de bloques, datapath, FSMs             |
| [`docs/simulation.md`](docs/simulation.md) | Modelado de simulación y herramientas externas  |

---

## Autores

- Emanuel Rojas Fernandez — `emmrojas@estudiantec.cr`
- Gabriel Gonzalez Muñoz -
- Emerson Monge Hernandez -
- Gabriel Fernandez Vargas -

---

## Licencia

MIT — ver [`LICENSE`](LICENSE) para más detalles.
