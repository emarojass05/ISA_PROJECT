# ISA Design – 32-bit RISC with Security Extensions (TEA + Key Vault)

## 1. Overview
- Arquitectura: RISC de 32 bits
- Tamaño de instrucción: 32 bits
- Registros: 8 registros de propósito general (R0–R7), 32 bits cada uno
- Program Counter (PC): 32 bits
- Registro de estado: incluye bandera de autenticación (AUTH)

---

## 2. Register File

| Registro | Descripción |
|----------|------------|
| R0–R7    | Registros generales de 32 bits |

---

## 3. Instruction Encoding

Todas las instrucciones tienen 32 bits.

### Tipo R (ALU)
[ opcode(6) | rd(3) | rs1(3) | rs2(3) | unused(17) ]

### Tipo I (inmediatos / memoria)
[ opcode(6) | rd(3) | rs1(3) | immediate(20) ]

### Tipo B (branch)
[ opcode(6) | rs1(3) | rs2(3) | offset(20) ]

### Tipo J (jump)
[ opcode(6) | address(26) ]

### Tipo S (seguridad)
[ opcode(6) | rd(3) | rs(3) | key_id(2) | unused(18) ]

---

## 4. Instruction Set

### 4.1 ALU Instructions (Tipo R)

| Instrucción           | Descripción            |
|----------------------|------------------------|
| ADD rd, rs1, rs2     | rd = rs1 + rs2         |
| SUB rd, rs1, rs2     | rd = rs1 - rs2         |
| AND rd, rs1, rs2     | rd = rs1 & rs2         |
| OR  rd, rs1, rs2     | rd = rs1 | rs2         |
| XOR rd, rs1, rs2     | rd = rs1 ^ rs2         |

---

### 4.2 Immediate Instructions (Tipo I)

| Instrucción           | Descripción            |
|----------------------|------------------------|
| ADDI rd, rs1, imm    | rd = rs1 + imm         |

---

### 4.3 Memory Instructions (Tipo I)

| Instrucción           | Descripción            |
|----------------------|------------------------|
| LOAD rd, addr        | rd = MEM[addr]         |
| STORE rs, addr       | MEM[addr] = rs         |

---

### 4.4 Control Flow (Tipo B / J)

| Instrucción           | Descripción                          |
|----------------------|--------------------------------------|
| BEQ rs1, rs2, offset | Si rs1 == rs2 → PC += offset         |
| BNE rs1, rs2, offset | Si rs1 != rs2 → PC += offset         |
| JMP address          | PC = address                         |

---

### 4.5 Security Instructions (Tipo S)

#### Key Vault

| Instrucción        | Descripción                          |
|-------------------|--------------------------------------|
| LOADKEY k, rs     | Guarda llave en la posición k        |
| AUTH rs           | Activa estado de autenticación       |

---

#### TEA Encryption

| Instrucción           | Descripción                              |
|----------------------|------------------------------------------|
| TEAENC rd, rs, k     | rd = TEA_encrypt(rs, key[k])             |
| TEADEC rd, rs, k     | rd = TEA_decrypt(rs, key[k])             |

---

## 5. Key Vault (Secure Memory)

- Capacidad: 4 llaves
- Tamaño por llave: 128 bits
- Acceso: solo mediante instrucciones especiales
- No accesible como memoria normal
- No se pueden leer llaves directamente

---

## 6. Security Model

- Se requiere ejecutar AUTH antes de:
  - LOADKEY
  - TEAENC
  - TEADEC

- Si no está autenticado:
  → Se genera excepción o error

---

## 7. TEA Algorithm Support

- Algoritmo: Tiny Encryption Algorithm (TEA)
- Tamaño de bloque: 64 bits
- Llave: 128 bits
- Rondas: 32
- Constante:
DELTA = 0x9e3779b9

---

## 8. Execution Semantics (Ejemplos)

ADD R1, R2, R3  
→ R1 = R2 + R3  

LOAD R1, 0x1000  
→ R1 = MEM[0x1000]  

STORE R1, 0x2000  
→ MEM[0x2000] = R1  

TEAENC R1, R2, K0  
→ R1 = TEA_encrypt(R2, key[0])  

---

## 9. Example Program

LOAD R1, 0x1000  
AUTH R3  
LOADKEY K0, R4  
TEAENC R2, R1, K0  
STORE R2, 0x2000  

---

## 10. Notes

- Arquitectura diseñada para simplicidad y eficiencia
- Balance entre hardware y funcionalidad
- Instrucciones de seguridad optimizadas para cifrado