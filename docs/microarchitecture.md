# Microarquitectura — SecuRISC-32

## 1. Visión general

SecuRISC-32 implementa un procesador RISC de 32 bits en SystemVerilog con una microarquitectura organizada en cinco etapas lógicas:

    IF → ID → EX → MEM → WB

La implementación utiliza registros intermedios de pipeline para separar las etapas principales del datapath:

    IF/ID
    ID/EX
    EX/MEM
    MEM/WB

El procesador trabaja con una arquitectura tipo Harvard, ya que la memoria de instrucciones y la memoria de datos se modelan como módulos separados. Esto facilita la simulación con `iverilog`, permite cargar programas en la memoria de instrucciones mediante archivos `.hex` y permite cargar archivos externos en la memoria de datos para pruebas de cifrado.

| Aspecto | Decisión de diseño |
| --- | --- |
| Tipo de procesador | RISC de 32 bits |
| Organización | Pipeline lógico de 5 etapas |
| Etapas | IF, ID, EX, MEM, WB |
| Memoria | Harvard: IMEM separada de DMEM |
| Ancho de palabra | 32 bits |
| Ancho del PC | 32 bits |
| Banco de registros | 32 registros de 32 bits |
| Memoria de instrucciones | Parametrizable mediante `IMEM_DEPTH` |
| Memoria de datos | Parametrizable mediante `DMEM_DEPTH` |
| Módulo principal | `src/cpu/cpu_top.sv` |
| Definiciones del ISA | `src/cpu/isa_defs.sv` |
| Unidad de seguridad | `src/cpu/sec_alu.sv` |
| Bóveda de llaves | `src/cpu/key_vault.sv` |
| Detección de riesgos | `src/cpu/hazard_unit.sv` |
| Forwarding | `src/cpu/forwarding_unit.sv` |

El diseño separa claramente la lógica de control, el datapath principal, la memoria, la bóveda de llaves y la ALU de seguridad. Esta modularidad permite probar cada componente de forma independiente mediante testbenches específicos.

---

## 2. Diagrama general de bloques

[Datapath](Datapath_PGA1.pdf)

## 3. Módulo principal `cpu_top.sv`

El módulo principal de integración es:

    src/cpu/cpu_top.sv

Este módulo instancia y conecta los principales bloques del procesador:

| Instancia | Módulo | Función |
| --- | --- | --- |
| `u_pc` | `pc.sv` | Mantiene el Program Counter |
| `u_pc_adder` | `pc_adder.sv` | Calcula `PC + 4` |
| `u_imem` | `instr_mem.sv` | Memoria de instrucciones |
| `u_decoder` | `decoder.sv` | Decodifica campos de instrucción |
| `u_cu` | `control_unit.sv` | Genera señales de control |
| `u_rf` | `register_file.sv` | Banco de registros |
| `u_alu` | `alu.sv` | Operaciones aritméticas y lógicas |
| `u_sec_alu` | `sec_alu.sv` | Operaciones de seguridad |
| `u_key_vault` | `key_vault.sv` | Almacenamiento protegido de llaves |
| `u_dmem` | `data_mem.sv` | Memoria de datos |
| `u_hazard` | `hazard_unit.sv` | Control de stalls y flushes |
| `u_forwarding` | `forwarding_unit.sv` | Reenvío de resultados entre etapas |

El módulo recibe como parámetros:

| Parámetro | Descripción |
| --- | --- |
| `XLEN` | Ancho de palabra del procesador, por defecto 32 bits |
| `IMEM_DEPTH` | Profundidad de la memoria de instrucciones |
| `DMEM_DEPTH` | Profundidad de la memoria de datos |
| `PROGRAM_FILE` | Archivo `.hex` usado para inicializar la memoria de instrucciones |
| `INITIAL_MEM` | Archivo `.mem` usado para inicializar la memoria de datos |

---

## 4. Registros de pipeline

La microarquitectura utiliza registros entre etapas definidos como `struct packed` en `isa_defs.sv`.

### 4.1 Registro IF/ID

El registro `if_id_t` guarda la información generada en la etapa de búsqueda de instrucción.

Campos principales:

| Campo | Descripción |
| --- | --- |
| `pc` | PC de la instrucción actual |
| `instr` | Instrucción obtenida desde la memoria de instrucciones |
| `pc_plus4` | Dirección de la siguiente instrucción secuencial |

### 4.2 Registro ID/EX

El registro `id_ex_t` guarda operandos, inmediatos y señales de control necesarias para ejecutar la instrucción.

Campos principales:

| Campo | Descripción |
| --- | --- |
| `pc` | PC de la instrucción |
| `pc_plus4` | PC + 4 |
| `rs1_data` | Dato leído del registro fuente 1 |
| `rs2_data` | Dato leído del registro fuente 2 |
| `k_out` | Dato leído desde la bóveda de llaves |
| `imm_ext` | Inmediato extendido |
| `rs1_addr` | Dirección de `rs1` |
| `rs2_addr` | Dirección de `rs2` |
| `rd_addr` | Dirección del registro destino |
| `pc_src` | Selección de siguiente PC |
| `wb_src` | Fuente para write back |
| `alu_op` | Operación de ALU |
| `sec_op` | Operación de seguridad |
| `reg_write` | Habilita escritura en banco de registros |
| `mem_write` | Habilita escritura en memoria |
| `alu_src` | Selecciona operando B de ALU |
| `branch` | Indica instrucción branch |
| `jal` | Indica salto con enlace |
| `vault_we` | Habilita escritura en la bóveda |

### 4.3 Registro EX/MEM

El registro `ex_mem_t` guarda resultados producidos en la etapa de ejecución.

Campos principales:

| Campo | Descripción |
| --- | --- |
| `alu_result` | Resultado de la ALU |
| `sec_result` | Resultado de la ALU de seguridad |
| `rs2_data` | Dato utilizado para stores |
| `pc_plus4` | PC + 4 |
| `pc_imm` | Dirección objetivo para branch |
| `rd_addr` | Registro destino |
| `wb_src` | Fuente de write back |
| `reg_write` | Escritura en banco de registros |
| `mem_write` | Escritura en memoria |
| `vault_we` | Escritura en bóveda |
| `branch_taken` | Resultado de evaluación de branch |

### 4.4 Registro MEM/WB

El registro `mem_wb_t` guarda los valores disponibles para la etapa de escritura.

Campos principales:

| Campo | Descripción |
| --- | --- |
| `alu_result` | Resultado proveniente de la ALU |
| `sec_result` | Resultado proveniente de `sec_alu` |
| `mem_rdata` | Dato leído desde memoria |
| `pc_plus4` | PC + 4 |
| `rd_addr` | Registro destino |
| `wb_src` | Selector de fuente de write back |
| `reg_write` | Habilita escritura final en registros |

---

## 5. Etapas del datapath

### 5.1 Instruction Fetch

La etapa IF se encarga de obtener la instrucción desde la memoria de instrucciones.

Flujo:

    PC → instr_mem → if_instr
    PC → pc_adder  → PC + 4

El PC se actualiza con `if_pc_next`, siempre que `pc_write` esté habilitado. Si la unidad de riesgos solicita detener el PC, se conserva el valor actual.

Componentes usados:

| Módulo | Función |
| --- | --- |
| `pc.sv` | Registro del PC |
| `pc_adder.sv` | Cálculo de `PC + 4` |
| `instr_mem.sv` | Lectura de instrucción |

El resultado de esta etapa se guarda en `if_id_reg`.

---

### 5.2 Instruction Decode

La etapa ID decodifica la instrucción, lee registros y genera señales de control.

Flujo principal:

    if_id_reg.instr → decoder → opcode, funct3, funct7, rs1, rs2, rd, imm
    opcode/funct3/funct7 → control_unit → señales de control
    rs1/rs2 → register_file → datos fuente

El decoder extrae:

| Campo | Bits |
| --- | --- |
| `opcode` | `[6:0]` |
| `rd` | `[11:7]` |
| `funct3` | `[14:12]` |
| `rs1` | `[19:15]` |
| `rs2` | `[24:20]` |
| `funct7` | `[31:25]` |

El inmediato se extiende según el tipo de instrucción.

Para instrucciones U-type, el diseño usa:

    final_rs1_addr = id_u_load ? id_rd_addr : id_rs1_addr

Esto permite que `luhw` y `llhw` operen sobre el registro destino para construir constantes de 32 bits en dos pasos, como ocurre con la pseudoinstrucción `li`.

El resultado de esta etapa se guarda en `id_ex_reg`.

---

### 5.3 Execute

La etapa EX ejecuta operaciones aritméticas, lógicas, de seguridad y evaluación de branches.

#### Camino ALU

La ALU recibe:

    a = ex_forwarded_rs1
    b = ex_alu_b

El segundo operando se selecciona con:

    ex_alu_b = alu_src ? imm_ext : ex_forwarded_rs2

La ALU produce:

| Señal | Descripción |
| --- | --- |
| `ex_alu_result` | Resultado de operación ALU |
| `ex_Z` | Flag zero |
| `ex_N` | Flag negative |
| `ex_C` | Flag carry |
| `ex_V` | Flag overflow |

#### Camino de seguridad

La ALU de seguridad recibe:

    a      = ex_forwarded_rs1
    b      = ex_forwarded_rs2
    key    = id_ex_reg.k_out
    sec_op = id_ex_reg.sec_op

Produce:

    ex_sec_result

Las operaciones soportadas por `sec_alu` son:

| Operación | Descripción |
| --- | --- |
| `SEC_ADDK` | Suma `a + key` |
| `SEC_XORK` | XOR `a ^ key` |
| `SEC_TEA` | Primitiva estilo TEA |
| `SEC_AUTH` | Controlada fuera de `sec_alu`, mediante `auth_bit` |
| `SEC_LDK` | Escritura en bóveda, no produce write back |

#### Branch

Los branches se evalúan usando los flags producidos por la ALU. Para branches, la unidad de control configura `alu_op = ALU_SUB`, de modo que la comparación se derive del resultado de `rs1 - rs2`.

Condiciones implementadas:

| Branch | Condición |
| --- | --- |
| `beq` | `Z = 1` |
| `bne` | `Z = 0` |
| `blt` | `N != V` |
| `bgt` | `!Z && (N == V)` |
| `bge` | `N == V` |
| `ble` | `Z || (N != V)` |

La dirección objetivo se calcula como:

    ex_pc_imm = id_ex_reg.pc + id_ex_reg.imm_ext

El resultado de esta etapa se guarda en `ex_mem_reg`.

---

### 5.4 Memory Access

La etapa MEM accede a memoria de datos cuando la instrucción es `lw` o `sw`.

Para `lw`:

    mem_rdata = data_mem[ex_mem_reg.alu_result]

Para `sw`:

    data_mem[ex_mem_reg.alu_result] = ex_mem_reg.rs2_data

El módulo usado es:

    src/cpu/data_mem.sv

La señal `mem_write` controla si la operación es escritura. La lectura se usa para la etapa de write back cuando `wb_src = WB_MEM`.

---

### 5.5 Write Back

La etapa WB escribe el resultado final en el banco de registros cuando `reg_write` está activo.

El valor escrito se selecciona mediante `wb_src`.

| Selector | Fuente |
| --- | --- |
| `WB_ALU` | Resultado de ALU |
| `WB_MEM` | Dato leído de memoria |
| `WB_PC4` | PC + 4 |
| `WB_SEC` | Resultado de `sec_alu` |

Flujo:

    wb_data → register_file[rd]

El write back ocurre mediante:

    wd3 = wb_data
    we3 = mem_wb_reg.reg_write
    rs3 = mem_wb_reg.rd_addr

---

## 6. Unidad de control

La unidad de control se encuentra en:

    src/cpu/control_unit.sv

Recibe:

    opcode
    funct3
    funct7

Y genera:

| Señal | Función |
| --- | --- |
| `pc_src` | Selección de fuente para el siguiente PC |
| `reg_write` | Habilita escritura en registros |
| `mem_write` | Habilita escritura en memoria |
| `alu_src` | Selecciona inmediato o registro como segundo operando ALU |
| `jal` | Indica instrucción `jal` |
| `u_load` | Indica operación U-type |
| `branch` | Indica instrucción branch |
| `wb_src` | Selecciona dato para write back |
| `alu_op` | Selecciona operación de ALU |
| `sec_op` | Selecciona operación de seguridad |

La unidad de control es combinacional. No se implementa como FSM multiciclo; en su lugar, cada instrucción avanza por el pipeline y las señales de control viajan a través de los registros intermedios.

---

## 7. Actualización del PC

El siguiente valor del PC se selecciona con prioridad:

    1. Branch tomado en EX
    2. Jump PC-relative detectado en ID
    3. Jump register detectado en ID
    4. PC + 4

La lógica principal es:

    if branch_taken:
        next_pc = branch_target
    else if pc_src == PC_IMM:
        next_pc = if_id_reg.pc + imm
    else if pc_src == PC_JR:
        next_pc = rs1_data
    else:
        next_pc = PC + 4

La unidad de riesgos puede detener el PC mediante la señal `pc_write`.

---

## 8. Unidad de forwarding

La unidad de forwarding se encuentra en:

    src/cpu/forwarding_unit.sv

Su función es reducir riesgos de datos reenviando resultados recientes hacia la etapa EX.

Entradas principales:

| Entrada | Descripción |
| --- | --- |
| `id_ex_rs1` | Registro fuente 1 de la instrucción en EX |
| `id_ex_rs2` | Registro fuente 2 de la instrucción en EX |
| `ex_mem_rd` | Registro destino de la instrucción en MEM |
| `ex_mem_reg_write` | Indica si EX/MEM escribirá registro |
| `mem_wb_rd` | Registro destino de la instrucción en WB |
| `mem_wb_reg_write` | Indica si MEM/WB escribirá registro |

Salidas:

| Salida | Descripción |
| --- | --- |
| `forward_a` | Selección para operando A |
| `forward_b` | Selección para operando B |

Codificación usada:

| Valor | Fuente |
| --- | --- |
| `00` | Valor original desde `id_ex_reg` |
| `10` | Resultado reenviado desde EX/MEM |
| `01` | Resultado reenviado desde MEM/WB |

Esto permite resolver dependencias como:

    add x5, x1, x2
    sub x6, x5, x3

sin esperar a que `x5` sea escrito definitivamente en el banco de registros.

---

## 9. Unidad de riesgos

La unidad de riesgos se encuentra en:

    src/cpu/hazard_unit.sv

Genera señales para controlar stalls y flushes:

| Señal | Función |
| --- | --- |
| `pc_write` | Permite o detiene la actualización del PC |
| `if_id_write` | Permite o detiene la actualización del registro IF/ID |
| `if_id_flush` | Limpia la instrucción en IF/ID |
| `id_ex_flush` | Limpia la instrucción en ID/EX |

La unidad recibe información sobre los registros fuente de la instrucción en ID, los registros destino de instrucciones en etapas posteriores y señales de control como `branch_taken` y `jump_taken`.

Su objetivo es evitar que el pipeline ejecute instrucciones con datos inválidos o que conserve instrucciones incorrectas después de un salto.

---

## 10. Bóveda de llaves

La bóveda de llaves se implementa en:

    src/cpu/key_vault.sv

Parámetros principales:

| Parámetro | Valor por defecto | Descripción |
| --- | --- | --- |
| `XLEN` | 32 | Ancho de palabra |
| `KEYS` | 4 | Cantidad de llaves |
| `WORDS_PER_KEY` | 4 | Palabras de 32 bits por llave |

La bóveda se modela como un arreglo interno:

    vault[0 : KEYS * WORDS_PER_KEY - 1]

Con los parámetros actuales:

    4 llaves * 4 palabras por llave = 16 palabras de 32 bits

Esto equivale a cuatro llaves de 128 bits, aunque el acceso se realiza por palabras de 32 bits.

### 10.1 Escritura en la bóveda

La escritura ocurre cuando:

    vault_we = 1
    auth_en = 1

La dirección de escritura se toma de los bits bajos del operando usado como índice:

    addr = rs2_data[3:0]

El dato escrito es:

    wdata = rs1_data

Esto corresponde a la instrucción:

    ldk rs1, rs2

### 10.2 Lectura desde la bóveda

La lectura es combinacional y solo devuelve un valor distinto de cero si el procesador está autenticado:

    k_out = auth_en ? vault[addr] : 0

El valor `k_out` se captura en el registro `ID/EX` y se entrega a `sec_alu`.

---

## 11. Autenticación

El procesador mantiene un bit interno de autenticación:

    auth_bit

Este bit se actualiza cuando se ejecuta una instrucción `auth`.

La contraseña esperada es:

    0xDEADBEEF

Comportamiento:

    if sec_op == SEC_AUTH:
        if rs1_data == 0xDEADBEEF:
            auth_bit = 1
        else:
            auth_bit = 0

Si `auth_bit = 0`, la bóveda no entrega llaves y no permite escrituras. Además, `sec_alu` bloquea operaciones de seguridad no autorizadas.

---

## 12. ALU de seguridad

La ALU de seguridad se encuentra en:

    src/cpu/sec_alu.sv

Entradas principales:

| Entrada | Descripción |
| --- | --- |
| `a` | Primer operando |
| `b` | Segundo operando |
| `key` | Palabra leída desde la bóveda |
| `sec_op` | Operación de seguridad |
| `auth_en` | Estado de autenticación |

Salidas:

| Salida | Descripción |
| --- | --- |
| `result` | Resultado de seguridad |
| `exception` | Señal de excepción |

Operaciones principales:

### 12.1 `SEC_ADDK`

    result = a + key

### 12.2 `SEC_XORK`

    result = a ^ key

### 12.3 `SEC_TEA`

    result = ((a << 4) + key) ^ b ^ ((a >> 5) + key)

Esta operación implementa una primitiva inspirada en TEA. No ejecuta el cifrado completo por sí sola; los programas de cifrado deben construir las rondas y el recorrido de memoria usando instrucciones assembly.

### 12.4 Detección de ataque cero

La ALU de seguridad incluye una defensa simple contra extracción directa de llaves mediante operaciones identidad.

La señal `zero_attack_detected` se activa cuando:

    a == 0
    sec_op == SEC_ADDK o SEC_XORK

Si ocurre una operación no autorizada o se detecta este patrón, el resultado se fuerza a cero.

El módulo `cpu_top.sv` imprime un error y termina la simulación si `sec_exception` se activa.

---

## 13. Memoria de instrucciones

La memoria de instrucciones se encuentra en:

    src/cpu/instr_mem.sv

Está parametrizada por:

    PROGRAM_FILE
    DEPTH

El archivo del programa se carga mediante `$readmemh`.

Ejemplo de ejecución:

    make sv-cpu-exec PROGRAM=programs/hex/program.hex

Durante los flujos de cifrado, el Makefile copia el programa correspondiente a:

    programs/hex/program.hex

para que la memoria de instrucciones lo cargue al iniciar la simulación.

---

## 14. Memoria de datos

La memoria de datos se encuentra en:

    src/cpu/data_mem.sv

Está parametrizada por:

    INITIAL_MEM
    DEPTH

Permite cargar un archivo inicial de memoria generado por:

    tools/load_file.py

Ejemplo:

    ./tools/load_file.py --input examples/test1.png --output memory.mem --address 0x1000

Luego la simulación puede cargar esa memoria como RAM inicial para que el procesador opere sobre datos reales.

Al finalizar la simulación, los testbenches generan un volcado de memoria:

    build/sim/memory_dump.txt

Ese archivo puede extraerse con:

    tools/extract_data.py

---

## 15. Flujo de una instrucción ALU

Ejemplo:

    add x5, x3, x4

Flujo por etapas:

| Etapa | Acción |
| --- | --- |
| IF | Se lee la instrucción desde `instr_mem` |
| ID | Se decodifican `opcode`, `rs1`, `rs2`, `rd`; se leen `x3` y `x4` |
| EX | La ALU calcula `R[x3] + R[x4]` |
| MEM | No hay acceso a memoria |
| WB | Se escribe el resultado en `x5` |

---

## 16. Flujo de una instrucción de memoria

Ejemplo:

    lw x5, 0(x10)

Flujo por etapas:

| Etapa | Acción |
| --- | --- |
| IF | Se lee la instrucción |
| ID | Se decodifica y se lee `x10` |
| EX | La ALU calcula `R[x10] + offset` |
| MEM | Se lee la memoria de datos |
| WB | Se escribe el dato leído en `x5` |

Ejemplo store:

    sw x5, 0(x10)

Flujo por etapas:

| Etapa | Acción |
| --- | --- |
| IF | Se lee la instrucción |
| ID | Se leen `x5` y `x10` |
| EX | Se calcula la dirección efectiva |
| MEM | Se escribe `x5` en memoria |
| WB | No hay escritura en registros |

---

## 17. Flujo de una instrucción de seguridad

Ejemplo:

    xork x5, x4, x3

Flujo por etapas:

| Etapa | Acción |
| --- | --- |
| IF | Se lee la instrucción |
| ID | Se decodifica `SEC_XORK`, se leen `x4` y `x3`, y se consulta la bóveda |
| EX | `sec_alu` calcula `R[x4] ^ key` |
| MEM | No hay acceso a memoria |
| WB | El resultado se escribe en `x5` |

Para que la operación funcione correctamente, debe ejecutarse antes:

    li      x1, 0xDEADBEEF
    auth    x1

y debe existir una llave cargada con:

    ldk rs1, rs2

---

## 18. Flujo de cifrado sobre archivos

Los programas de cifrado recorren una región de memoria cargada desde un archivo externo.

Flujo general:

    1. Autenticar el procesador con auth
    2. Escribir una llave en la bóveda con ldk
    3. Inicializar punteros de memoria
    4. Leer palabras desde DMEM con lw
    5. Aplicar xork o tea
    6. Escribir resultados con sw
    7. Repetir hasta llegar al final de la región
    8. Extraer memoria final con extract_data.py

El flujo automático del Makefile hace esto mediante:

    make verify-roundtrip FILE=test1.png
    make verify-roundtrip-tea FILE=test1.png

---

## 19. Manejo de excepciones de seguridad

La señal `exception` de `sec_alu` se usa para reportar operaciones de seguridad inválidas o no autorizadas.

En `cpu_top.sv`, si `sec_exception` se activa, se ejecuta:

    $display("SECURITY ERROR: Unauthorized operation or zero-attack detected.");
    $fatal(1);

Esto detiene la simulación. En la versión actual no se implementa un mecanismo de recuperación de excepción; el error se considera fatal durante la simulación.

---

## 20. Justificación de decisiones de diseño

| Decisión | Justificación |
| --- | --- |
| Instrucciones de 32 bits | Simplifican fetch, decode y cálculo del PC |
| Separación IMEM/DMEM | Facilita cargar programas y datos por separado |
| Pipeline lógico de 5 etapas | Permite organizar claramente IF, ID, EX, MEM y WB |
| Registros de pipeline | Mantienen datos y señales de control entre etapas |
| Forwarding | Reduce stalls por dependencias de datos |
| Hazard unit | Controla stalls y flushes en branches, jumps y dependencias |
| Bóveda de llaves separada | Evita que las llaves sean tratadas como memoria normal |
| Autenticación por `auth` | Protege operaciones de seguridad |
| `sec_alu` separada de la ALU general | Mantiene modularidad entre operaciones comunes y criptográficas |
| TEA como primitiva | Reduce complejidad de hardware frente a una implementación completa de 32 rondas |

---

## 21. Diferencias respecto a una implementación multiciclo

Aunque el ISA puede explicarse mediante las etapas clásicas IF, ID, EX, MEM y WB, la implementación actual no usa una FSM multiciclo que ejecute una sola instrucción a la vez. En su lugar, utiliza registros de pipeline para mantener varias instrucciones en diferentes etapas.

Por lo tanto:

| Aspecto | Multiciclo clásico | Implementación actual |
| --- | --- | --- |
| Instrucciones simultáneas | Una | Varias en distintas etapas |
| Control principal | FSM por etapa | Control combinacional + registros de pipeline |
| Riesgos de datos | No aparecen igual | Requieren forwarding y hazard unit |
| Branches | Se resuelven secuencialmente | Pueden requerir flush |
| Throughput | Menor | Mayor cuando no hay stalls |

---

## 22. Notas y limitaciones

- La ALU de seguridad implementa una primitiva estilo TEA, no un cifrado TEA completo por sí sola.
- El cifrado completo se construye en software mediante programas assembly.
- La bóveda almacena palabras de 32 bits; cuatro palabras forman una llave de 128 bits.
- Las instrucciones de seguridad requieren autenticación previa.
- Las operaciones no autorizadas pueden detener la simulación mediante `$fatal`.
- El diseño actual usa forwarding y hazard detection, pero no implementa predicción de saltos.
- Los saltos condicionales se resuelven en la etapa EX.
- Los saltos incondicionales pueden redirigir el PC desde la etapa ID.
- La memoria de datos y la memoria de instrucciones están separadas.
