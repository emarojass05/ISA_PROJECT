# GAEM ISA Reference Sheet
## Overview
### Disposiciones Generales

| Propiedad               | Valor        | Notas |
| ----------------------- | ------------ | ----- |
| Ancho de Instruccion    | 4 bytes      |       |
| Ancho de Palabra (WORD) | 4 bytes      |       |
| Número de Registros     | 32           |       |
| Alineado de Memoria     | 4 bytes      |       |
| Incremento PC           | PC + 4 bytes |       |

#### Acceso a memoria

Para el acceso a memoria (`sw`/`lw`), las direcciones deben estar alineadas a 4 bytes, en caso contrario, el comportamiento es indefinido.

## Formatos de Intrucción

#### R-type

    [31:25 (funct7)][24:20 (rs2)][19:15 (rs1)][14:12 (funct3)][11:7 (rd)][6:0 (opcode)]

#### I-type

    [31:20 (imm[11:0])][19:15 (rs1)][14:12 (funct3)][11:7 (rd)][6:0 (opcode)]

#### S-type

    [31:25 (imm[11:5])][24:20 (rs2)][19:15 (rs1)][14:12 (funct3)][11:7 (imm[4:0])][6:0 (opcode)]

#### B-type

    [31:25 (imm[11:5])][24:20 (rs2)][19:15 (rs1)][14:12 (funct3)][11:7 (imm[4:0])][6:0 (opcode)]

#### J-type

    [31:25 (imm[11:5])][24:20 (rs2)][19:15 (rs1)][14:12 (funct3)][11:7 (imm[4:0])][6:0 (opcode)]

#### U-type

    [31:16 (imm[15:0])][14:12 (funct3)][11:7 (rd)][6:0 (opcode)]

#### SEC-type

    [TBD][6:0 opcode]

### Inmediatos y Extensión

Todos los inmediatos son extendidos a 32 bits (`XLEN`) antes de su uso.

#### Regla general

- Los inmediatos se interpretan en complemento a dos
- Se aplica `sign extension` salvo que se indique lo contrario

---

#### I-type

Formato:  
`imm[11:0]`

Interpretación:  
`imm_ext = sign_extend(imm[11:0])`

Uso:
- Operaciones ALU inmediatas
- Direccionamiento en `LOAD`

---

#### S-type

Formato:  
`imm[11:5] | imm[4:0]`

Reconstrucción:  
`imm = {imm[11:5], imm[4:0]}`

Interpretación:  
`imm_ext = sign_extend(imm)`

Uso:
- Offset para `STORE`

---

#### B-type (Branch)

Formato:  
`imm[11:5] | imm[4:0]`

Reconstrucción:  
`imm = {imm[11:5], imm[4:0]}`

Interpretación:  
`offset = sign_extend(imm)`

Actualización de PC:  
`PC = PC + offset` (si la condición es verdadera)

---

#### J-type (Jump)

Formato:  
`imm[11:5] | imm[4:0]`

Reconstrucción:  
`imm = {imm[11:5], imm[4:0]}`

Interpretación:  
`offset = sign_extend(imm)`

Uso:
- `j`, `jal`

Actualización de PC:  
`PC = PC + offset`

Notas:
- `rs1`, `rs2` son ignorados en `j`
- `rs2` es utilizado en `jal`
- `rs1` es utilizado en `jr`

---

#### U-type

Formato:  
`imm[15:0]`

Interpretación:
- No se extiende directamente
- Se posiciona en el registro destino según la instrucción

Uso:
- `luhw`: `R[rd][31:16] = imm`
- `llhw`: `R[rd][15:0]  = imm`

---

#### Resumen

- Todos los offsets son `PC-relative`
- Todos los inmediatos (excepto `U-type`) usan `sign extension`
- No se aplica desplazamiento implícito (`<<1`)

## Tabla de Instrucciones

| Instrucción | Nombre                         | Tipo  | Opcode    | funct3 | funct7    | Descripción                          | Notas |
| ----------- | ------------------------------ | ----- | --------- | ------ | --------- | ------------------------------------ | ----- |
| `add`       | Adición                        | `R`   | `0000000` | `000`  | `0000000` | `R[rd] = R[rs1] + R[rs2]`            |       |
| `sub`       | Substracción                   | `R`   | `0000000` | `001`  | `0000000` | `R[rd] = R[rs1] - R[rs2]`            |       |
| `mul`       | Multiplicación                 | `R`   | `0000000` | `000`  | `0000001` | `R[rd] = R[rs1] * R[rs2]`            |       |
| `div`       | División                       | `R`   | `0000000` | `001`  | `0000001` | `R[rd] = R[rs1] / R[rs2]`            |       |
| `rem`       | Módulo                         | `R`   | `0000000` | `010`  | `0000001` | `R[rd] = R[rs1] % R[rs2]`            |       |
| `and`       | AND bit a bit                  | `R`   | `0000000` | `010`  | `0000000` | `R[rd] = R[rs1] & R[rs2]`            |       |
| `or`        | OR bit a bit                   | `R`   | `0000000` | `011`  | `0000000` | `R[rd] = R[rs1] \| R[rs2]`           |       |
| `xor`       | XOR bit a bit                  | `R`   | `0000000` | `100`  | `0000000` | `R[rd] = R[rs1] ^ R[rs2]`            |       |
| `sll`       | Shift Left Lógico              | `R`   | `0000000` | `101`  | `0000000` | `R[rd] = R[rs1] << R[rs2]`           |       |
| `srl`       | Shift Right Lógico             | `R`   | `0000000` | `110`  | `0000000` | `R[rd] = R[rs1] >> R[rs2]`           |       |
| `addi`      | Adición Inmediata              | `I`   | `0000001` | `000`  |           | `R[rd] = R[rs1] + imm`               |       |
| `xori`      | XOR Inmediato                  | `I`   | `0000001` | `001`  |           | `R[rd] = R[rs1] ^ imm`               |       |
| `slli`      | Shift Left Lógico Inmediato    | `I`   | `0000001` | `010`  |           | `R[rd] = R[rs1] << imm`              |       |
| `srli`      | Shift Right Lógico Inmediato   | `I`   | `0000001` | `011`  |           | `R[rd] = R[rs1] >> imm`              |       |
| `sw`        | Guardar Palabra (WORD)         | `S`   | `0000010` | `000`  |           | `Mem[R[rs1] + offset] = R[rs2]`      |       |
| `lw`        | Cargar Palabra (WORD)          | `I`   | `0000011` | `100`  |           | `R[rd] = Mem[R[rs1] + offset]`       |       |
| `beq`       | Branch ==                      | `B`   | `0000100` | `000`  |           | `if (R[rs1] == R[rs2]) PC += offset` |       |
| `bne`       | Branch !=                      | `B`   | `0000100` | `001`  |           | `if (R[rs1] != R[rs2]) PC += offset` |       |
| `bgt`       | Branch >                       | `B`   | `0000100` | `010`  |           | `if (R[rs1] > R[rs2]) PC += offset`  |       |
| `blt`       | Branch <                       | `B`   | `0000100` | `011`  |           | `if (R[rs1] < R[rs2]) PC += offset`  |       |
| `bge`       | Branch >=                      | `B`   | `0000100` | `100`  |           | `if (R[rs1] >= R[rs2]) PC += offset` |       |
| `ble`       | Branch <=                      | `B`   | `0000100` | `101`  |           | `if (R[rs1] <= R[rs2]) PC += offset` |       |
| `j`         | Salto Incondicional            | `J`   | `0000111` | `000`  |           | `PC += offset`                       |       |
| `jal`       | Saltar y enlazar               | `J`   | `0000111` | `001`  |           | `R[rs2] = PC + 4; PC += offset`       |       |
| `jr`        | Saltar a contenido de registro | `J`   | `0000111` | `010`  |           | `PC = R[rs1]`                        |       |
| `luhw`      | Cargar inmediato superior      | `U`   | `0000101` | `000`  |           | `R[rd][31:16] = imm`                 |       |
| `llhw`      | Cargar inmediato inferior      | `U`   | `0000101` | `001`  |           | `R[rd][15:0] = imm`                  |       |
| `auth`      | Enable Secure Mode             | `SEC` | `0000110` | `XXX`  |           | `TBD`                                | TBD   |
| `ldK`       | Load 128-bit Key               | `SEC` | `0000110` | `XXX`  |           | `TBD`                                | TBD   |
| `enc`       | Encrypt (TEA)                  | `SEC` | `0000110` | `XXX`  |           | `TBD`                                | TBD   |
| `dec`       | Decrypt (TEA)                  | `SEC` | `0000110` | `XXX`  |           | `TBD`                                | TBD   |

## Pseudoinstrucciones
| Pseudoinstrucción | Descomposición                            | Significado           |
| ----------------- | ----------------------------------------- | --------------------- |
| `nop`             | `addi x0, x0, 0`                          | Operacion nula        |
| `li rd, imm`      | `luhw rd, imm[31:16]; llhw rd, imm[15:0]` | Cargar inmediato      |
| `mv rd, rs`       | `addi rd, rs, 0`                          | Copiar registros      |
| `call offset`     | `jal x1, offset`                          | Llamar subrutina      |
| `ret`             | `jr x1`                                   | Retornar de subrutina |

## Convención de Registros

- 32 bits en complemento a dos (MSB -> signo)

Hay disponibles 32 registros distribuidos según el siguiente ABI:

| Registro  | Alias     | Uso                             | Guardado por     |
| --------- | --------- | ------------------------------- | ---------------- |
| `x0`      | `zero`    | Constante cero (hardwired)      | --               |
| `x1`      | `ra`      | Dirección de retorno            | Caller           |
| `x2`      | `sp`      | Stack pointer                   | Callee           |
| `x3-x9`   | `a0-a6`   | Argumentos/retorno de funciones | Caller           |
| `x10-x19` | `s0-s9`   | Propósito general               | Callee           |
| `x20`     | `sr`      | Registro de estado              | --               |
| `x21-x25` | `t0-t4`   | Registros temporales            | Caller           |
| `x26-x29` | `s10-s13` | Propósito general               | Callee           |
| `x30`     | `delta`   | Delta constant (TEA, hardwired) | --               |
| `x31`     | `vp`      | Vault Pointer                   | Callee (Tipo SE) |


## Cifrado y Seguridad
