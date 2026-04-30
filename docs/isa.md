# GAEM ISA Reference Sheet

## Overview
### Disposiciones Generales

| Propiedad               | Valor        | Notas |
| ----------------------- | ------------ | ----- |
| Ancho de Instrucción    | 4 bytes      |       |
| Ancho de Palabra (WORD) | 4 bytes      |       |
| Número de Registros     | 32           |       |
| Alineado de Memoria     | 4 bytes      |       |
| Incremento PC           | PC + 4 bytes |       |

#### Acceso a memoria

Para el acceso a memoria (`sw`/`lw`), las direcciones deben estar alineadas a 4 bytes, en caso contrario, el comportamiento es indefinido.

## Formatos de Instrucción

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

    [31:16 (imm[15:0])][15 (unused)][14:12 (funct3)][11:7 (rd)][6:0 (opcode)]

#### SEC-type

    [31:25 (unused)][24:20 (rs2)][19:15 (rs1)][14:12 (funct3)][11:7 (rd)][6:0 (opcode)]

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
- `rs2` es utilizado en `jal` (Nota: el destino se guarda en `rd`)
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

Notas:
- `rd` es usado como `rs1` para la adecuada construcción de los inmediatos por medio de operaciones especiales de la alu para `llhw` y `luhw`.

---

#### Resumen

- Todos los offsets son `PC-relative`
- Todos los inmediatos (excepto `U-type`) usan `sign extension`
- No se aplica desplazamiento implícito (`<<1`)

## Tabla de Instrucciones

| Instrucción  | Nombre                         | Tipo  | Opcode    | funct3 | funct7    | Descripción                          | Notas |
| ------------ | ------------------------------ | ----- | --------- | ------ | --------- | ------------------------------------ | ----- |
| `add`        | Adición                        | `R`   | `0000000` | `000`  | `0000000` | `R[rd] = R[rs1] + R[rs2]`            |       |
| `sub`        | Substracción                   | `R`   | `0000000` | `001`  | `0000000` | `R[rd] = R[rs1] - R[rs2]`            |       |
| `mul`        | Multiplicación                 | `R`   | `0000000` | `000`  | `0000001` | `R[rd] = R[rs1] * R[rs2]`            |       |
| `div`        | División                       | `R`   | `0000000` | `001`  | `0000001` | `R[rd] = R[rs1] / R[rs2]`            |       |
| `rem`        | Módulo                         | `R`   | `0000000` | `010`  | `0000001` | `R[rd] = R[rs1] % R[rs2]`            |       |
| `and`        | AND bit a bit                  | `R`   | `0000000` | `010`  | `0000000` | `R[rd] = R[rs1] & R[rs2]`            |       |
| `or`         | OR bit a bit                   | `R`   | `0000000` | `011`  | `0000000` | `R[rd] = R[rs1] \| R[rs2]`           |       |
| `xor`        | XOR bit a bit                  | `R`   | `0000000` | `100`  | `0000000` | `R[rd] = R[rs1] ^ R[rs2]`            |       |
| `sll`        | Shift Left Lógico              | `R`   | `0000000` | `101`  | `0000000` | `R[rd] = R[rs1] << R[rs2]`           |       |
| `srl`        | Shift Right Lógico             | `R`   | `0000000` | `110`  | `0000000` | `R[rd] = R[rs1] >> R[rs2]`           |       |
| `addi`       | Adición Inmediata              | `I`   | `0000001` | `000`  |           | `R[rd] = R[rs1] + imm`               |       |
| `xori`       | XOR Inmediato                  | `I`   | `0000001` | `001`  |           | `R[rd] = R[rs1] ^ imm`               |       |
| `slli`       | Shift Left Lógico Inmediato    | `I`   | `0000001` | `010`  |           | `R[rd] = R[rs1] << imm`              |       |
| `srli`       | Shift Right Lógico Inmediato   | `I`   | `0000001` | `011`  |           | `R[rd] = R[rs1] >> imm`              |       |
| `sw`         | Guardar Palabra (WORD)         | `S`   | `0000010` | `000`  |           | `Mem[R[rs1] + offset] = R[rs2]`      |       |
| `lw`         | Cargar Palabra (WORD)          | `I`   | `0000011` | `100`  |           | `R[rd] = Mem[R[rs1] + offset]`       |       |
| `beq`        | Branch ==                      | `B`   | `0000100` | `000`  |           | `if (R[rs1] == R[rs2]) PC += offset` |       |
| `bne`        | Branch !=                      | `B`   | `0000100` | `001`  |           | `if (R[rs1] != R[rs2]) PC += offset` |       |
| `bgt`        | Branch >                       | `B`   | `0000100` | `010`  |           | `if (R[rs1] > R[rs2]) PC += offset`  |       |
| `blt`        | Branch <                       | `B`   | `0000100` | `011`  |           | `if (R[rs1] < R[rs2]) PC += offset`  |       |
| `bge`        | Branch >=                      | `B`   | `0000100` | `100`  |           | `if (R[rs1] >= R[rs2]) PC += offset` |       |
| `ble`        | Branch <=                      | `B`   | `0000100` | `101`  |           | `if (R[rs1] <= R[rs2]) PC += offset` |       |
| `j`          | Salto Incondicional            | `J`   | `0000111` | `000`  |           | `PC += offset`                       |       |
| `jal`        | Saltar y enlazar               | `J`   | `0000111` | `001`  |           | `R[rd] = PC + 4; PC += offset`       |       |
| `jr`         | Saltar a contenido de registro | `J`   | `0000111` | `010`  |           | `PC = R[rs1]`                        |       |
| `luhw`       | Cargar inmediato superior      | `U`   | `0000101` | `000`  |           | `R[rd][31:16] = imm`                 |       |
| `llhw`       | Cargar inmediato inferior      | `U`   | `0000101` | `001`  |           | `R[rd][15:0] = imm`                  |       |
| `sec.auth`   | Enable Secure Mode             | `SEC` | `0000110` | `000`  |           | `Auth_bit = (R[rs1] == 0xDEADBEEF)`  | Activa Vault |
| `sec.ldk`    | Load Key to Vault              | `SEC` | `0000110` | `001`  |           | `Vault[R[rs2]] = R[rs1]`             | Requiere Auth |
| `sec.addk`   | Secure Add Key                 | `SEC` | `0000110` | `010`  |           | `R[rd] = R[rs1] + Vault[R[rs2]]`     | Requiere Auth |
| `sec.xork`   | Secure XOR Key                 | `SEC` | `0000110` | `011`  |           | `R[rd] = R[rs1] ^ Vault[R[rs2]]`     | Requiere Auth |
| `sec.tea`    | TEA Crypto Core                | `SEC` | `0000110` | `100`  |           | `R[rd] = TEA_Formula(rs1, rs2, key)` | Acelerador HW |

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

## Cifrado y Seguridad (Custom ISA Extension)

La arquitectura GAEM incluye una extensión de seguridad criptográfica por hardware diseñada para aislar material sensible (llaves) del flujo de datos tradicional, evitando que el software pueda leer las llaves criptográficas una vez cargadas.

Esta arquitectura cuenta con tres componentes físicos principales operando directamente en el Datapath:

### 1. El Registro Guardián (`Auth_bit`)
Es un mecanismo de control de acceso por hardware. Por defecto, todas las operaciones criptográficas están bloqueadas y arrojarán una excepción si se intentan ejecutar.
* Para habilitar la seguridad, el software debe ejecutar la instrucción `sec.auth` pasando una llave maestra (`0xDEADBEEF` por defecto).
* Solo cuando el hardware verifica esta firma, el bit de autorización se levanta (`auth_en = 1`), permitiendo el uso del Coprocesador y la Bóveda.

### 2. Bóveda de Llaves Aislada (`Key Vault`)
La arquitectura incluye una memoria RAM secundaria independiente de la memoria de datos principal.
* **Aislamiento:** Es físicamente imposible leer el contenido de la bóveda usando instrucciones estándar como `lw`.
* **Escritura Exclusiva:** Las llaves solo se pueden inyectar en la bóveda usando la instrucción `sec.ldk`.
* **Lectura Implícita:** Las llaves nunca se devuelven al `Register File`. Se leen internamente de forma automática en la etapa `Decode` y se envían por una ruta dedicada al Coprocesador Seguro.

### 3. Coprocesador Seguro Acelerado (`SEC_ALU`)
Ubicado en paralelo a la ALU estándar en la etapa `Execute`, este acelerador de hardware ejecuta operaciones matemáticas mezclando datos públicos con llaves secretas. Posee mecanismos de defensa contra ataques y aceleradores criptográficos:

* **Zero-Attack Detection:** Si el software malicioso intenta inyectar un cero en una operación de identidad (`sec.addk x0` o `sec.xork x0`) con la intención de que la operación devuelva la llave pura (ej. `0 + key = key`), la `SEC_ALU` detecta el ataque, anula el resultado (`result = 0`) y levanta una excepción por hardware (`exception = 1`).
* **Acelerador TEA (`sec.tea`):** Implementa el núcleo matemático del algoritmo TEA (Tiny Encryption Algorithm) a nivel de compuertas lógicas (Hardware Accelerator). Ejecuta la fórmula simétrica en **un solo ciclo de reloj**:
    $$Result = ((A \ll 4) + Key) \oplus B \oplus ((A \gg 5) + Key)$$
* **Modo Stream Cipher (Simetría de Cifrado):** Gracias a la propiedad simétrica de la compuerta XOR, la misma instrucción de hardware `sec.tea` se utiliza tanto para encriptar como para desencriptar información en tiempo real sin modificar la arquitectura lógica, simplemente aplicando XOR sobre el Keystream generado.