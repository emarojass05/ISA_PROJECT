# GAEM ISA Reference Sheet
## Overview
### Disposiciones Generales
| Propiedad               | Valor   | Notas |
| ----------------------- | ------- | ----- |
| Ancho de Instruccion    | 32 bits |       |
| Ancho de Palabra (WORD) | 32 bits |       |
| Número de Registros     | 32      |       |
| Alineado de Memoria     | 32      |       |

## Formatos de Intrucción

- **TIPO R**

    `[31:25 (funct7)][24:20 (rs2)][19:15 (rs1)][14:12 (funct3)][11:7 (rd)][6:0 (opcode)]`

- **TIPO I**

    `[31:20 (imm[11:0])][19:15 (rs1)][14:12 (funct3)][11:7 (rd)][6:0 (opcode)]`

- **TIPO S**

    `[11:5 (imm[11:5])][24:20 (rs2)][19:15 (rs1)][14:12 (funct3)][11:7 (imm[4:0])][6:0 (opcode)]`

- **TIPO B**

    `[31:25 (funct7)][24:20 (rs2)][19:15 (rs1)][14:12 (funct3)][11:7 (rd)][6:0 (opcode)]`

- **TIPO U**

    `[31:16 (imm[15:0])][14:12 (funct3)][11:7 (rd)][6:0 (opcode)][31:16 (imm[15:0])][14:12 (funct3)][11:7 (rd)][6:0 (opcode)]`

- **TIPO SEC**

    `[TBD][6:0 opcode]`

## Tabla de Instrucciones

| Instrucción | Nombre                       | Tipo  | Opcode    | funct3 | funct7    | Descripción                                      | Notas |
| ----------- | ---------------------------- | ----- | --------- | ------ | --------- | ------------------------------------------------ | ----- |
| `add`       | Adición                      | `R`   | `0000000` | `000`  | `0000000` | `R[rd] = R[rs1] + R[rs2]`                        |       |
| `sub`       | Substracción                 | `R`   | `0000000` | `001`  | `0000000` | `R[rd] = R[rs1] - R[rs2]`                        |       |
| `mul`       | Multiplicación               | `R`   | `0000000` | `000`  | `0000001` | `R[rd] = R[rs1] * R[rs2]`                        |       |
| `div`       | División                     | `R`   | `0000000` | `001`  | `0000001` | `R[rd] = R[rs1] / R[rs2]`                        |       |
| `rem`       | Módulo                       | `R`   | `0000000` | `010`  | `0000001` | `R[rd] = R[rs1] % R[rs2]`                        |       |
| `and`       | AND bit a bit                | `R`   | `0000000` | `010`  | `0000000` | `R[rd] = R[rs1] & R[rs2]`                        |       |
| `or`        | OR bit a bit                 | `R`   | `0000000` | `011`  | `0000000` | `R[rd] = R[rs1] \| R[rs2]`                       |       |
| `xor`       | XOR bit a bit                | `R`   | `0000000` | `100`  | `0000000` | `R[rd] = R[rs1] ^ R[rs2]`                        |       |
| `sll`       | Shift Left Lógico            | `R`   | `0000000` | `101`  | `0000000` | `R[rd] = R[rs1] << R[rs2]`                       |       |
| `srl`       | Shift Right Lógico           | `R`   | `0000000` | `110`  | `0000000` | `R[rd] = R[rs1] >> R[rs2]`                       |       |
| `addi`      | Adición Inmediata            | `I`   | `0000001` | `000`  |           | `R[rd] = R[rs1] + imm`                           |       |
| `xori`      | XOR Inmediato                | `I`   | `0000001` | `001`  |           | `R[rd] = R[rs1] ^ imm`                           |       |
| `slli`      | Shift Left Lógico Inmediato  | `I`   | `0000001` | `010`  |           | `R[rd] = R[rs1] << imm`                          |       |
| `srli`      | Shift Right Lógico Inmediato | `I`   | `0000001` | `011`  |           | `R[rd] = R[rs1] >> imm`                          |       |
| `lw`        | Cargar Palabra (WORD)        | `I`   | `0000001` | `100`  |           | `R[rd] = Mem[R[rs1] + offset]`                   |       |
| `sw`        | Guardar Palabra (WORD)       | `S`   | `0000010` | `000`  |           | `Mem[R[rs1] + offset] = R[rs2]`                  |       |
| `beq`       | Branch ==                    | `B`   | `0000100` | `000`  |           | `if (R[rs1] == R[rs2]) PC += offset`             |       |
| `bne`       | Branch !=                    | `B`   | `0000100` | `001`  |           | `if (R[rs1] != R[rs2]) PC += offset`             |       |
| `bgt`       | Branch >                     | `B`   | `0000100` | `010`  |           | `if (R[rs1] > R[rs2]) PC += offset`              |       |
| `blt`       | Branch <                     | `B`   | `0000100` | `011`  |           | `if (R[rs1] < R[rs2]) PC += offset`              |       |
| `bge`       | Branch >=                    | `B`   | `0000100` | `100`  |           | `if (R[rs1] >= R[rs2]) PC += offset`             |       |
| `ble`       | Branch <=                    | `B`   | `0000100` | `101`  |           | `if (R[rs1] <= R[rs2]) PC += offset`             |       |
| `b`         | Branch/Salto Incondicional   | `B`   | `0000100` | `110`  |           | `PC = address`                                   |       |
| `luhw`      | Cargar inmediato superior    | `U`   | `0000011` | `000`  |           | `R[rd][31:16] = imm`                             |       |
| `llhw`      | Cargar inmediato inferior    | `U`   | `0000011` | `001`  |           | `R[rd][15:0] = imm`                              |       |
| `auth`      | Enable Secure Mode           | `SEC` | `0000101` | `XXX`  |           | `AUTH = 1`                                       | TBD   |
| `ldK`       | Load 128-bit Key             | `SEC` | `0000101` | `XXX`  |           | `KeyVault[k] = {R[rs1], R[rs2], R[rs3], R[rs4]}` | TBD   |
| `enc`       | Encrypt (TEA)                | `SEC` | `0000101` | `XXX`  |           | `Encrypt(R[rs1], R[rs2], k)`                     | TBD   |
| `dec`       | Decrypt (TEA)                | `SEC` | `0000101` | `XXX`  |           | `Decrypt(R[rs1], R[rs2], k)`                     | TBD   |

## Pseudoinstrucciones
| Pseudoinstrucción | Descomposición                            | Significado           |
| ----------------- | ----------------------------------------- | --------------------- |
| `nop`             | `addi zero, zero, 0`                      | Operacion nula        |
| `li rd, imm`      | `luhw rd, imm[31:16]; llhw rd, imm[15:0]` | Cargar inmediato      |
| `mv rd, rs`       | `addi rd, rs, 0`                          | Copiar registros      |
| `call offset`     | `R[ra] = PC+4; PC += offset`              | Llamar subrutina      |
| `ret`             | `PC = R[ra]`                              | Retornar de subrutina |

## Convención de Registros

- 32 bits: 31 bits de contenido + 1 bit de signo (MSB)

Hay disponibles 32 registros distribuidos según el siguiente ABI:

| Registro  | Alias     | Uso                             | Guardado por     |
| --------- | --------- | ------------------------------- | ---------------- |
| `x0`      | `zero`    | Constante cero                  | --               |
| `x1`      | `ra`      | Dirección de retorno            | Caller           |
| `x2`      | `sp`      | Stack pointer                   | Callee           |
| `x3-x9`   | `a0-a6`   | Argumentos/retorno de funciones | Caller           |
| `x10-x19` | `s0-s9`   | Propósito general               | Callee           |
| `x20`     | `sr`      | Registro de estado              | --               |
| `x21-x25` | `t0-t4`   | Registros temporales            | Caller           |
| `x26-x29` | `s10-s13` | Propósito general               | Callee           |
| `x30`     | `delta`   | Delta constant (TEA)            | --               |
| `x31`     | `vp`      | Vault Pointer                   | Callee (Tipo SE) |

## Acceso a memoria

## Inmediatos

## Cifrado y Seguridad
