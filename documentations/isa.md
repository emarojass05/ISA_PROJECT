# ISA – RISC 32-bit con Extensiones de Seguridad

## Flujo general

CPU → AUTH → habilita acceso seguro  
CPU → KeyVault (solo instrucciones especiales)  
CPU ↔ Memoria  
CPU → TEA → Memoria  
Registros ↔ ALU  

## Registros

16 Registros de 32 bits

| Registro| Alias| Uso| Guardado por|
|-|-|-|-|
| r0| zero| Constante zero|--|
| r1| ra| Dirección de retorno| Caller|
| r2| sp| Stack pointer| Callee|
| r3-r7| a0-a4| Argumentos/retorno de funciones| Caller|
| r8-r12| s0-s4| Registros guardados | Callee|
| r13-r15| t0-t2| Registros temporales| Caller|




## Program Counter

- PC de 32 bits
- Incremento: PC + 4
- Modificado por saltos y branches


## Registro de Estado

- AUTH flag
- Controla acceso a:
  - Key Vault
  - Instrucciones de cifrado



## Formatos de Instrucción

| Instrucción | Tipo | Descripción | Operación |Notas|
|------------|------|------------|-----------|-|
| ADD        | R    | Add        | `R[rd] = R[rs1] + R[rs2]` ||
| SUB        | R    | Subtract   | `R[rd] = R[rs1] - R[rs2]` ||
| AND        | R    | Bitwise AND | `R[rd] = R[rs1] & R[rs2]` ||
| OR         | R    | Bitwise OR  | `R[rd] = R[rs1] \| R[rs2]` ||
| XOR        | R    | Bitwise XOR | `R[rd] = R[rs1] ^ R[rs2]` ||
| SLL        | R    | Shift Left Logical | `R[rd] = R[rs1] << R[rs2]` ||
| SRL        | R    | Shift Right Logical | `R[rd] = R[rs1] >> R[rs2]` ||
| MV | R | Move contents
| LD       | I    | Load Word | `R[rd] = Mem[R[rs1] + offset]` ||
| LIM | I | Load Immediate | `R[rd] = imm`||
| STR      | S    | Store Word | `Mem[R[rs1] + offset] = R[rs2]` ||
| BEQ        | B    | Branch if Equal | `if (R[rs1] == R[rs2]) PC = PC + offset` ||
| BNE        | B    | Branch if Not Equal | `if (R[rs1] != R[rs2]) PC = PC + offset` ||
| BGT        | B    | Branch if Greater Than | `if (R[rs1] > R[rs2]) PC = PC + offset` ||
| BLT        | B    | Branch if Less Than | `if (R[rs1] < R[rs2]) PC = PC + offset` ||
| BGE        | B    | Branch if Greater or Equal | `if (R[rs1] >= R[rs2]) PC = PC + offset` ||
| BLE        | B    | Branch if Less or Equal | `if (R[rs1] <= R[rs2]) PC = PC + offset` ||
| JMP        | J    | Jump | `PC = address` ||
| CALL       | J    | Call Function | `R[RA] = PC + 4; PC = address` ||
| RET        | J    | Return | `PC = R[RA]` ||
| AUTH       | SEC  | Enable Secure Mode | `AUTH = 1` ||
| LDK    | SEC  | Load 128-bit Key | `KeyVault[k] = {R[rs1], R[rs2], R[rs3], R[rs4]}` ||
| ENC     | SEC  | Encrypt (TEA) | `Encrypt(R[rs1], R[rs2], k)` ||
| DEC     | SEC  | Decrypt (TEA) | `Decrypt(R[rs1], R[rs2], k)` ||

## Encodificación de las instrucciones

| Tipo | 15 | 14 | 13 | 12 | 11 | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|------|----|----|----|----|----|----|---|---|---|---|---|---|---|---|---|---|
| R    |    | rs2 |  |  |  | rs1 |  |  |  | funct4 |  |  |  | opcode |  |  |
| I    | imm |  |  |  |  |  |  |  | rd |  |  |  | mem | opcode |  |  |
| S    | imm |  |  |  |  |  |  |  |  | rs1 |  |  |  | opcode |  |  |
| B    |    |    | rs2 |  |  |  | rs1 |  |  |  | eq | funct2 |  | opcode |  |  |
| J    | imm |  |  |  |  |  |  |  |  |  |  | funct2 |  | opcode |  |  |

### Opcodes de las instrucciones

| Instrucción (R) |   opcode | funct4 |
|------------|-----------------|-------|
| ADD        | 000    | 0000     |
| SUB        | 000    | 0001     |
| AND        | 000    | 0010     |
| OR         | 000    | 0011     |
| XOR        | 000    | 0100     |
| SLL        | 000    | 0101     |
| SLR        | 000    | 0110     |
| MV         | 000    | 0111     |

| Instrucción (I) | opcode | mem |
|------------|--------|-----|
| LD         | 001    | 1   |
| LIM        | 001    | 0   |

| Instrucción (S) | opcode |
|------------|--------|
| STR        | 010    |

| Instrucción (J) | opcode | funct2 |
|------------|--------|--------|
| JMP        | 100    | 00     |
| CALL       | 100    | 01     |
| RET        | 100    | 10     |

| Instrucción (B) | opcode | funct2 | eq |
|------------|--------|--------|----|
| BEQ / BNE  | 011    | 00     | 0/1|
| BGT / BGE  | 011    | 01     | 0/1|
| BLT / BLE  | 011    | 10     | 0/1|

## Key Vault

- Memoria segura interna
- 4 llaves de 128 bits
- No accesible como memoria normal
- Solo accesible mediante instrucciones

---

## Modelo de Seguridad

- AUTH requerido para:
  - LOADKEY
  - TEAENC
  - TEADEC

- Si AUTH = 0:
  - Se genera excepción
  - Se bloquea la instrucción

---

## TEA (Tiny Encryption Algorithm)

- Bloque: 64 bits
- Llave: 128 bits
- Rondas: 32
- Constante: 0x9e3779b9

---

## Ejecución

- ALU: 1 ciclo
- Memoria: etapa MEM
- TEA: multi-cycle
- Puede generar stall en pipeline

---

## Notas

- Arquitectura tipo RISC (load/store)
- Seguridad integrada en hardware
- Separación entre memoria normal y Key Vault
- Diseño enfocado en eficiencia y protección de datos
