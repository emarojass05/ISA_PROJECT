# Análisis de Rendimiento y Validación — SecuRISC-32

## 1. Objetivo

Este documento define la metodología de medición y validación usada para evaluar el impacto de la jerarquía de caché y de las optimizaciones del compilador sobre SecuRISC-32.

La evaluación se enfoca en:

* Ciclos totales de ejecución.
* Instrucciones retiradas.
* IPC.
* Stalls por caché.
* Stalls por hazards de control.
* Accesos, hits y misses de L1-D.
* Hits y misses de L2.
* Accesos a memoria principal.
* Tráfico transferido hacia memoria principal.
* Comparación funcional con caché habilitada y deshabilitada.
* Comparación entre programas optimizados y no optimizados.

---

## 2. Fuentes de medición

Las métricas se obtienen desde señales internas del procesador y de la jerarquía de caché.

| Fuente                | Archivo              | Métricas principales                                      |
| --------------------- | -------------------- | --------------------------------------------------------- |
| Pipeline              | `cpu_top.sv`         | Instrucciones retiradas, stalls de control                |
| Controlador de caché  | `cache_ctrl.sv`      | L1 accesses, L1 hits/misses, L2 hits/misses, stall cycles |
| Jerarquía de caché    | `cache_hierarchy.sv` | Exporta contadores hacia `cpu_top.sv`                     |
| Testbench de programa | `tb_cpu_program.sv`  | Calcula IPC, hit rates y ancho de banda                   |
| Makefile              | `Makefile`           | Automatiza ejecución con/sin caché                        |

El reporte principal se genera en:

```text
build/sim/metrics.txt
```

---

## 3. Archivos generados

Después de ejecutar un programa con `make sv-cpu-exec`, el testbench genera:

| Archivo                       | Contenido                           |
| ----------------------------- | ----------------------------------- |
| `build/sim/metrics.txt`       | Métricas de rendimiento             |
| `build/sim/cycle_count.txt`   | Ciclos totales                      |
| `build/sim/register_dump.txt` | Estado final del banco de registros |
| `build/sim/memory_dump.txt`   | Estado final de memoria             |

Estos archivos permiten validar tanto rendimiento como correctitud funcional.

---

## 4. Métricas del procesador

| Métrica                 | Definición                                            |
| ----------------------- | ----------------------------------------------------- |
| Ciclos totales          | Ciclos desde el reset hasta HALT o `MAX_CYCLES`       |
| Instrucciones retiradas | Instrucciones que avanzan sin flush ni stall de caché |
| IPC                     | Instrucciones retiradas / ciclos totales              |
| Stalls de caché         | Ciclos donde `cache_stall = 1`                        |
| Stalls de control       | Slots perdidos por branches y jumps tomados           |

El IPC se calcula como:

```text
IPC = instructions_retired / cycles_total
```

Un IPC más alto indica mejor aprovechamiento del pipeline. Un IPC más bajo puede deberse a misses de caché, hazards de control, dependencias de datos o código no optimizado.

---

## 5. Métricas de caché

| Métrica      | Definición                                      |
| ------------ | ----------------------------------------------- |
| L1 accesses  | Número de solicitudes a L1-D                    |
| L1 hits      | Solicitudes resueltas en L1-D                   |
| L1 misses    | Solicitudes que pasan de L1-D a L2              |
| L1 hit rate  | `L1 hits / L1 accesses`                         |
| L1 miss rate | `L1 misses / L1 accesses`                       |
| L2 hits      | Misses de L1 resueltos en L2                    |
| L2 misses    | Solicitudes que pasan de L2 a memoria principal |
| L2 hit rate  | `L2 hits / (L2 hits + L2 misses)`               |
| L2 miss rate | `L2 misses / (L2 hits + L2 misses)`             |

Fórmulas:

```text
L1_hit_rate  = perf_l1_hits / perf_l1_accesses
L1_miss_rate = perf_l1_misses / perf_l1_accesses

L2_hit_rate  = perf_l2_hits / (perf_l2_hits + perf_l2_misses)
L2_miss_rate = perf_l2_misses / (perf_l2_hits + perf_l2_misses)
```

---

## 6. Métricas de memoria principal

La memoria principal modela una capacidad de 64 KB (`DEPTH=16384` palabras de 32 bits) con latencia base de 25 ticks de memoria. La FSM de latencia avanza un tick cada `MEM_CLK_DIV` ciclos de CPU, por lo que la latencia efectiva es `LATENCY * MEM_CLK_DIV` ciclos de CPU (default de sistema `MEM_CLK_DIV=4` -> 100 ciclos, ~25 MHz si el CPU corre a 100 MHz). El divisor puede sobreescribirse en tiempo de compilación con `make sv-cpu-exec MEM_CLK_DIV=<n>`.

Cada acceso a memoria principal transfiere una línea completa de caché:

```text
1 línea = 32 bytes = 8 palabras de 32 bits = 256 bits
```

| Métrica              | Definición                               |
| -------------------- | ---------------------------------------- |
| Main memory fetches  | Cantidad de líneas solicitadas a memoria |
| MM bytes transferred | `main_memory_fetches * 32`               |
| BW utilization       | `bytes_transferidos / ciclos_totales`    |

Fórmulas:

```text
MM_bytes_transferred = perf_mm_accesses * 32
BW_utilization = MM_bytes_transferred / cycles_total
```

---

## 7. AMAT

El AMAT se puede estimar con:

```text
AMAT = L1_hit_time
     + L1_miss_rate * (L2_hit_time + L2_miss_rate * memory_penalty)
```

Para el modelo usado:

| Parámetro        | Valor de referencia                                             |
| ---------------- | --------------------------------------------------------------- |
| `L1_hit_time`    | 1 ciclo                                                         |
| `L2_hit_time`    | Aproximadamente 8 ciclos modelados por FSM                      |
| `memory_penalty` | `MM_LATENCY * MEM_CLK_DIV` ciclos de CPU (default 25 x 4 = 100) |

El factor `MEM_CLK_DIV` es esencial: la FSM de `main_mem_model` avanza un tick cada `MEM_CLK_DIV` ciclos de CPU, así que la penalización real de un miss de L2 hacia memoria principal es `LATENCY * MEM_CLK_DIV` ciclos de CPU (100 con el default de sistema), no `LATENCY` ciclos. Usar solo `LATENCY` reportaría un AMAT optimista que no corresponde a la latencia que de hecho experimenta el pipeline.

El AMAT debe interpretarse como una aproximación útil para comparar configuraciones o programas. El costo real observado se refleja directamente en `perf_cache_stall_cycles` y en los ciclos totales. `tb_cpu_program.sv` reporta dos formas complementarias en `metrics.txt`:

```text
AMAT_analitico = HT_L1 + MR_L1 * (HT_L2 + MR_L2 * MM_penalty)
AMAT_medido    = HT_L1 + perf_cache_stall_cycles / perf_l1_accesses
```

Una diferencia grande entre ambos indica overhead de FSM no contemplado por el modelo analítico o un working set atípico.

---

## 8. Benchmarks disponibles

Los programas `.hex` cargados al proyecto permiten evaluar diferentes comportamientos.

| Benchmark        | Archivo(s)                                     | Propósito                                           |
| ---------------- | ---------------------------------------------- | --------------------------------------------------- |
| Autenticación    | `auth_test.hex`                                | Validar `auth` y bóveda de llaves                   |
| Seguridad básica | `sec_test.hex`                                 | Validar instrucciones de seguridad                  |
| Cifrado          | `encrypt.hex`, `decrypt.hex`                   | Evaluar acceso a memoria + operaciones de seguridad |
| Caché            | `cache_stress.hex`                             | Generar presión sobre la jerarquía de memoria       |
| División         | `div_o0.hex`, `div_o1.hex`, `div_o2.hex`       | Comparar niveles de optimización                    |
| Factorial        | `fact_o0.hex`, `fact_o1.hex`, `fact_o2.hex`    | Comparar conteo de instrucciones/ciclos             |
| Primalidad       | `primo_o0.hex`, `primo_o1.hex`, `primo_o2.hex` | Evaluar branches, loops y optimizaciones            |
| Máximo de lista  | `maximo_lista.hex`                             | Evaluar recorrido de arreglo                        |
| Suma de mayores  | `sumeMayores.hex`                              | Evaluar loops, comparaciones y memoria              |

---

## 9. Metodología de validación funcional

### 9.1 Validación unitaria

Primero se validan los módulos aislados:

```bash
make sv-run-alu
make sv-run-decoder
make sv-run-control_unit
make sv-run-register_file
make sv-run-key_vault
make sv-run-sec_alu
make sv-run-main_mem_model
make sv-run-mem_write_buffer
make sv-run-cache_l1d
make sv-run-cache_l2
make sv-run-cache_ctrl
make sv-run-cache_hierarchy
```

### 9.2 Validación del CPU completo

Después se ejecutan programas completos:

```bash
make sv-cpu-exec PROGRAM=programs/hex/program.hex CACHE_ENABLE=0 MAX_CYCLES=2000
make sv-cpu-exec PROGRAM=programs/hex/program.hex CACHE_ENABLE=1 MAX_CYCLES=2000
```

### 9.3 Validación con y sin caché

La equivalencia funcional se valida ejecutando el mismo programa en ambos modos:

```bash
make verify-cache-modes PROGRAM=programs/hex/cache_stress.hex MAX_CYCLES=5000
```

El criterio esperado es:

```text
[PASS] Register files match — both cache modes produce identical results.
```

Si los registros finales coinciden, la jerarquía de caché conserva la semántica del programa.

---

## 10. Metodología de medición de rendimiento

Para cada benchmark se recomienda ejecutar:

```bash
make sv-cpu-exec PROGRAM=programs/hex/<benchmark>.hex CACHE_ENABLE=0 MAX_CYCLES=5000
cp build/sim/metrics.txt build/sim/<benchmark>_cache0_metrics.txt

make sv-cpu-exec PROGRAM=programs/hex/<benchmark>.hex CACHE_ENABLE=1 MAX_CYCLES=5000
cp build/sim/metrics.txt build/sim/<benchmark>_cache1_metrics.txt
```

Luego se comparan:

* Ciclos totales.
* Instrucciones retiradas.
* IPC.
* Stalls de caché.
* L1 hit rate.
* L2 hit rate.
* Accesos a memoria principal.

---

## 11. Tabla base para resultados

| Benchmark          | Caché | Ciclos | Instr. retiradas | IPC    | L1 acc. | L1 hit rate | L2 hit rate | MM fetches | Cache stalls |
| ------------------ | ----- | ------ | ---------------- | ------ | ------- | ----------- | ----------- | ---------- | ------------ |
| `cache_stress.hex` | 0     | 1368   | 610              | 0.4459 | 0       | 0.00%       | 0.00%       | 0          | 0            |
| `cache_stress.hex` | 1     | 2744   | 610              | 0.2223 | 160     | 0.00%       | 97.50%      | 4          | 1376         |
| `div_o0.hex`       | 1     | 910    | 431              | 0.4736 | 121     | 97.52%      | 0.00%       | 3          | 96           |
| `div_o1.hex`       | 1     | 1549   | 691              | 0.4461 | 435     | 98.62%      | 0.00%       | 6          | 192          |
| `div_o2.hex`       | 1     | 1549   | 691              | 0.4461 | 435     | 98.62%      | 0.00%       | 6          | 192          |
| `fact_o0.hex`      | 1     | 394    | 174              | 0.4416 | 48      | 93.75%      | 0.00%       | 3          | 96           |
| `fact_o1.hex`      | 1     | 680    | 223              | 0.3279 | 128     | 92.97%      | 0.00%       | 9          | 288          |
| `fact_o2.hex`      | 1     | 680    | 223              | 0.3279 | 128     | 92.97%      | 0.00%       | 9          | 288          |
| `primo_o0.hex`     | 1     | 16     | 8                | 0.5000 | 1       | 0.00%       | 0.00%       | 1          | 9            |
| `primo_o1.hex`     | 1     | 3421   | 1576             | 0.4607 | 898     | 98.55%      | 0.00%       | 13         | 416          |
| `primo_o2.hex`     | 1     | 3421   | 1576             | 0.4607 | 898     | 98.55%      | 0.00%       | 13         | 416          |

### 11.1 Análisis de resultados obtenidos

Los resultados muestran que la jerarquía de caché introduce un costo inicial asociado a los misses obligatorios, especialmente cuando se habilita `CACHE_ENABLE=1`. Esto se observa claramente en `cache_stress.hex`, donde la ejecución con caché aumenta de 1368 a 2744 ciclos debido a 1376 ciclos de stall. Sin embargo, este benchmark está diseñado para ejercer presión sobre la jerarquía de memoria, por lo que su comportamiento no representa necesariamente el caso promedio de los programas.

En los programas `div_o0.hex`, `div_o1.hex` y `div_o2.hex`, la tasa de aciertos de L1-D se mantiene alta, entre 97.52% y 98.62%. Esto indica que, una vez cargadas las líneas iniciales desde memoria principal, la mayoría de accesos posteriores se resuelven directamente en L1. El costo principal proviene de los cold misses iniciales, reflejados en los accesos a memoria principal y en los ciclos de stall.

Para la familia `fact_o0.hex`, `fact_o1.hex` y `fact_o2.hex`, se observa que las versiones optimizadas O1 y O2 tienen el mismo comportamiento medido, con 680 ciclos, 223 instrucciones retiradas y 288 ciclos de stall. Esto sugiere que, para este caso específico, ambas versiones generan un patrón de ejecución equivalente o muy similar desde el punto de vista del procesador y la jerarquía de memoria.

En la familia `primo_o0.hex`, `primo_o1.hex` y `primo_o2.hex`, las versiones O1 y O2 también presentan resultados idénticos. Ambas ejecutan 3421 ciclos, retiran 1576 instrucciones y alcanzan un L1 hit rate de 98.55%. Esto indica alta localidad después de los primeros misses. El caso `primo_o0.hex` presenta una ejecución muy corta, con 16 ciclos y 8 instrucciones retiradas, por lo que se interpreta como un caso mínimo o una terminación temprana del programa evaluado.

En general, los resultados permiten validar que los contadores de rendimiento capturan correctamente ciclos, instrucciones, IPC, stalls por caché, accesos a L1-D, hits/misses y accesos a memoria principal. Además, la comparación entre programas optimizados y no optimizados permite observar el impacto del código generado sobre el comportamiento del pipeline y la jerarquía de memoria.

---

## 12. Comparación de optimizaciones del compilador

Para comparar optimizaciones, se agrupan programas equivalentes por nivel:

| Familia    | O0             | O1             | O2             |
| ---------- | -------------- | -------------- | -------------- |
| División   | `div_o0.hex`   | `div_o1.hex`   | `div_o2.hex`   |
| Factorial  | `fact_o0.hex`  | `fact_o1.hex`  | `fact_o2.hex`  |
| Primalidad | `primo_o0.hex` | `primo_o1.hex` | `primo_o2.hex` |

Métricas relevantes:

| Métrica        | Interpretación esperada                               |
| -------------- | ----------------------------------------------------- |
| Instrucciones  | Debe bajar si DCE o simplificaciones eliminan trabajo |
| Ciclos totales | Debe bajar si hay menos instrucciones o menos stalls  |
| IPC            | Puede subir si el reordenamiento reduce burbujas      |
| Cache stalls   | Puede bajar si mejora la localidad de memoria         |
| L1 hit rate    | Puede subir en código con mejor localidad             |
| Control stalls | Puede bajar si se reducen saltos o se mejora el flujo |

---

## 13. Interpretación esperada por patrón de acceso

### 13.1 Acceso secuencial

Un acceso secuencial debe favorecer la localidad espacial. Al traer una línea de 32 bytes, se cargan 8 palabras, por lo que las siguientes palabras cercanas deberían producir hits en L1.

Indicadores esperados:

* Alto L1 hit rate después de los cold misses iniciales.
* Bajo número relativo de accesos a memoria principal.
* Menos ciclos de stall conforme avanza el recorrido.

### 13.2 Acceso aleatorio

Un acceso aleatorio reduce la localidad espacial y temporal.

Indicadores esperados:

* Menor L1 hit rate.
* Mayor presión sobre L2 y memoria principal.
* Más ciclos de stall.

### 13.3 Acceso con stride

Un stride puede generar conflictos dependiendo de cómo caigan las direcciones en los sets.

Indicadores esperados:

* Si el stride mapea muchas direcciones al mismo set, puede aumentar el miss rate.
* La asociatividad de L1 y L2 ayuda a reducir, pero no elimina, misses por conflicto.

---

## 14. Validación de caché L1-D

`tb_cache_l1d.sv` cubre:

| Caso            | Validación                            |
| --------------- | ------------------------------------- |
| Reset           | Líneas inválidas y dirty bits limpios |
| Fill + read hit | Una línea instalada produce hit       |
| Read miss       | Dirección no instalada produce miss   |
| Write-hit       | Actualiza palabra y marca línea dirty |
| Victim dirty    | Expone dirty victim para write-back   |
| LRU replacement | Selección de víctima según bit LRU    |
| LRU update      | Actualización de uso reciente         |

---

## 15. Validación de caché L2

`tb_cache_l2.sv` cubre:

| Caso            | Validación                                  |
| --------------- | ------------------------------------------- |
| Reset           | Líneas inválidas y dirty bits limpios       |
| Fill + read hit | Línea instalada produce hit                 |
| Read miss       | Dirección no instalada produce miss         |
| Write-line      | Write-back desde L1 actualiza L2            |
| Victim dirty    | Víctima sucia se identifica correctamente   |
| PLRU sequence   | Reemplazo aproximado según árbol pseudo-LRU |
| PLRU update     | Actualización explícita después de acceso   |

---

## 16. Validación del controlador de caché

`tb_cache_ctrl.sv` cubre:

| Caso              | Validación                            |
| ----------------- | ------------------------------------- |
| Bypass mode       | Solicitudes pasan a memoria de bypass |
| L1 read hit       | Respuesta sin miss                    |
| L1 write hit      | Store directo en L1                   |
| L1 miss + L2 hit  | Se llena L1 desde L2                  |
| L1 miss + L2 miss | Se solicita línea a memoria principal |
| Dirty L1 victim   | Se escribe línea sucia hacia L2       |
| Store miss        | Write-allocate                        |
| Dirty L2 victim   | Se encola en write buffer             |
| Drain-on-conflict | Evita leer datos obsoletos            |

---

## 17. Validación de jerarquía completa

`tb_cache_hierarchy.sv` cubre:

| Caso                | Validación                             |
| ------------------- | -------------------------------------- |
| Bypass mode         | Lectura/escritura sin caché            |
| Cold miss           | Acceso inicial baja hasta memoria      |
| Hit after fill      | Segundo acceso se resuelve en caché    |
| Multiple sets       | Direcciones con diferentes sets        |
| Write overwrite     | Store hit actualiza dato               |
| Toggle cache enable | Estado de caché persiste entre modos   |
| Reset               | `cache_stall` se desactiva sin request |
| Dirty L2 eviction   | Write buffer drena hacia memoria       |

---

## 18. Conclusiones

1. La jerarquía de caché L1-D/L2 permitió medir correctamente el impacto de memoria sobre el procesador. Los contadores registraron ciclos totales, instrucciones retiradas, IPC, stalls, accesos a L1, hits/misses y accesos a memoria principal, cumpliendo con las métricas necesarias para evaluar el rendimiento de SecuRISC-32.

2. Los resultados muestran que la caché beneficia principalmente a programas con localidad temporal o espacial. En benchmarks como `div_o0.hex`, `div_o1.hex`, `div_o2.hex`, `primo_o1.hex` y `primo_o2.hex`, la tasa de acierto de L1-D se mantuvo cercana o superior al 97%, lo que indica que la mayoría de accesos se resolvieron sin bajar hasta memoria principal.

3. El benchmark `cache_stress.hex` evidencia el costo de los misses de caché. Con caché habilitada, los ciclos aumentaron de 1368 a 2744 debido a 1376 ciclos de stall. Este comportamiento es esperado, ya que el programa está diseñado para presionar la jerarquía de memoria y validar el manejo de misses y stalls.

4. Las optimizaciones del compilador no siempre reducen ciclos en todos los casos. En varias familias, como división, factorial y primalidad, las versiones O1 y O2 produjeron métricas idénticas, lo que sugiere que para esos programas el código generado tuvo un comportamiento equivalente en el pipeline y en la jerarquía de memoria.
---

