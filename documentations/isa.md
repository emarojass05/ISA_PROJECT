# ISA – RISC 32-bit con Extensiones de Seguridad

---

## Flujo general

CPU → AUTH → habilita acceso seguro  
CPU → KeyVault (solo instrucciones especiales)  
CPU ↔ Memoria  
CPU → TEA → Memoria  
Registros ↔ ALU  

---

## Registros

- 8 registros de propósito general (32 bits)
- R0 = 0 (hardwired)
- R6 = SP (stack pointer)
- R7 = RA (return address)

---

## Program Counter

- PC de 32 bits
- Incremento: PC + 4
- Modificado por saltos y branches

---

## Registro de Estado

- AUTH flag
- Controla acceso a:
  - Key Vault
  - Instrucciones de cifrado

---

## Tipos de Instrucción

### Tipo R (ALU)

Formato:
[ opcode | rd | rs1 | rs2 | unused ]

Instrucciones:
- ADD rd, rs1, rs2
- SUB rd, rs1, rs2
- AND rd, rs1, rs2
- OR rd, rs1, rs2
- XOR rd, rs1, rs2
- SLL rd, rs1, rs2
- SRL rd, rs1, rs2

---

### Tipo I (Inmediatos / Memoria)

Formato:
[ opcode | rd | rs1 | immediate ]

Instrucciones:
- ADDI rd, rs1, imm
- LOAD rd, offset(rs1)

---

### Tipo Memoria (Store)

Formato:
[ opcode | rs2 | rs1 | offset ]

Instrucciones:
- STORE rs2, offset(rs1)

---

### Tipo Branch (Control de flujo condicional)

Formato:
[ opcode | rs1 | rs2 | offset ]

Instrucciones:
- BEQ rs1, rs2, offset
- BNE rs1, rs2, offset
- BLT rs1, rs2, offset
- BGE rs1, rs2, offset

---

### Tipo Jump (Control de flujo incondicional)

Formato:
[ opcode | address ]

Instrucciones:
- JMP address
- CALL address
- RET

---

### Tipo Seguridad (Vault / Cifrado)

Formato:
[ opcode | campos específicos ]

Instrucciones:

#### Autenticación
- AUTH rs  
Activa modo seguro (AUTH = 1)

#### Manejo de llaves
- LOADKEY k, rs1, rs2, rs3, rs4  
Carga llave de 128 bits en el Key Vault

#### Cifrado TEA
- TEAENC rs1, rs2, k  
Cifra bloque de 64 bits

- TEADEC rs1, rs2, k  
Descifra bloque de 64 bits

---

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
