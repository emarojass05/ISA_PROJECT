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

    [31:25 (funct7)] [24:20 (rs2)] [19:15 (rs1)] [14:12 (funct3)] [11:7 (rd)] [6:0 (opcode)]

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
- `rs1`, `rs2` son ignorados en `j` y `jal`
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
| `jal`       | Saltar y enlazar               | `J`   | `0000111` | `001`  |           | `R[ra] = PC + 4; PC += offset`       |       |
| `jr`        | Saltar a contenido de registro | `J`   | `0000111` | `010`  |           | `PC = R[rs1]`                        |       |
| `luhw`      | Cargar inmediato superior      | `U`   | `0000101` | `000`  |           | `R[rd][31:16] = imm`                 |       |
| `llhw`      | Cargar inmediato inferior      | `U`   | `0000101` | `001`  |           | `R[rd][15:0] = imm`                  |       |
| `auth`      | Enable Secure Mode             | `SEC` | `0000110` | `000`  |           | `if (R[rs1] == SECRET) R[sr][0] = 1 else Exception()`                               
| `ldK`       | Load 128-bit Key               | `SEC` | `0000110` | `001`  |           | `Vault[R[rs2]] =R[rs1]`                              
| `enc0`       | Encrypt (TEA)                  | `010` | `0000110` | `010`  |           | `R[rd] = R[rd] + (((R[rs1] << 4) + K0) ^ (R[rs1] + R[rs2]) ^ ((R[rs1] >> 5) + K1))`                                
| `enc1`       | Encrypt (TEA)                  | `011` | `0000110` | `011`  |           | `R[rd] = R[rd] + (((R[rs1] << 4) + K2) ^ (R[rs1] + R[rs2]) ^ ((R[rs1] >> 5) + K3))`                               
| `dec0`       | Decrypt (TEA)                  | `100` | `0000110` | `100`  |           | `R[rd] = R[rd] - (((R[rs1] << 4) + K0) ^ (R[rs1] + R[rs2]) ^ ((R[rs1] >> 5) + K1))`                                
| `dec1`       | Decrypt (TEA)                  | `101` | `0000110` | `101`  |           | `R[rd] = R[rd] - (((R[rs1] << 4) + K2) ^ (R[rs1] + R[rs2]) ^ ((R[rs1] >> 5) + K3))`                              

## Pseudoinstrucciones
| Pseudoinstrucción | Descomposición                            | Significado           |
| ----------------- | ----------------------------------------- | --------------------- |
| `nop`             | `addi zero, zero, 0`                      | Operacion nula        |
| `li rd, imm`      | `luhw rd, imm[31:16]; llhw rd, imm[15:0]` | Cargar inmediato      |
| `mv rd, rs`       | `addi rd, rs, 0`                          | Copiar registros      |
| `call offset`     | `jal offset`                              | Llamar subrutina      |
| `ret`             | `jr ra`                                   | Retornar de subrutina |

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

### 1. Formato de Instrucción SEC-type

Para mantener la simplicidad y eficiencia de la arquitectura, las instrucciones de seguridad (`SEC-type`) reutilizan exactamente la misma estructura y datapath del formato `R-type`. La Unidad de Control identifica el modo de seguridad mediante el Opcode `0000110` y utiliza el campo `funct3` para seleccionar la operación específica.

**Formato:**
`[31:25 (funct7)] [24:20 (rs2)] [19:15 (rs1)] [14:12 (funct3)] [11:7 (rd)] [6:0 (opcode)]`

### 2. Restricciones y Bóveda de Llaves (Key Vault)

[cite_start]El procesador cuenta con una raíz de confianza (RoT) implementada como una memoria segura capaz de almacenar 4 llaves criptográficas de 128 bits[cite: 45, 46]. El acceso a esta bóveda está estrictamente regulado por hardware:

* [cite_start]**Aislamiento:** Los datos almacenados en la bóveda no podrán ser escritos en registros del CPU o memoria general del sistema[cite: 86]. 
* [cite_start]**Operandos Implícitos:** Solamente las instrucciones que operen directamente con las llaves pueden acceder a la bóveda como operando fuente[cite: 87]. Extraen fragmentos de la llave de 32 bits ($K_0, K_1, K_2, K_3$) de forma interna según la instrucción ejecutada.
* [cite_start]**Autenticación:** El procesador mantiene un registro de estado de autenticación que controla el acceso a las operaciones privilegiadas[cite: 90]. [cite_start]Las operaciones criptográficas y de carga de llaves (`ldK`, `enc`, `dec`) verificarán que este estado sea válido; de lo contrario, generarán una excepción o error de acceso[cite: 91].

### 3. Tabla de Instrucciones de Seguridad

[cite_start]*Nota: Para lograr un cifrado eficiente y mantener un balance con la complejidad y área del procesador, las rondas del algoritmo TEA se dividen en dos pasos independientes[cite: 93, 94, 95]. Las fórmulas matemáticas presentadas utilizan suma y resta de 32 bits y compuertas lógicas XOR ($\oplus$).*

| Instrucción | Nombre | Tipo | Opcode | funct3 | Descripción Lógica |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `auth` | Activar Modo Seguro | `SEC` | `0000110` | `000` | `if (R[rs1] == SECRET) R[sr][0] = 1 else Exception()` |
| `ldK` | Cargar Llave a Bóveda | `SEC` | `0000110` | `001` | `Vault[R[rs2]] = R[rs1]` |
| `enc0` | Cifrar TEA (v0) | `SEC` | `0000110` | `010` | $R[rd] = R[rd] + (((R[rs1] \ll 4) + K_0) \oplus (R[rs1] + R[rs2]) \oplus ((R[rs1] \gg 5) + K_1))$ |
| `enc1` | Cifrar TEA (v1) | `SEC` | `0000110` | `011` | $R[rd] = R[rd] + (((R[rs1] \ll 4) + K_2) \oplus (R[rs1] + R[rs2]) \oplus ((R[rs1] \gg 5) + K_3))$ |
| `dec1` | Descifrar TEA (v1) | `SEC` | `0000110` | `100` | $R[rd] = R[rd] - (((R[rs1] \ll 4) + K_2) \oplus (R[rs1] + R[rs2]) \oplus ((R[rs1] \gg 5) + K_3))$ |
| `dec0` | Descifrar TEA (v0) | `SEC` | `0000110` | `101` | $R[rd] = R[rd] - (((R[rs1] \ll 4) + K_0) \oplus (R[rs1] + R[rs2]) \oplus ((R[rs1] \gg 5) + K_1))$ |

### 4. Implementación del Algoritmo TEA (Software)

[cite_start]El desarrollador de software o compilador debe estructurar el ciclo de las 32 rondas requeridas por el algoritmo[cite: 40]. El flujo básico en lenguaje ensamblador es el siguiente:

1.  Autenticar el sistema utilizando la instrucción `auth`.
2.  Cargar la llave de 128 bits iterativamente desde memoria utilizando la instrucción `ldK`.
3.  Inicializar una variable sumatoria (`sum`) en 0.
4.  Ejecutar un ciclo 32 veces realizando:
    * [cite_start]Incrementar `sum` utilizando la constante `DELTA` (cuyo valor es `0x9e3779b9`)[cite: 41].
    * Ejecutar `enc0` pasando `v1` y `sum` como operandos.
    * Ejecutar `enc1` pasando `v0` y `sum` como operandos.
