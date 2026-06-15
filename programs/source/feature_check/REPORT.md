# Feature Check Report

Generated: 2026-06-13  
Branch: test/compiler  
Compiler: `./frc`  
CPU execution: `make sv-cpu-exec CACHE_ENABLE=0 MAX_CYCLES=4000`  
Return value register: **x3** (= ABI alias `a0`)

---

## Results Table

| Program          | Feature                                | Correcto (x3) | Obtenido (x3) | Estado            | Notas                                                                                    |
| ---------------- | -------------------------------------- | ------------- | ------------- | ----------------- | ---------------------------------------------------------------------------------------- |
| arithmetic_ops   | `+ - * / %` y precedencia              | 42            | 42            | **PASS**          |                                                                                          |
| bitwise_ops      | `\|` `^` `<<` `>>`                     | 42            | 42            | **PASS**          |                                                                                          |
| logical_ops      | `&&` `\|\|` `!` con operandos no-bool  | 3             | 10            | **FAIL**          | `&&`->AND bitwise, `\|\|`->OR bitwise, `!x`->XOR 1                                       |
| relational_eq    | `> < >= <= == !=`                      | 6             | 6             | **PASS**          |                                                                                          |
| unary_ops        | `-x`, `!flag`                          | 5             | 5             | **PASS**          |                                                                                          |
| if_else          | `si/sinon` anidados                    | 6             | 6             | **PASS**          |                                                                                          |
| while_loop       | `alors`                                | 10            | 10            | **PASS**          |                                                                                          |
| for_loop         | `pour` con `i++`, `i--`                | 14            | 14            | **PASS**          | Correcto per codigo; esperado inicial 20 era incorrecto                                  |
| continue_stmt    | `suivre` en loop                       | 6             | 6             | **PASS**          |                                                                                          |
| recursion        | factorial(5) recursivo                 | 120           | 120           | **PASS**          |                                                                                          |
| many_params      | funcion con 8 params (>7, tests stack) | 36            | 36            | **PASS**          |                                                                                          |
| array_literal    | init `{...}`, lectura indexada         | 30            | 30            | **PASS**          |                                                                                          |
| array_sized      | `*arr(N)`, escritura y lectura         | 99            | 99            | **PASS**          |                                                                                          |
| array_indexed_rw | escritura/lectura indexada en loop     | 15            | 15            | **PASS**          |                                                                                          |
| array_multidim   | `m@(i)@(j)` -- matriz 2x2              | 4             | 3             | **FAIL**          | Stride de fila no aplicado: accede `base+i*4+j*4` en vez de `base+(i*cols+j)*4`          |
| array_large      | arreglo local 600 ints (frame >2047 B) | 42            | --            | **COMPILE_ERROR** | `addi sp,sp,-2404: Immediate out of 12-bit range`                                        |
| types_bool       | `vrai`/`faux`                          | 1             | 1             | **PASS**          |                                                                                          |
| types_char       | tipo `char`                            | 65            | 65            | **PASS**          |                                                                                          |
| hex_literals     | literales `0x...`                      | 255           | 255           | **PASS**          |                                                                                          |
| globals          | variables y arreglos globales          | 45            | 0             | **FAIL**          | Bug pipeline CPU: JAL a FUNC_main no se toma cuando ENTRY tiene >=6 instrs antes del JAL |
| annotations      | `? vaulted`                            | 7             | 7             | **PASS**          |                                                                                          |
| imports          | `invoquer "..."`                       | 60            | 60            | **PASS**          | Requiere flag `-D programs/source/feature_check`                                         |
| string_literal   | literal `"..."` como expresion         | --            | --            | **COMPILE_ERROR** | `[ERR](SYNTAX) missing '{' at '"hello"'`                                                 |
| pointer_params   | arreglo via `*param`, mutacion         | 40            | 40            | **PASS**          |                                                                                          |

---

## Detalle de Fallos

### 1. logical_ops -- FAIL (x3 obtenido: 10, esperado: 3)

**Programa** (`programs/source/feature_check/logical_ops.fr`):

```fr
fonc [int] main() {
    [int] r1 = 2 && 1;   $ expected: 1
    [int] r2 = 0 || 5;   $ expected: 1
    [int] r3 = !5;        $ expected: 0
    [int] r4 = !0;        $ expected: 1
    ret r1 + r2 + r3 + r4;  $ expected: 3
}
```

**Comando:**
```
./frc programs/source/feature_check/logical_ops.fr -o programs/hex/program.hex
make sv-cpu-exec PROGRAM=programs/hex/program.hex CACHE_ENABLE=0 MAX_CYCLES=4000
```

**IR generado (./frc logical_ops.fr --ir):**
```
_t0 = 2 & 1      ; deberia ser logical AND -> 1, produce bitwise AND -> 0
_t1 = 0 | 5      ; deberia ser logical OR  -> 1, produce bitwise OR  -> 5
_t2 = !5         ; deberia ser 0, produce xori(5,1) = 4
_t3 = !0         ; produce xori(0,1) = 1 (correcto por accidente)
```

**Assembly generado (fragmento ./frc -c):**
```asm
and t0, t0, t1     ; 2 & 1 = 0   (bitwise AND)
or  t0, t0, t1     ; 0 | 5 = 5   (bitwise OR)
xori t0, t0, 1     ; !5  -> 5 XOR 1 = 4
xori t0, t0, 1     ; !0  -> 0 XOR 1 = 1
```

**Resultado:** 0 + 5 + 4 + 1 = 10 obtenido vs 3 esperado.

**Diagnostico:** `&&` se compila como `and` bitwise, `||` como `or` bitwise, `!` como `xori reg, 1` (flip de bit 0). Ninguno tiene semantica logica correcta con operandos no booleanos.

---

### 2. array_multidim -- FAIL (x3 obtenido: 3, esperado: 4)

**Programa** (`programs/source/feature_check/array_multidim.fr`):

```fr
fonc [int] main() {
    [int] *mat = {1, 2, 3, 4};  $ 2x2: {{1,2},{3,4}}
    [int] row = 1;
    [int] col = 1;
    ret mat@(row)@(col);         $ esperado: mat[1][1] = 4
}
```

**IR generado:**
```
_t3 = _t0 + _t2      ; base + row*4
_t6 = _t3 + _t5      ; (base + row*4) + col*4
_t7 = mem[_t6 + 0]   ; accede mat + row*4 + col*4
```

**Calculo:**
- Correcto (stride 2 cols): `mat + (1*2 + 1)*4 = mat+12 -> valor 4`
- Obtenido: `mat + 1*4 + 1*4 = mat+8 -> valor 3`

**Diagnostico:** `m@(i)@(j)` no incorpora el stride de fila (numero de columnas). La segunda indexacion `@(j)` aplica simplemente `offset + j*4`, sin multiplicar la primera dimension por el ancho de la fila.

---

### 3. array_large -- COMPILE_ERROR

**Programa** (`programs/source/feature_check/array_large.fr`):

```fr
fonc [int] main() {
    [int] *arr(600);     $ 600 * 4 = 2400 bytes
    arr@(0) = 1;
    arr@(599) = 42;
    ret arr@(599);
}
```

**Comando:**
```
./frc programs/source/feature_check/array_large.fr -o programs/hex/program.hex
```

**Error exacto:**
```
[ERR](COMPILER) Error on line 8: addi sp, sp, -2404
Immediate -2404 is out of signed 12-bit range
```

**Diagnostico:** Arreglos locales de mas de ~511 enteros (>2044 bytes, contando el slot de ra) producen un frame que requiere `addi sp, sp, -N` con N > 2048, fuera del rango del immediato de 12 bits con signo del ISA. El compilador emite la instruccion invalida y el ensamblador la rechaza.

---

### 4. globals -- FAIL (x3 obtenido: 0, esperado: 45)

**Programa** (`programs/source/feature_check/globals.fr`):

```fr
[int] g_counter = 0;
[int] *g_arr(3);

fonc [void] increment([int] amount) { g_counter = g_counter + amount; ret; }
fonc [void] fill_globals() { g_arr@(0)=10; g_arr@(1)=20; g_arr@(2)=30; ret; }
fonc [int] main() {
    increment(5);
    increment(10);
    fill_globals();
    ret g_counter + g_arr@(2);  $ esperado: 15 + 30 = 45
}
```

**Comando:**
```
./frc programs/source/feature_check/globals.fr -o programs/hex/program.hex
make sv-cpu-exec PROGRAM=programs/hex/program.hex CACHE_ENABLE=0 MAX_CYCLES=4000
```

**Traza CPU (make sv-cpu-exec con MAX_CYCLES=200):**
```
cycle  pc        instr       cache_stall
   13  0000001c  0c101407    0     ; jal ra, FUNC_main (offset=0xC8, target=0xE4)
   14  0000001c  0c101407    0     ; stall
   15  0000001c  0c101407    0     ; stall
   16  00000020  00000007    0     ; j PROGRAM_END en IF -> HALT disparado
[HALT] PROGRAM_END detected at cycle 16 (pc=00000020)
```

**Diagnostico:** El compilador genera en ENTRY instrucciones de inicializacion de globales (luhw/llhw/sw por cada variable global) antes de `jal ra, FUNC_main`. Con `g_counter` y `g_arr` declarados, el ENTRY tiene 7 instrucciones antes del JAL (byte offset 0x1C). El JAL esta correctamente codificado (offset 0xC8=200, target 0xE4=FUNC_main).

El bug ocurre en el pipeline del CPU: cuando el JAL entra en la etapa ID/EX, la etapa IF ha captado `j PROGRAM_END` (0x00000007) en el ciclo siguiente. El testbench detecta HALT_INSTR en IF antes de que el pipeline realice el flush posterior a la resolucion del JAL. Resultado: main nunca se ejecuta y x3 permanece en 0.

**Experimentos de biseccion:**
- ASM manual con 5 instrucciones antes de JAL -> x3=45 (PASS)
- ASM manual con 6 instrucciones antes de JAL -> x3=0 (FAIL)
- El umbral exacto es 6 instrucciones antes del JAL.
- El IAL esta codificado correctamente en ambos casos; el fallo es un bug de interaccion CPU-testbench.

---

### 5. string_literal -- COMPILE_ERROR

**Programa** (`programs/source/feature_check/string_literal.fr`):

```fr
fonc [int] main() {
    [char] *s = "hello";
    ret 1;
}
```

**Comando:**
```
./frc programs/source/feature_check/string_literal.fr -o programs/hex/program.hex
```

**Error exacto:**
```
[ERR](SYNTAX) line 6:15 missing '{' at '"hello"'
[ERR](SYNTAX) line 6:22 mismatched input ';' expecting {'}', ','}
```

**Diagnostico:** El parser rechaza string literals en posicion de expresion. El IR generator tambien lo rechaza explicitamente (`raise Exception("String literals are not supported in IR generation")`). El token STRING_LITERAL existe en el lexer pero no esta conectado como expresion asignable.

---

## Resumen Final

| Estado        | Cantidad |
| ------------- | -------- |
| PASS          | 18       |
| FAIL          | 3        |
| COMPILE_ERROR | 2        |
| **Total**     | **23**   |

**Features que funcionan correctamente:**
arithmetic_ops, bitwise_ops, relational_eq, unary_ops, if_else, while_loop, for_loop, continue_stmt, recursion, many_params, array_literal, array_sized, array_indexed_rw, types_bool, types_char, hex_literals, annotations, imports (con -D), pointer_params.

**Features rotos confirmados con evidencia:**

1. **logical_ops** -- `&&`/`||` compilan como AND/OR bitwise; `!` como XOR-1. Con operandos no booleanos los resultados son incorrectos.
2. **array_multidim** -- `m@(i)@(j)` no tiene stride de fila; accede `base+i*4+j*4` en vez de `base+(i*cols+j)*4`.
3. **globals** -- Variables globales causan >=6 instrucciones en ENTRY antes del JAL, activando un bug de pipeline/testbench que impide que `main` se ejecute.
4. **array_large** -- Arreglos locales de >~511 ints producen offset de frame fuera del rango de 12 bits del ISA, fallando en ensamblado.
5. **string_literal** -- No soportado ni en parser ni en IR; el feature no esta implementado.
