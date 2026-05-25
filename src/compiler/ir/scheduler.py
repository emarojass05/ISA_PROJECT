"""
scheduler.py - Reordenamiento de instrucciones (List Scheduling).

Que hace
--------
Reordena las instrucciones dentro de cada bloque basico para reducir
hazards de datos RAW (Read After Write), minimizando los ciclos de stall
que el CPU necesita insertar entre instrucciones dependientes.

Algoritmo: List Scheduling
--------------------------
1. Construir un grafo de dependencias (DAG) para el bloque.
2. Calcular la prioridad de cada nodo = longitud del camino critico al final.
3. Scheduling greedy:
     - Cola de listos = nodos sin predecesores sin agendar.
     - En cada paso: elegir el nodo de mayor prioridad de la cola.
     - Agendarlo, actualizar la cola con nuevos nodos listos.

Grafo de dependencias
---------------------
Se agrega un arco de instruccion i a instruccion j (j debe ir despues de i)
cuando existe alguna de estas dependencias:

  RAW (Read After Write):   i define X, j usa X       -> real, no mover j antes de i
  WAR (Write After Read):   i usa X,   j define X     -> no mover j antes de i
  WAW (Write After Write):  i define X, j define X    -> mantener orden de escrituras
  MEM (memoria):            cualquier par load/store  -> orden conservador
  CTRL (control):           labels al inicio, terminadores al final (fijos)

Restricciones fijas
-------------------
  - IRLabel al inicio del bloque SIEMPRE queda en posicion 0.
  - Terminadores (IRGoto, IRIfTrue, IRIfFalse, IRReturn) SIEMPRE al final.
  - IRCall ordena todo lo que este antes/despues de el (barrera).

Interfaz publica
----------------
    SchedulerStats                  metricas del pass
    schedule_block(block)           reordena un BasicBlock in-place
    schedule_function(ir_func)      aplica a todos los bloques de una funcion
    schedule_program(ir_program)    aplica a todas las funciones
"""

from __future__ import annotations

import copy
from dataclasses import dataclass, field
from typing import Dict, List, Set, Tuple

from .ir_types import (
    IRInstruction, IRLabel, IRGoto, IRIfTrue, IRIfFalse,
    IRReturn, IRStore, IRLoad, IRCall,
)
from .ir_program import IRFunction, IRProgram
from .cfg import CFG


# ---------------------------------------------------------------------------
# Clasificadores de instrucciones
# ---------------------------------------------------------------------------

def _is_label(i: IRInstruction) -> bool:
    return isinstance(i, IRLabel)

def _is_terminator(i: IRInstruction) -> bool:
    return isinstance(i, (IRGoto, IRIfTrue, IRIfFalse, IRReturn))

def _is_memory(i: IRInstruction) -> bool:
    return isinstance(i, (IRLoad, IRStore))

def _is_barrier(i: IRInstruction) -> bool:
    """Instrucciones que actuan como barrera: nada puede cruzarlas."""
    return isinstance(i, IRCall)


# ---------------------------------------------------------------------------
# Nodo del grafo de dependencias
# ---------------------------------------------------------------------------

@dataclass
class DepNode:
    """
    Representa una instruccion en el DAG de dependencias.

    Atributos:
        idx          Posicion original en el bloque (para desempate).
        instr        La instruccion IR.
        succs        Indices de nodos que deben ir DESPUES de este.
        preds_count  Numero de predecesores aun no agendados (in-degree).
        priority     Longitud del camino critico desde este nodo al final.
    """
    idx:         int
    instr:       IRInstruction
    succs:       List[int] = field(default_factory=list)
    preds_count: int = 0
    priority:    int = 0


# ---------------------------------------------------------------------------
# Construccion del DAG de dependencias
# ---------------------------------------------------------------------------

def _build_dag(instrs: List[IRInstruction]) -> List[DepNode]:
    """
    Construye el DAG de dependencias para una lista de instrucciones.

    Retorna una lista de DepNode con succs y preds_count populados.
    """
    n = len(instrs)
    nodes = [DepNode(idx=i, instr=instrs[i]) for i in range(n)]

    # Para cada variable: ultimo indice que la definio
    last_def: Dict[str, int] = {}
    # Para cada variable: lista de indices que la usaron (para WAR)
    last_uses: Dict[str, List[int]] = {}
    # Indice del ultimo acceso a memoria
    last_mem: int = -1
    # Indice de la ultima barrera (IRCall)
    last_barrier: int = -1

    def add_edge(src: int, dst: int) -> None:
        """Agrega arco src -> dst si no existe ya."""
        if dst not in nodes[src].succs:
            nodes[src].succs.append(dst)
            nodes[dst].preds_count += 1

    for j, instr in enumerate(instrs):
        uses_j = instr.uses()
        defs_j = instr.defs()

        # Dependencia de barrera: todo va despues de la ultima barrera
        if last_barrier >= 0 and j != last_barrier:
            add_edge(last_barrier, j)

        # RAW: j usa variables definidas por instrucciones anteriores
        for var in uses_j:
            if var in last_def:
                add_edge(last_def[var], j)

        # WAR: j define variables usadas por instrucciones anteriores
        for var in defs_j:
            if var in last_uses:
                for k in last_uses[var]:
                    if k != j:
                        add_edge(k, j)

        # WAW: j define variables ya definidas antes
        for var in defs_j:
            if var in last_def and last_def[var] != j:
                add_edge(last_def[var], j)

        # MEM: orden conservador entre accesos a memoria
        if _is_memory(instr):
            if last_mem >= 0:
                add_edge(last_mem, j)
            last_mem = j

        # Actualizar barrera
        if _is_barrier(instr):
            last_barrier = j

        # Actualizar last_def y last_uses
        for var in defs_j:
            last_def[var] = j
        for var in uses_j:
            last_uses.setdefault(var, [])
            if j not in last_uses[var]:
                last_uses[var].append(j)

    return nodes


# ---------------------------------------------------------------------------
# Calculo de prioridades (altura en el DAG)
# ---------------------------------------------------------------------------

def _compute_priorities(nodes: List[DepNode]) -> None:
    """
    Calcula la prioridad de cada nodo = longitud del camino critico
    desde ese nodo hasta un nodo hoja (sin sucesores).

    Topological order inverso (de hojas hacia raices).
    priority[i] = 1 + max(priority[succ] for succ in succs[i])
    """
    n = len(nodes)
    # Procesamos en orden inverso de indices (aproximacion valida para DAGs
    # construidos en orden; para robustez hacemos iteracion hasta convergencia)
    changed = True
    while changed:
        changed = False
        for i in range(n - 1, -1, -1):
            node = nodes[i]
            new_prio = 1
            for s in node.succs:
                cand = 1 + nodes[s].priority
                if cand > new_prio:
                    new_prio = cand
            if new_prio != node.priority:
                node.priority = new_prio
                changed = True


# ---------------------------------------------------------------------------
# List Scheduling
# ---------------------------------------------------------------------------

def _list_schedule(nodes: List[DepNode]) -> List[IRInstruction]:
    """
    Ejecuta el algoritmo de list scheduling sobre el DAG.

    Invariante: un nodo esta "listo" cuando todos sus predecesores
    han sido agendados (preds_count == 0).

    Criterio de seleccion: mayor prioridad; en empate, menor idx original
    (mantiene el orden original cuando no hay diferencia).
    """
    # Copia de preds_count para no mutar los nodos originales
    pending = [node.preds_count for node in nodes]

    # Cola inicial: nodos sin predecesores
    ready = [i for i, p in enumerate(pending) if p == 0]

    scheduled: List[IRInstruction] = []
    scheduled_set: Set[int] = set()

    while ready:
        # Elegir nodo de mayor prioridad.
        # Desempate: mayor idx original = instruccion mas tardia en el orden
        # original. Esto favorece instrucciones independientes (que suelen
        # tener indices mayores) sobre instrucciones dependientes recien
        # desbloqueadas, llenando el hueco del RAW hazard.
        best = max(ready, key=lambda i: (nodes[i].priority, nodes[i].idx))
        ready.remove(best)

        scheduled.append(nodes[best].instr)
        scheduled_set.add(best)

        # Actualizar predecesores de sucesores
        for s in nodes[best].succs:
            pending[s] -= 1
            if pending[s] == 0:
                ready.append(s)

    return scheduled


# ---------------------------------------------------------------------------
# Scheduling de un bloque basico
# ---------------------------------------------------------------------------

def schedule_block(block) -> int:
    """
    Reordena las instrucciones de un BasicBlock usando list scheduling.

    Restricciones fijas antes de schedular:
      - El label inicial (si existe) se fija en posicion 0.
      - Los terminadores se fijan al final.
      - El cuerpo schedulable es todo lo que queda en el medio.

    Retorna el numero de instrucciones movidas respecto al orden original.
    """
    instrs = block.instructions
    if len(instrs) <= 1:
        return 0

    # Separar label inicial, cuerpo y terminadores
    prefix: List[IRInstruction] = []
    suffix: List[IRInstruction] = []
    body:   List[IRInstruction] = []

    i = 0
    # Label al inicio
    if instrs and _is_label(instrs[0]):
        prefix.append(instrs[0])
        i = 1

    # Terminadores al final
    j = len(instrs) - 1
    while j >= i and _is_terminator(instrs[j]):
        suffix.insert(0, instrs[j])
        j -= 1

    body = list(instrs[i:j+1])

    if len(body) <= 1:
        return 0   # nada que reordenar

    # Guardar orden original para contar movimientos
    original_strs = [str(x) for x in body]

    # Construir DAG y schedular
    nodes = _build_dag(body)
    _compute_priorities(nodes)
    new_body = _list_schedule(nodes)

    # Contar instrucciones movidas
    moves = sum(1 for a, b in zip(original_strs, [str(x) for x in new_body]) if a != b)

    block.instructions = prefix + new_body + suffix
    return moves


# ---------------------------------------------------------------------------
# Metricas
# ---------------------------------------------------------------------------

@dataclass
class SchedulerStats:
    """Metricas del pass de instruction scheduling."""
    blocks_scheduled: int = 0
    instrs_moved:     int = 0
    blocks_changed:   int = 0


# ---------------------------------------------------------------------------
# Interfaces publicas
# ---------------------------------------------------------------------------

def schedule_function(ir_func: IRFunction) -> SchedulerStats:
    """
    Aplica list scheduling a todos los bloques basicos de una funcion.

    Construye el CFG para obtener los bloques, schedula cada uno
    y re-aplana el body.

    Modifica ir_func.body in-place.
    """
    stats = SchedulerStats()

    cfg = CFG.build_from_function(ir_func)

    for block in cfg.blocks:
        stats.blocks_scheduled += 1
        moved = schedule_block(block)
        stats.instrs_moved += moved
        if moved > 0:
            stats.blocks_changed += 1

    # Re-aplanar
    ir_func.body = [
        instr
        for block in cfg.blocks
        for instr in block.instructions
    ]

    return stats


def schedule_program(ir_program: IRProgram) -> SchedulerStats:
    """
    Aplica instruction scheduling a todas las funciones del programa.
    """
    total = SchedulerStats()
    for func in ir_program.functions:
        s = schedule_function(func)
        total.blocks_scheduled += s.blocks_scheduled
        total.instrs_moved     += s.instrs_moved
        total.blocks_changed   += s.blocks_changed
    return total
