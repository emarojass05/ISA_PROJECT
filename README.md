# SecuRISC-32 — Procesador RISC con Extensiones de Seguridad

> Proyecto Grupal I — CE-4301 Arquitectura de Computadores I
> Instituto Tecnológico de Costa Rica · Escuela de Ingeniería en Computadores
> I Semestre 2026

SecuRISC-32 es una ISA tipo RISC de 32 bits diseñada e implementada en SystemVerilog para aplicaciones relacionadas con seguridad informática. El proyecto incluye un procesador con instrucciones aritméticas, lógicas, de memoria, control de flujo y una extensión de seguridad con autenticación, bóveda de llaves y primitivas criptográficas.

El procesador se simula con Icarus Verilog (`iverilog`) y puede ejecutar programas escritos directamente en assembly o generados desde un compilador propio para el lenguaje fuente del proyecto.

---

## Propósito del proyecto

El objetivo principal del proyecto es aplicar conceptos de arquitectura de computadores mediante el diseño e implementación de:

1. Una ISA RISC propia con instrucciones aritméticas, lógicas, de memoria y de control de flujo.
2. Extensiones de seguridad para autenticación, acceso controlado a una bóveda de llaves y operaciones criptográficas.
3. Soporte para operaciones de cifrado sobre archivos cargados en memoria simulada.
4. Herramientas para cargar archivos arbitrarios en RAM simulada y extraer los resultados después de la ejecución.
5. Un compilador que traduce programas fuente del lenguaje del proyecto hacia assembly y código hexadecimal ejecutable por el procesador.

---

## Dependencias

| Herramienta | Versión recomendada | Uso |
| --- | --- | --- |
| Icarus Verilog | 11.0+ | Compilación y simulación de módulos SystemVerilog |
| GTKWave | 3.3+ | Visualización de señales `.vcd` |
| Python | 3.9+ | Compilador, assembler y herramientas de archivos |
| GNU Make | 4.0+ | Automatización de compilación y simulación |
| Java | 11+ | Ejecución de ANTLR |
| Git | 2.30+ | Control de versiones |

### Instalación rápida en Ubuntu / WSL

```bash
sudo apt update
sudo apt install iverilog gtkwave python3 python3-pip python3-venv make git default-jre
```

### Instalación rápida en macOS

```bash
brew install icarus-verilog gtkwave python3 make git openjdk
```

### Instalación en Windows

Se recomienda usar WSL2 con Ubuntu y seguir las instrucciones de Linux.

---

## Configuración inicial

Después de clonar el repositorio, se recomienda crear el entorno virtual de Python e instalar las dependencias:

```bash
make setup
```

Para verificar y generar los módulos de ANTLR:

```bash
make check-env
make antlr-build
```

---

## Estructura del repositorio

```text
ISA_PROJECT/
├── LICENSE
├── Makefile
├── README.md
├── README_comp.md
├── requirements.txt
│
├── docs/
│   └── isa.md
│
├── examples/
│   ├── test1.png
│   ├── test2.png
│   ├── test3.png
│   ├── enc_test2.png
│   └── dec_enc_test2.png
│
├── programs/
│   ├── asm/
│   │   ├── auth_test.s
│   │   ├── decrypt.s
│   │   ├── encrypt.s
│   │   ├── program.s
│   │   ├── sec_test.s
│   │   ├── tea_encrypt.s
│   │   ├── tea_decrypt.s
│   │   ├── test.s
│   │   ├── test2.s
│   │   └── test3.s
│   │
│   ├── hex/
│   │   ├── auth_test.hex
│   │   ├── decrypt.hex
│   │   ├── encrypt.hex
│   │   ├── program.hex
│   │   ├── sec_test.hex
│   │   ├── tea_encrypt.hex
│   │   ├── tea_decrypt.hex
│   │   ├── test.hex
│   │   ├── test2.hex
│   │   ├── test3.hex
│   │   └── test_instr_mem.hex
│   │
│   ├── mems/
│   │   └── memory.mem
│   │
│   └── source/
│       ├── factorial.fr
│       ├── main.fr
│       ├── many_args.fr
│       ├── matrix_mult.fr
│       ├── merge_sort.fr
│       ├── search.fr
│       ├── tea.fr
│       └── test.fr
│
├── src/
│   ├── compiler/
│   │   ├── backend/
│   │   │   └── encoder.py
│   │   ├── grammar/
│   │   │   └── Language.g4
│   │   ├── generated/
│   │   ├── semantic/
│   │   │   ├── ControlFlowVisitor.py
│   │   │   ├── asmgenerator.py
│   │   │   ├── fixuptable.py
│   │   │   ├── labeltable.py
│   │   │   └── symboltable.py
│   │   └── main.py
│   │
│   └── cpu/
│       ├── alu.sv
│       ├── control_unit.sv
│       ├── cpu_top.sv
│       ├── data_mem.sv
│       ├── decoder.sv
│       ├── forwarding_unit.sv
│       ├── hazard_unit.sv
│       ├── instr_mem.sv
│       ├── isa_defs.sv
│       ├── key_vault.sv
│       ├── pc.sv
│       ├── pc_adder.sv
│       ├── register_file.sv
│       └── sec_alu.sv
│
├── tb/
│   ├── tb_alu.sv
│   ├── tb_control_unit.sv
│   ├── tb_cpu.sv
│   ├── tb_cpu_program.sv
│   ├── tb_cpu_top.sv
│   ├── tb_data_mem.sv
│   ├── tb_decoder.sv
│   ├── tb_instr_mem.sv
│   ├── tb_key_vault.sv
│   ├── tb_pc.sv
│   ├── tb_pc_adder.sv
│   ├── tb_register_file.sv
│   └── tb_sec_alu.sv
│
└── tools/
    ├── antlr-4.13.2-complete.jar
    ├── extract_data.py
    └── load_file.py
```

---

## Componentes principales

### Procesador

El procesador está implementado en `src/cpu/` y está compuesto por módulos separados:

| Módulo               | Descripción                                |
| -------------------- | ------------------------------------------ |
| `cpu_top.sv`         | Integra el procesador completo             |
| `isa_defs.sv`        | Define tipos, opcodes y constantes del ISA |
| `control_unit.sv`    | Genera señales de control                  |
| `decoder.sv`         | Decodifica instrucciones                   |
| `alu.sv`             | Ejecuta operaciones aritméticas y lógicas  |
| `register_file.sv`   | Banco de registros                         |
| `data_mem.sv`        | Memoria de datos                           |
| `instr_mem.sv`       | Memoria de instrucciones                   |
| `pc.sv`              | Registro de Program Counter                |
| `pc_adder.sv`        | Cálculo de siguiente PC                    |
| `forwarding_unit.sv` | Unidad de forwarding                       |
| `hazard_unit.sv`     | Unidad de detección de riesgos             |
| `key_vault.sv`       | Bóveda de llaves                           |
| `sec_alu.sv`         | ALU de seguridad                           |

### Compilador

El compilador se encuentra en `src/compiler/`. Permite procesar archivos `.fr` desde `programs/source/` y generar assembly y hexadecimal.

| Componente        | Descripción                      |
| ----------------- | -------------------------------- |
| `Language.g4`     | Gramática ANTLR                  |
| `main.py`         | Punto de entrada del compilador  |
| `asmgenerator.py` | Generación de assembly           |
| `symboltable.py`  | Tabla de símbolos                |
| `labeltable.py`   | Tabla de etiquetas               |
| `fixuptable.py`   | Resolución de saltos y etiquetas |
| `encoder.py`      | Ensamblador de `.s` a `.hex`     |

---

## ISA implementada

La ISA utiliza instrucciones de 32 bits y 32 registros de propósito general. Los grupos principales de instrucciones son:

| Grupo      | Instrucciones                                                       |
| ---------- | ------------------------------------------------------------------- |
| ALU R-type | `add`, `sub`, `mul`, `div`, `rem`, `and`, `or`, `xor`, `sll`, `srl` |
| ALU I-type | `addi`, `xori`, `slli`, `srli`                                      |
| Memoria    | `lw`, `sw`                                                          |
| Branch     | `beq`, `bne`, `bgt`, `blt`, `bge`, `ble`                            |
| Jump       | `j`, `jal`, `jr`                                                    |
| U-type     | `luhw`, `llhw`                                                      |
| Seguridad  | `auth`, `ldk`, `addk`, `xork`, `tea`                                |

La especificación detallada del ISA se encuentra en:

```text
docs/isa.md
```

---

## Extensión de seguridad

La extensión de seguridad agrega instrucciones especiales para autenticación y operaciones con llaves protegidas.

### Autenticación

La instrucción `auth` habilita el modo seguro cuando se proporciona la contraseña correcta:

```asm
li      x1, 0xDEADBEEF
auth    x1
```

### Bóveda de llaves

La instrucción `ldk` almacena una palabra de llave dentro de la bóveda:

```asm
li      x2, 0xA5A5A5A5
li      x3, 0
ldk     x2, x3
```

Esto escribe el valor de `x2` en la entrada `vault[0]`.

### Operaciones con llave

Las instrucciones `addk`, `xork` y `tea` usan valores almacenados en la bóveda:

```asm
addk    x8, x7, x6
xork    x9, x7, x6
tea     x10, x7, x6
```

---

## Compilación de módulos SystemVerilog

Para compilar y ejecutar un módulo específico con su testbench:

```bash
make sv-run-alu
make sv-run-pc
make sv-run-pc_adder
make sv-run-register_file
make sv-run-data_mem
make sv-run-instr_mem
make sv-run-decoder
make sv-run-control_unit
make sv-run-key_vault
make sv-run-sec_alu
```

El patrón general es:

```bash
make sv-run-<modulo>
```

Para solo compilar un módulo:

```bash
make sv-cbuild-alu
```

Para limpiar salidas de simulación:

```bash
make sv-clear
```

---

## Ejecución del CPU con un programa arbitrario

El target `sv-cpu-exec` permite ejecutar el CPU con un archivo `.hex` específico.

```bash
make sv-cpu-exec PROGRAM=programs/hex/program.hex
```

También se puede cargar memoria inicial:

```bash
make sv-cpu-exec PROGRAM=programs/hex/program.hex INITIAL_MEM=memory.mem
```

Y ajustar la cantidad máxima de ciclos:

```bash
make sv-cpu-exec PROGRAM=programs/hex/program.hex MAX_CYCLES=500
```

---

## Uso del assembler

Los programas assembly se encuentran en:

```text
programs/asm/
```

Para codificar un programa y mostrar el hexadecimal en consola:

```bash
make asm-encode-sec_test
```

Para codificar un programa y guardar el resultado en `programs/hex/`:

```bash
make asm-build-sec_test
```

Ejemplos:

```bash
make asm-build-auth_test
make asm-build-sec_test
make asm-build-encrypt
make asm-build-decrypt
make asm-build-tea_encrypt
make asm-build-tea_decrypt
```

---

## Uso del compilador del lenguaje fuente

Los programas fuente `.fr` se encuentran en:

```text
programs/source/
```

### Parsear un programa

```bash
make frc-parse-factorial
```

Este comando procesa el archivo:

```text
programs/source/factorial.fr
```

y ejecuta el análisis del programa.

### Compilar y guardar salida

```bash
make frc-build-factorial
```

Este es el flujo recomendado para la entrega. Genera y guarda tanto el archivo `.asm` como el archivo `.hex` correspondiente.

### Compilar en modo debug

```bash
make frc-debug-factorial
```

Este modo imprime información detallada del proceso de compilación, incluyendo fases internas, AST, tablas, assembly generado y hexadecimal final.

### Otros ejemplos

```bash
make frc-parse-main
make frc-build-main
make frc-debug-main

make frc-build-many_args
make frc-build-matrix_mult
make frc-build-merge_sort
make frc-build-search
make frc-build-tea
```

---

## Herramientas de carga y extracción de archivos

El proyecto incluye herramientas para cargar archivos reales en la memoria simulada y extraer resultados desde los volcados de memoria.

### Cargar un archivo a memoria

```bash
./tools/load_file.py --input examples/test1.png --output memory.mem --address 0x1000
```

Parámetros:

| Parámetro   | Descripción                                 |
| ----------- | ------------------------------------------- |
| `--input`   | Archivo de entrada que se desea cargar      |
| `--output`  | Archivo `.mem` generado                     |
| `--address` | Dirección inicial dentro de la RAM simulada |

### Extraer datos desde un volcado de memoria

```bash
./tools/extract_data.py --memory build/sim/memory_dump.txt --address 0x1000 --size 4096 --output resultado.bin
```

Parámetros:

| Parámetro   | Descripción                             |
| ----------- | --------------------------------------- |
| `--memory`  | Archivo de volcado de memoria           |
| `--address` | Dirección inicial de extracción         |
| `--size`    | Cantidad de bytes que se desean extraer |
| `--output`  | Archivo binario resultante              |

---

## Flujo de cifrado y descifrado

El proyecto incluye flujos automatizados en el Makefile para cifrar y descifrar archivos cargados en memoria.

### Limpiar artefactos de cifrado

```bash
make encrypt-clean
```

Este comando borra archivos temporales generados por los flujos de cifrado y descifrado.

### Cifrado estándar

```bash
make encrypt-flow FILE=test1.png
```

Este flujo:

1. Carga `examples/test1.png` en memoria.
2. Copia `programs/hex/encrypt.hex` como programa principal.
3. Ejecuta la simulación.
4. Extrae el resultado como `examples/enc_test1.png`.
5. Compara el archivo original contra el resultado cifrado.

### Descifrado estándar

```bash
make decrypt-flow FILE=enc_test1.png
```

Este flujo:

1. Carga `examples/enc_test1.png` en memoria.
2. Copia `programs/hex/decrypt.hex` como programa principal.
3. Ejecuta la simulación.
4. Extrae el resultado como `examples/dec_enc_test1.png`.

### Verificación roundtrip estándar

```bash
make verify-roundtrip FILE=test1.png
```

Este flujo ejecuta:

```text
encrypt-flow
decrypt-flow
comparación final
```

El resultado esperado es que el archivo descifrado coincida con el archivo original.

### Verificación roundtrip con TEA

```bash
make verify-roundtrip-tea FILE=test1.png
```

Este flujo utiliza los programas TEA:

```text
programs/hex/tea_encrypt.hex
programs/hex/tea_decrypt.hex
```

y luego ejecuta el roundtrip completo.

Antes de ejecutarlo, el Makefile reconstruye los programas TEA:

```bash
make asm-build-tea_encrypt
make asm-build-tea_decrypt
```

---

## Comandos principales

### Comandos de compilación del compilador

```bash
make frc-parse-factorial
make frc-build-factorial
make frc-debug-factorial
```

Descripción:

| Comando                    | Descripción                                               |
| -------------------------- | --------------------------------------------------------- |
| `make frc-parse-factorial` | Analiza `factorial.fr`                                    |
| `make frc-build-factorial` | Genera y guarda `.asm` y `.hex`; recomendado para entrega |
| `make frc-debug-factorial` | Imprime fases internas, AST, tablas, assembly y hex       |

### Comandos de cifrado

```bash
make verify-roundtrip FILE=test1.png
make verify-roundtrip-tea FILE=test1.png
```

Descripción:

| Comando                                    | Descripción                                            |
| ------------------------------------------ | ------------------------------------------------------ |
| `make verify-roundtrip FILE=test1.png`     | Verifica cifrado y descifrado estándar                 |
| `make verify-roundtrip-tea FILE=test1.png` | Verifica cifrado y descifrado usando los programas TEA |

---

## Testbenches incluidos

| Testbench             | Cobertura                          |
| --------------------- | ---------------------------------- |
| `tb_alu.sv`           | Operaciones aritméticas y lógicas  |
| `tb_control_unit.sv`  | Señales de control                 |
| `tb_cpu.sv`           | Simulación integral del procesador |
| `tb_cpu_program.sv`   | Ejecución de programas arbitrarios |
| `tb_cpu_top.sv`       | Integración del CPU                |
| `tb_data_mem.sv`      | Memoria de datos                   |
| `tb_decoder.sv`       | Decodificación de instrucciones    |
| `tb_instr_mem.sv`     | Memoria de instrucciones           |
| `tb_key_vault.sv`     | Bóveda de llaves                   |
| `tb_pc.sv`            | Program Counter                    |
| `tb_pc_adder.sv`      | Cálculo de PC                      |
| `tb_register_file.sv` | Banco de registros                 |
| `tb_sec_alu.sv`       | ALU de seguridad                   |

---

## Documentación de diseño

| Documento                   | Contenido                                                              |
| --------------------------- | ---------------------------------------------------------------------- |
| `docs/isa.md`               | Especificación del ISA, formatos, opcodes, instrucciones y green sheet |
| `docs/microarchitecture.md` | Organización interna, datapath, pipeline y módulos principales         |
| `docs/simulation.md`        | Modelo de simulación, testbenches, herramientas y flujos de validación |

---


## Archivos generados

Durante la compilación y simulación se generan archivos como:

| Archivo o carpeta             | Descripción                                     |
| ----------------------------- | ----------------------------------------------- |
| `build/sim/*.vvp`             | Binarios de simulación generados por `iverilog` |
| `build/sim/*.vcd`             | Waveforms para GTKWave                          |
| `build/sim/memory_dump.txt`   | Volcado final de memoria                        |
| `build/sim/register_dump.txt` | Volcado de registros                            |
| `programs/hex/*.hex`          | Programas codificados en hexadecimal            |
| `examples/enc_*`              | Archivos cifrados                               |
| `examples/dec_*`              | Archivos descifrados                            |


Para limpiar salidas de simulación:

```bash
make sv-clear
```

---

## Autores

- Emanuel Rojas Fernández
- Gabriel González Muñoz
- Emerson Monge Hernández
- Gabriel Fernández Vargas

