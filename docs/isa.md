# Referencia del ISA GAEM

## 1. Descripción General

GAEM es una arquitectura de conjunto de instrucciones de 32 bits, de estilo RISC, diseñada para un procesador educativo implementado en SystemVerilog. El ISA incluye instrucciones aritméticas y lógicas, operaciones con inmediatos, acceso a memoria, control de flujo y una extensión de seguridad para autenticación, almacenamiento seguro de llaves y primitivas criptográficas.

El objetivo principal del ISA es mantener un procesador simple, modular y fácil de simular, pero con soporte suficiente para aplicaciones relacionadas con seguridad informática, como cifrado de archivos, manejo protegido de llaves y operaciones criptográficas aceleradas por hardware.

---

## 2. Propiedades Generales

| Propiedad | Valor | Notas |
| --- | --- | --- |
| Ancho de instrucción | 32 bits / 4 bytes | Instrucciones de tamaño fijo |
| Ancho de palabra | 32 bits / 4 bytes | Tamaño principal de dato |
| Número de registros | 32 | Desde `x0` hasta `x31` |
| Ancho del Program Counter | 32 bits | PC direccionado por bytes |
| Incremento normal del PC | `PC + 4` | Una instrucción por palabra |
| Alineamiento de memoria | 4 bytes | `lw` y `sw` trabajan con palabras de 32 bits |
| Direccionamiento de memoria | 32 bits | Dirección calculada mediante registro base + offset |
| Extensión de inmediatos | Extensión de signo salvo indicación contraria | U-type se maneja por separado |
| Opcode de seguridad | `0x06` | Usado por `auth`, `ldk`, `addk`, `xork`, `tea` |

---

## 3. Reglas de Acceso a Memoria

El ISA soporta acceso a memoria por palabras mediante las instrucciones `lw` y `sw`.

Sintaxis en ensamblador:

    lw rd, offset(rs1)
    sw rs2, offset(rs1)

La dirección efectiva se calcula como:

    address = R[rs1] + sign_extend(offset)

Los accesos a memoria deben estar alineados a 4 bytes. Si una dirección no está alineada a 4 bytes, el comportamiento queda indefinido en la implementación actual.

---

## 4. Formatos de Instrucción

Todas las instrucciones tienen un tamaño fijo de 32 bits.

### 4.1 Formato R-type

El formato R-type se utiliza para operaciones ALU entre registros.

    [31:25 funct7][24:20 rs2][19:15 rs1][14:12 funct3][11:7 rd][6:0 opcode]

| Campo | Bits | Descripción |
| --- | --- | --- |
| `funct7` | `[31:25]` | Selector extendido de operación |
| `rs2` | `[24:20]` | Registro fuente 2 |
| `rs1` | `[19:15]` | Registro fuente 1 |
| `funct3` | `[14:12]` | Selector principal de operación |
| `rd` | `[11:7]` | Registro destino |
| `opcode` | `[6:0]` | Grupo principal de instrucción |

Ejemplo:

    add x5, x3, x4

Significado:

    R[x5] = R[x3] + R[x4]

---

### 4.2 Formato I-type

El formato I-type se utiliza para operaciones inmediatas y para la instrucción `lw`.

    [31:20 imm[11:0]][19:15 rs1][14:12 funct3][11:7 rd][6:0 opcode]

| Campo | Bits | Descripción |
| --- | --- | --- |
| `imm` | `[31:20]` | Inmediato con signo de 12 bits |
| `rs1` | `[19:15]` | Registro fuente o registro base |
| `funct3` | `[14:12]` | Selector de operación |
| `rd` | `[11:7]` | Registro destino |
| `opcode` | `[6:0]` | Grupo principal de instrucción |

Ejemplo:

    addi x5, x3, 10

Significado:

    R[x5] = R[x3] + 10

---

### 4.3 Formato S-type

El formato S-type se utiliza para operaciones de almacenamiento en memoria.

    [31:25 imm[11:5]][24:20 rs2][19:15 rs1][14:12 funct3][11:7 imm[4:0]][6:0 opcode]

| Campo | Bits | Descripción |
| --- | --- | --- |
| `imm[11:5]` | `[31:25]` | Bits superiores del inmediato |
| `rs2` | `[24:20]` | Registro que contiene el dato a guardar |
| `rs1` | `[19:15]` | Registro base |
| `funct3` | `[14:12]` | Selector de operación de almacenamiento |
| `imm[4:0]` | `[11:7]` | Bits inferiores del inmediato |
| `opcode` | `[6:0]` | Grupo principal de instrucción |

Ejemplo:

    sw x5, 0(x10)

Significado:

    Mem[R[x10] + 0] = R[x5]

---

### 4.4 Formato B-type

El formato B-type se utiliza para saltos condicionales.

    [31:25 imm[11:5]][24:20 rs2][19:15 rs1][14:12 funct3][11:7 imm[4:0]][6:0 opcode]

Los saltos utilizan offsets relativos al PC.

Ejemplo:

    blt x10, x11, loop

Significado:

    if R[x10] < R[x11]:
        PC = PC + offset
    else:
        PC = PC + 4

---

### 4.5 Formato J-type

El formato J-type se utiliza para saltos.

    [31:25 imm[11:5]][24:20 rs2][19:15 rs1][14:12 funct3][11:7 imm[4:0]][6:0 opcode]

Este formato reutiliza una distribución similar al formato S-type para el inmediato. El comportamiento depende del campo `funct3`.

Instrucciones soportadas:

    j label
    jal rd, label
    jr rs1

Para `j` y `jal`, el inmediato se interpreta como un offset relativo al PC. Para `jr`, el PC se carga desde un registro.

---

### 4.6 Formato U-type

El formato U-type se utiliza para cargar mitades de 16 bits de un inmediato de 32 bits.

    [31:16 imm[15:0]][14:12 funct3][11:7 rd][6:0 opcode]

Instrucciones soportadas:

    luhw rd, imm16
    llhw rd, imm16

Significado:

    luhw: R[rd][31:16] = imm16
    llhw: R[rd][15:0]  = imm16

Estas instrucciones son utilizadas principalmente por el ensamblador para implementar la pseudoinstrucción:

    li rd, imm32

que se expande como:

    luhw rd, imm[31:16]
    llhw rd, imm[15:0]

---

### 4.7 Formato SEC-type

El formato SEC-type se utiliza para instrucciones de seguridad y operaciones criptográficas.

Las instrucciones SEC reutilizan un formato similar al R-type:

    [31:25 funct7][24:20 rs2][19:15 rs1][14:12 funct3][11:7 rd][6:0 opcode]

En la implementación actual:

    opcode = 0x06

| Campo | Bits | Descripción |
| --- | --- | --- |
| `funct7` | `[31:25]` | Actualmente codificado como cero por el ensamblador |
| `rs2` | `[24:20]` | Segundo registro fuente o fuente del índice de bóveda |
| `rs1` | `[19:15]` | Primer registro fuente |
| `funct3` | `[14:12]` | Selector de operación de seguridad |
| `rd` | `[11:7]` | Registro destino cuando aplica |
| `opcode` | `[6:0]` | Opcode de seguridad `0x06` |

Las instrucciones de seguridad están controladas por un bit interno de autenticación. Las operaciones que modifican o utilizan la bóveda de llaves requieren autenticación exitosa mediante la instrucción `auth`.

---

## 5. Manejo de Inmediatos

### 5.1 Regla General

Salvo que se indique lo contrario, los inmediatos se extienden con signo a 32 bits antes de ser utilizados.

    imm_ext = sign_extend(imm)

### 5.2 Inmediato I-type

Utilizado por:

    addi, xori, slli, srli, lw

Formato:

    imm[11:0]

Interpretación:

    imm_ext = sign_extend(imm[11:0])

### 5.3 Inmediato S-type

Utilizado por:

    sw

Formato:

    imm[11:5] | imm[4:0]

Reconstrucción:

    imm = {imm[11:5], imm[4:0]}

Interpretación:

    imm_ext = sign_extend(imm)

### 5.4 Inmediato B-type

Utilizado por:

    beq, bne, bgt, blt, bge, ble

Los saltos condicionales utilizan offsets relativos al PC.

    if condition:
        PC = PC + offset
    else:
        PC = PC + 4

El ensamblador resuelve las etiquetas como:

    offset = label_address - current_pc

No se aplica desplazamiento implícito al offset.

### 5.5 Inmediato J-type

Utilizado por:

    j, jal, jr

Para `j` y `jal`, el offset es relativo al PC:

    PC = PC + offset

Para `jr`, el PC se carga desde un registro:

    PC = R[rs1]

### 5.6 Inmediato U-type

Utilizado por:

    luhw, llhw

El inmediato es de 16 bits y se inserta directamente en una mitad del registro destino.

---

## 6. Banco de Registros

El ISA cuenta con 32 registros de propósito general, cada uno de 32 bits.

| Registro | Alias | Propósito | Guardado por |
| --- | --- | --- | --- |
| `x0` | `zero` | Constante cero | Hardware |
| `x1` | `ra` | Dirección de retorno | Caller |
| `x2` | `sp` | Stack pointer | Callee |
| `x3-x9` | `a0-a6` | Argumentos y valores de retorno | Caller |
| `x10-x19` | `s0-s9` | Registros guardados / propósito general | Callee |
| `x20` | `sr` | Registro asociado a estado/seguridad por convención | Especial |
| `x21-x25` | `t0-t4` | Registros temporales | Caller |
| `x26-x29` | `s10-s13` | Registros guardados adicionales | Callee |
| `x30` | `delta` | Constante delta para TEA por convención | Especial |
| `x31` | `vp` | Puntero de bóveda por convención | Callee |

### Notas

- `x0` se trata como registro cero por convención.
- El ensamblador acepta nombres directos como `x5` y alias como `ra`, `sp`, `a0`, `s0`, `t0`, `delta` y `vp`.
- El registro `x30` se reserva por convención para la constante delta de TEA, pero no está cableado directamente por el encoding.
- El registro `x31` se reserva por convención como puntero de bóveda, pero el encoding SEC actual usa `rs2[3:0]` como fuente del índice de la bóveda.

---

## 7. Mapa de Opcodes

| Grupo de instrucciones | Opcode Hex | Opcode Binario | Instrucciones principales |
| --- | --- | --- | --- |
| ALU R-type | `0x00` | `0000000` | `add`, `sub`, `mul`, `div`, `rem`, `and`, `or`, `xor`, `sll`, `srl` |
| ALU I-type | `0x01` | `0000001` | `addi`, `xori`, `slli`, `srli` |
| Store | `0x02` | `0000010` | `sw` |
| Load | `0x03` | `0000011` | `lw` |
| Branch | `0x04` | `0000100` | `beq`, `bne`, `bgt`, `blt`, `bge`, `ble` |
| U-type | `0x05` | `0000101` | `luhw`, `llhw` |
| Seguridad | `0x06` | `0000110` | `auth`, `ldk`, `addk`, `xork`, `tea` |
| Jump | `0x07` | `0000111` | `j`, `jal`, `jr` |

---

## 8. Hoja de Referencia de Instrucciones

### 8.1 Instrucciones ALU R-type

| Instrucción | Tipo | Opcode | funct3 | funct7 | Operación |
| --- | --- | --- | --- | --- | --- |
| `add rd, rs1, rs2` | R | `0x00` | `000` | `0000000` | `R[rd] = R[rs1] + R[rs2]` |
| `sub rd, rs1, rs2` | R | `0x00` | `001` | `0000000` | `R[rd] = R[rs1] - R[rs2]` |
| `mul rd, rs1, rs2` | R | `0x00` | `000` | `0000001` | `R[rd] = R[rs1] * R[rs2]` |
| `div rd, rs1, rs2` | R | `0x00` | `001` | `0000001` | `R[rd] = R[rs1] / R[rs2]` |
| `rem rd, rs1, rs2` | R | `0x00` | `010` | `0000001` | `R[rd] = R[rs1] % R[rs2]` |
| `and rd, rs1, rs2` | R | `0x00` | `010` | `0000000` | `R[rd] = R[rs1] & R[rs2]` |
| `or rd, rs1, rs2` | R | `0x00` | `011` | `0000000` | `R[rd] = R[rs1] \| R[rs2]` |
| `xor rd, rs1, rs2` | R | `0x00` | `100` | `0000000` | `R[rd] = R[rs1] ^ R[rs2]` |
| `sll rd, rs1, rs2` | R | `0x00` | `101` | `0000000` | `R[rd] = R[rs1] << R[rs2]` |
| `srl rd, rs1, rs2` | R | `0x00` | `110` | `0000000` | `R[rd] = R[rs1] >> R[rs2]` |

### 8.2 Instrucciones I-type

| Instrucción | Tipo | Opcode | funct3 | Operación |
| --- | --- | --- | --- | --- |
| `addi rd, rs1, imm` | I | `0x01` | `000` | `R[rd] = R[rs1] + sign_extend(imm)` |
| `xori rd, rs1, imm` | I | `0x01` | `001` | `R[rd] = R[rs1] ^ sign_extend(imm)` |
| `slli rd, rs1, imm` | I | `0x01` | `010` | `R[rd] = R[rs1] << imm` |
| `srli rd, rs1, imm` | I | `0x01` | `011` | `R[rd] = R[rs1] >> imm` |
| `lw rd, offset(rs1)` | I | `0x03` | `100` | `R[rd] = Mem[R[rs1] + offset]` |

### 8.3 Instrucciones S-type

| Instrucción | Tipo | Opcode | funct3 | Operación |
| --- | --- | --- | --- | --- |
| `sw rs2, offset(rs1)` | S | `0x02` | `000` | `Mem[R[rs1] + offset] = R[rs2]` |

### 8.4 Instrucciones Branch

| Instrucción | Tipo | Opcode | funct3 | Operación |
| --- | --- | --- | --- | --- |
| `beq rs1, rs2, offset/label` | B | `0x04` | `000` | Salta si `R[rs1] == R[rs2]` |
| `bne rs1, rs2, offset/label` | B | `0x04` | `001` | Salta si `R[rs1] != R[rs2]` |
| `bgt rs1, rs2, offset/label` | B | `0x04` | `010` | Salta si `R[rs1] > R[rs2]` |
| `blt rs1, rs2, offset/label` | B | `0x04` | `011` | Salta si `R[rs1] < R[rs2]` |
| `bge rs1, rs2, offset/label` | B | `0x04` | `100` | Salta si `R[rs1] >= R[rs2]` |
| `ble rs1, rs2, offset/label` | B | `0x04` | `101` | Salta si `R[rs1] <= R[rs2]` |

### 8.5 Instrucciones Jump

| Instrucción | Tipo | Opcode | funct3 | Operación |
| --- | --- | --- | --- | --- |
| `j label` | J | `0x07` | `000` | `PC = PC + offset` |
| `jal rd, label` | J | `0x07` | `001` | `R[rd] = PC + 4; PC = PC + offset` |
| `jr rs1` | J | `0x07` | `010` | `PC = R[rs1]` |

### 8.6 Instrucciones U-type

| Instrucción | Tipo | Opcode | funct3 | Operación |
| --- | --- | --- | --- | --- |
| `luhw rd, imm16` | U | `0x05` | `000` | `R[rd][31:16] = imm16` |
| `llhw rd, imm16` | U | `0x05` | `001` | `R[rd][15:0] = imm16` |

### 8.7 Instrucciones de Seguridad

| Instrucción | Tipo | Opcode | funct3 | Operación |
| --- | --- | --- | --- | --- |
| `auth rs1` | SEC | `0x06` | `000` | Autentica el modo seguro usando `R[rs1]` |
| `ldk rs1, rs2` | SEC | `0x06` | `001` | Guarda `R[rs1]` en `vault[R[rs2][3:0]]` si hay autenticación |
| `addk rd, rs1, rs2` | SEC | `0x06` | `010` | `R[rd] = R[rs1] + vault[R[rs2][3:0]]` |
| `xork rd, rs1, rs2` | SEC | `0x06` | `011` | `R[rd] = R[rs1] ^ vault[R[rs2][3:0]]` |
| `tea rd, rs1, rs2` | SEC | `0x06` | `100` | Ejecuta una primitiva estilo TEA usando `R[rs1]` y una llave seleccionada desde la bóveda |

---

## 9. Extensión de Seguridad

La extensión de seguridad agrega soporte para autenticación, almacenamiento seguro de llaves y operaciones aritméticas/lógicas dependientes de llaves.

Las instrucciones de seguridad implementadas son:

    auth
    ldk
    addk
    xork
    tea

No existen instrucciones independientes `enc` o `dec` dentro del ISA. El cifrado y descifrado se implementan como programas en ensamblador que utilizan las instrucciones de seguridad.

### 9.1 Autenticación

La instrucción `auth` habilita las operaciones seguras cuando se proporciona el valor de contraseña correcto.

Sintaxis:

    auth rs1

Ejemplo:

    li      x1, 0xDEADBEEF
    auth    x1

Si la autenticación es correcta, el procesador habilita el estado interno de autenticación. Si falla, las operaciones sobre la bóveda de llaves permanecen bloqueadas.

### 9.2 Bóveda de Llaves

La bóveda de llaves es una estructura segura de almacenamiento en hardware. No se accede a ella mediante instrucciones normales como `lw` o `sw`.

Las llaves se escriben mediante:

    ldk rs1, rs2

Significado:

    vault[R[rs2][3:0]] = R[rs1]

Solo el código autenticado puede modificar la bóveda.

Ejemplo:

    li      x1, 0xDEADBEEF
    auth    x1

    li      x10, 0x33333333
    li      x11, 0
    ldk     x10, x11

Esto escribe:

    vault[0] = 0x33333333

### 9.3 Suma Dependiente de Llave

Sintaxis:

    addk rd, rs1, rs2

Significado:

    R[rd] = R[rs1] + vault[R[rs2][3:0]]

Ejemplo:

    li      x7, 0xAA55AA55
    li      x6, 0
    addk    x8, x7, x6

### 9.4 XOR Dependiente de Llave

Sintaxis:

    xork rd, rs1, rs2

Significado:

    R[rd] = R[rs1] ^ vault[R[rs2][3:0]]

Ejemplo:

    li      x1, 0xDEADBEEF
    auth    x1

    li      x2, 0xA5A5A5A5
    li      x3, 0
    ldk     x2, x3

    lw      x4, 0(x10)
    xork    x5, x4, x3
    sw      x5, 0(x10)

Esta operación se utiliza en los programas de ejemplo de cifrado y descifrado mediante XOR.

### 9.5 Primitiva de Ronda TEA

Sintaxis:

    tea rd, rs1, rs2

Comportamiento abstracto:

    R[rd] = TEA_round_primitive(R[rs1], vault[R[rs2][3:0]])

La ALU de seguridad implementa una primitiva inspirada en TEA basada en desplazamientos, suma, XOR y una llave proveniente de la bóveda.

Conceptualmente, la operación sigue esta estructura:

    ((a << 4) + key) ^ b ^ ((a >> 5) + key)

donde `a` proviene de `rs1` y `key` se obtiene desde la bóveda de llaves. Esta instrucción se usa como una primitiva de aceleración criptográfica, no como una instrucción de cifrado completo. El cifrado y descifrado completo se construyen en ensamblador mediante ciclos, accesos a memoria, `auth`, `ldk` y operaciones de seguridad.

---

## 10. Pseudoinstrucciones

El ensamblador soporta varias pseudoinstrucciones.

| Pseudoinstrucción | Expansión | Significado |
| --- | --- | --- |
| `nop` | `addi x0, x0, 0` | Operación nula |
| `li rd, imm32` | `luhw rd, imm[31:16]`; `llhw rd, imm[15:0]` | Cargar inmediato de 32 bits |
| `mv rd, rs` | `addi rd, rs, 0` | Copiar registro |
| `call label` | `jal x1, label` | Llamar subrutina |
| `ret` | `jr x1` | Retornar de subrutina |

---

## 11. Sintaxis Assembly

### 11.1 ALU registro-registro

    add rd, rs1, rs2
    sub rd, rs1, rs2
    xor rd, rs1, rs2

### 11.2 ALU inmediata

    addi rd, rs1, imm
    xori rd, rs1, imm

### 11.3 Memoria

    lw rd, offset(rs1)
    sw rs2, offset(rs1)

### 11.4 Branch

    beq rs1, rs2, label
    bne rs1, rs2, label
    blt rs1, rs2, label

### 11.5 Jump

    j label
    jal rd, label
    jr rs1

### 11.6 Seguridad

    auth rs1
    ldk rs1, rs2
    addk rd, rs1, rs2
    xork rd, rs1, rs2
    tea rd, rs1, rs2

---

## 12. Programas de Ejemplo

### 12.1 Prueba de Autenticación y Bóveda

    li      x10, 0x11111111
    li      x11, 0
    ldk     x10, x11

    li      x12, 0x00000000
    addk    x13, x12, x11

    li      x1, 0xCAFEBABE
    auth    x1

    li      x10, 0x22222222
    ldk     x10, x11

    li      x12, 0x00000000
    addk    x14, x12, x11

    li      x1, 0xDEADBEEF
    auth    x1

    li      x10, 0x33333333
    ldk     x10, x11

    li      x12, 0x00000000
    addk    x15, x12, x11

    end:
        j   end

Este programa valida que el acceso a la bóveda esté bloqueado antes de autenticarse, que continúe bloqueado con una contraseña incorrecta y que se habilite cuando se usa la contraseña correcta.

Este ejemplo autentica el procesador, escribe una llave en la bóveda y aplica XOR con esa llave a cada palabra de una región de memoria.

Debido a que XOR es una operación auto-inversa, el mismo algoritmo puede utilizarse para descifrar.

### 12.2 Programa de Cifrado Estilo TEA

Los programas estilo TEA no son instrucciones individuales del ISA. Son rutinas en ensamblador que combinan:

    auth
    ldk
    lw
    sw
    add
    sub
    bne
    blt
    tea

La estructura general es:

    autenticar
    inicializar la bóveda de llaves
    para cada bloque de memoria de 64 bits:
        cargar v0 y v1
        ejecutar 32 rondas
        guardar v0 y v1

La instrucción `tea` proporciona aceleración por hardware para una primitiva de ronda estilo TEA, mientras que los ciclos y el recorrido de memoria se manejan por software.

---

## 13. Justificación de Diseño

### 13.1 Instrucciones de 32 bits

El uso de instrucciones de tamaño fijo simplifica la etapa de fetch, la decodificación y la actualización del PC. Como cada instrucción ocupa 4 bytes, el incremento normal del PC es:

    PC = PC + 4

Esto reduce la complejidad de control en la etapa de búsqueda de instrucciones.

### 13.2 Banco de Registros Estilo RISC

El ISA utiliza 32 registros de propósito general de 32 bits. Esto proporciona suficientes registros para operaciones aritméticas, direccionamiento de memoria, contadores de ciclo, valores temporales, estado de rutinas de seguridad e intermediarios criptográficos.

El diseño evita modos de direccionamiento complejos y mantiene simple el datapath.

### 13.3 Separación por Grupos de Instrucciones

El mapa de opcodes separa las instrucciones en grupos funcionales:

    ALU
    ALU inmediata
    Memoria
    Branch
    Construcción de inmediatos U-type
    Seguridad
    Jump

Esto simplifica la unidad de control, ya que el opcode identifica inmediatamente la clase principal de instrucción.

### 13.4 Construcción de Inmediatos con U-type

El ISA utiliza `luhw` y `llhw` para construir constantes de 32 bits a partir de dos mitades de 16 bits. Esto evita requerir un campo inmediato de 32 bits dentro del formato de instrucción.

El ensamblador oculta esta complejidad mediante la pseudoinstrucción:

    li rd, imm32

### 13.5 Bóveda de Llaves Segura

La bóveda de llaves separa las llaves criptográficas de la memoria de datos normal. Las llaves no pueden accederse mediante `lw` o `sw`; solo se manipulan mediante instrucciones de seguridad.

Este diseño reduce la exposición accidental de material secreto y modela un mecanismo básico de raíz de confianza.

### 13.6 Control de Autenticación

Las operaciones de seguridad requieren autenticación previa. La instrucción `auth` activa un estado interno de autenticación únicamente si se proporciona el valor correcto.

Esto evita escrituras no autorizadas en la bóveda y bloquea operaciones dependientes de llaves cuando el procesador no está autenticado.

### 13.7 Aceleración TEA como Primitiva

El ISA no implementa una instrucción completa de cifrado o descifrado. En su lugar, proporciona la instrucción `tea`, que acelera parte de una ronda estilo TEA.

Este diseño mantiene un balance entre eficiencia y complejidad:

- Una instrucción TEA completa de 32 rondas aumentaría la complejidad del hardware.
- Una primitiva pequeña mantiene simple la ALU de seguridad.
- El software puede implementar rutinas completas de cifrado y descifrado mediante ciclos.

Esto sigue el principio RISC de utilizar instrucciones simples que se combinan para construir comportamientos más complejos.

---

## 14. Green Sheet

### ISA Principal

| Categoría | Instrucciones |
| --- | --- |
| ALU R-type | `add`, `sub`, `mul`, `div`, `rem`, `and`, `or`, `xor`, `sll`, `srl` |
| ALU I-type | `addi`, `xori`, `slli`, `srli` |
| Memoria | `lw`, `sw` |
| Branch | `beq`, `bne`, `bgt`, `blt`, `bge`, `ble` |
| Jump | `j`, `jal`, `jr` |
| U-type | `luhw`, `llhw` |
| Seguridad | `auth`, `ldk`, `addk`, `xork`, `tea` |

### Resumen de Opcodes

| Opcode | Binario | Clase de instrucción |
| --- | --- | --- |
| `0x00` | `0000000` | ALU R-type |
| `0x01` | `0000001` | ALU I-type |
| `0x02` | `0000010` | Store |
| `0x03` | `0000011` | Load |
| `0x04` | `0000100` | Branch |
| `0x05` | `0000101` | U-type |
| `0x06` | `0000110` | Seguridad |
| `0x07` | `0000111` | Jump |

### Resumen funct3/funct7 R-type

| Instrucción | funct3 | funct7 |
| --- | --- | --- |
| `add` | `000` | `0000000` |
| `sub` | `001` | `0000000` |
| `mul` | `000` | `0000001` |
| `div` | `001` | `0000001` |
| `rem` | `010` | `0000001` |
| `and` | `010` | `0000000` |
| `or` | `011` | `0000000` |
| `xor` | `100` | `0000000` |
| `sll` | `101` | `0000000` |
| `srl` | `110` | `0000000` |

### Resumen funct3 I-type

| Instrucción | funct3 |
| --- | --- |
| `addi` | `000` |
| `xori` | `001` |
| `slli` | `010` |
| `srli` | `011` |
| `lw` | `100` |

### Resumen funct3 Branch

| Instrucción | funct3 |
| --- | --- |
| `beq` | `000` |
| `bne` | `001` |
| `bgt` | `010` |
| `blt` | `011` |
| `bge` | `100` |
| `ble` | `101` |

### Resumen funct3 Jump

| Instrucción | funct3 |
| --- | --- |
| `j` | `000` |
| `jal` | `001` |
| `jr` | `010` |

### Resumen funct3 Seguridad

| funct3 | Instrucción | Descripción |
| --- | --- | --- |
| `000` | `auth` | Autentica el modo seguro |
| `001` | `ldk` | Guarda una llave en la bóveda |
| `010` | `addk` | Suma un valor con una llave de la bóveda |
| `011` | `xork` | Aplica XOR entre un valor y una llave de la bóveda |
| `100` | `tea` | Primitiva de ronda estilo TEA |

---

## 15. Notas y Limitaciones

- `enc` y `dec` no son instrucciones del ISA. Se implementan como programas en ensamblador.
- `ldk` escribe un valor dentro de la bóveda; no carga una llave desde la bóveda hacia un registro general.
- La bóveda de llaves se accede indirectamente mediante instrucciones de seguridad.
- Los offsets de branch y jump son relativos al PC.
- El ensamblador expande `li` en dos instrucciones U-type.
- El soporte TEA actual se implementa como una primitiva de hardware más ciclos en software, no como una instrucción completa de cifrado por bloque.
- Las instrucciones de seguridad requieren autenticación antes de modificar o utilizar datos protegidos de la bóveda.
