"""
loop_unroller.py — Loop unrolling con factor configurable y heuristica.

Que hace
--------
Duplica el cuerpo de un loop N veces dentro de la misma iteracion,
reduciendo el numero de saltos al header y aumentando el bloque de
instrucciones disponibles para el scheduler.

Estructura de loop que detectamos (producida por IRGenerator):

    WHILE_START_k  / FOR_START_k          <- header label
      [instrucciones de condicion]
      iffalse _tx goto EXIT_LABEL         <- salto de salida
      [cuerpo del loop]
    FOR_UPDATE_k (opcional, solo en for)
      [instrucciones de actualizacion]
      goto HEADER_LABEL                   <- back-edge
    EXIT_LABEL:

Tipos de unrolling
------------------
1. Full unrolling  — trip count constante conocido <= MAX_FULL_UNROLL.
   Se elimina el loop y se replican las instrucciones T veces.
   NO hay chequeo de condicion entre copias (el trip count garantiza
   que todas las iteraciones se ejecutan).

2. Partial unrolling — factor F configurable.
   Se duplica el cuerpo F veces DENTRO del loop.
   Se agrega un chequeo de condicion entre cada copia para manejar
   loops cuyo conteo no es multiplo de F.

Heuristica automatica (cuando factor=0)
----------------------------------------
    body_size <= 4  instrucciones  →  factor 4
    body_size <= 8  instrucciones  →  factor 2
    body_size  > 8  instrucciones  →  sin unrolling (evita code bloat)

Trip count
----------
Se detecta para patrones simples de la forma:
    init:  loop_var = literal_constante
    cond:  loop_var < N  (o <=, >, >=)
    step:  loop_var = loop_var + literal_constante
Si no es detectable, se usa partial unrolling con la heuristica.

Interfaz publica
----------------
    unroll_program(ir_program, factor, max_full)
    unroll_function(ir_func,   factor, max_full)
"""

from __future__ import annotations

import copy
from dataclasses import dataclass
from typing import List, Optional, Dict

from .ir_types import (
    IRInstruction, IRLabel, IRGoto, IRIfTrue, IRIfFalse,
    IRCopy, IRBinOp, IRReturn, BinOp,
)
from .ir_program import IRFunction, IRProgram


# ---------------------------------------------------------------------------
# Constantes por defecto
# ---------------------------------------------------------------------------

DEFAULT_MAX_FULL_UNROLL = 16   # maximo trip count para full unrolling
DEFAULT_FACTOR          = 0    # 0 = usar heuristica


# ---------------------------------------------------------------------------
# Estructura de un loop detectado en la IR plana
# ---------------------------------------------------------------------------

@dataclass
class LoopInfo:
    """
    Describe un loop natural encontrado en el body plano de una funcion.

    Indices apuntan a posiciones en body[]:

        body[header_idx]   = IRLabel(header_label)
        body[iffalse_idx]  = IRIfFalse(cond, exit_label)
        body[body_start]   = primera instruccion del cuerpo
        body[latch_idx]    = IRGoto(header_label)   <- back-edge
        body[exit_idx]     = IRLabel(exit_label)

    cond_start .. iffalse_idx-1  son las instrucciones que calculan la
    condicion del loop.
    """
    header_label: str
    exit_label:   str
    header_idx:   int          # indice de IRLabel(header_label)
    cond_start:   int          # primera instruccion de la condicion
    iffalse_idx:  int          # indice de IRIfFalse
    body_start:   int          # primera instruccion del cuerpo
    latch_idx:    int          # indice de IRGoto(header_label)
    exit_idx:     int          # indice de IRLabel(exit_label)


# ---------------------------------------------------------------------------
# Deteccion de loops
# ---------------------------------------------------------------------------

def _find_loops(body: List[IRInstruction]) -> List[LoopInfo]:
    """
    Escanea el body plano y retorna una lista de LoopInfo, uno por loop
    natural detectado.

    Estrategia: un loop existe cuando hay un IRGoto cuyo destino es una
    etiqueta que aparece ANTES en el body (back-edge). La etiqueta debe
    ser WHILE_START o FOR_START (producidas por IRGenerator).
    """
    # Mapa etiqueta → indice en body
    label_idx: Dict[str, int] = {}
    for i, instr in enumerate(body):
        if isinstance(instr, IRLabel):
            label_idx[instr.name] = i

    loops: List[LoopInfo] = []

    for i, instr in enumerate(body):
        if not isinstance(instr, IRGoto):
            continue

        target = instr.target
        if target not in label_idx:
            continue

        header_idx = label_idx[target]
        latch_idx  = i

        # El target debe ser una etiqueta de inicio de loop
        if not (target.startswith("WHILE_START") or
                target.startswith("FOR_START")):
            continue

        # Buscar el IRIfFalse entre header y latch
        iffalse_idx = None
        exit_label  = None
        for j in range(header_idx + 1, latch_idx):
            if isinstance(body[j], (IRIfFalse, IRIfTrue)):
                iffalse_idx = j
                exit_label  = body[j].target
                break

        if iffalse_idx is None:
            continue   # loop sin condicion detectable, se omite

        # El exit_label debe existir despues del latch
        if exit_label not in label_idx:
            continue
        exit_idx = label_idx[exit_label]
        if exit_idx <= latch_idx:
            continue   # el exit esta antes del latch, estructura rara

        loops.append(LoopInfo(
            header_label = target,
            exit_label   = exit_label,
            header_idx   = header_idx,
            cond_start   = header_idx + 1,
            iffalse_idx  = iffalse_idx,
            body_start   = iffalse_idx + 1,
            latch_idx    = latch_idx,
            exit_idx     = exit_idx,
        ))

    # Procesar de adentro hacia afuera (loops mas internos primero)
    loops.sort(key=lambda l: l.header_idx, reverse=True)
    return loops


# ---------------------------------------------------------------------------
# Analisis del trip count
# ---------------------------------------------------------------------------

@dataclass
class TripCountInfo:
    loop_var:  str
    init_val:  int
    bound:     int
    step:      int
    op:        BinOp    # operador de comparacion

    def compute(self) -> Optional[int]:
        """
        Calcula el numero de iteraciones si es posible determinarlo
        estaticamente. Retorna None si no es calculable.
        """
        try:
            if self.op == BinOp.LT:
                iters = (self.bound - self.init_val + self.step - 1) // self.step
            elif self.op == BinOp.LE:
                iters = (self.bound - self.init_val + self.step) // self.step
            elif self.op == BinOp.GT:
                iters = (self.init_val - self.bound + self.step - 1) // self.step
            elif self.op == BinOp.GE:
                iters = (self.init_val - self.bound + self.step) // self.step
            else:
                return None
            return max(0, iters)
        except ZeroDivisionError:
            return None


def _try_get_trip_count(body: List[IRInstruction],
                         loop: LoopInfo) -> Optional[TripCountInfo]:
    """
    Intenta extraer el trip count para patrones simples:

        loop_var = CONST_INIT          (antes del header)
        loop_var OP CONST_BOUND        (condicion)
        loop_var = loop_var +/- STEP   (dentro del cuerpo)

    Retorna TripCountInfo o None si no es detectable.
    """
    # --- 1. Extraer variable y bound de la condicion ---
    # La condicion calcula: _tx = loop_var OP bound
    # iffalse _tx goto exit
    # Buscamos el IRBinOp que define la variable usada en el iffalse.

    cond_var = body[loop.iffalse_idx].cond if hasattr(body[loop.iffalse_idx], 'cond') else None
    if cond_var is None:
        return None

    # Buscar el IRBinOp que define cond_var en la seccion de condicion
    cmp_instr = None
    for j in range(loop.cond_start, loop.iffalse_idx):
        instr = body[j]
        if isinstance(instr, IRBinOp) and instr.dest == cond_var:
            cmp_instr = instr
            break

    if cmp_instr is None:
        return None

    # El operador debe ser una comparacion
    cmp_ops = {BinOp.LT, BinOp.LE, BinOp.GT, BinOp.GE}
    if cmp_instr.op not in cmp_ops:
        return None

    loop_var = cmp_instr.left
    bound_str = cmp_instr.right

    # El bound debe ser un literal entero
    try:
        bound = int(bound_str, 0)
    except (ValueError, TypeError):
        return None

    # --- 2. Buscar init del loop_var antes del header ---
    init_val = None
    for j in range(loop.header_idx - 1, -1, -1):
        instr = body[j]
        if isinstance(instr, IRCopy) and instr.dest == loop_var:
            try:
                init_val = int(instr.src, 0)
                break
            except (ValueError, TypeError):
                break   # no es literal, no podemos saber el init
        if isinstance(instr, IRLabel):
            break       # cruzamos una etiqueta, paramos

    if init_val is None:
        return None

    # --- 3. Buscar el step en el cuerpo ---
    # Patron: loop_var = loop_var + STEP  o  loop_var = loop_var - STEP
    step = None
    for j in range(loop.body_start, loop.latch_idx):
        instr = body[j]
        if isinstance(instr, IRBinOp) and instr.dest == loop_var:
            if instr.left == loop_var and instr.op in (BinOp.ADD, BinOp.SUB):
                try:
                    s = int(instr.right, 0)
                    step = s if instr.op == BinOp.ADD else -s
                    break
                except (ValueError, TypeError):
                    pass
        # IRCopy: loop_var = temp → el temp podria venir de loop_var + step
        if isinstance(instr, IRCopy) and instr.dest == loop_var:
            # buscar hacia atras el BinOp que define instr.src
            src = instr.src
            for k in range(j - 1, loop.body_start - 1, -1):
                b = body[k]
                if isinstance(b, IRBinOp) and b.dest == src:
                    if b.left == loop_var and b.op in (BinOp.ADD, BinOp.SUB):
                        try:
                            s = int(b.right, 0)
                            step = s if b.op == BinOp.ADD else -s
                            break
                        except (ValueError, TypeError):
                            pass
            if step is not None:
                break

    if step is None or step == 0:
        return None

    return TripCountInfo(
        loop_var = loop_var,
        init_val = init_val,
        bound    = bound,
        step     = step,
        op       = cmp_instr.op,
    )


# ---------------------------------------------------------------------------
# Clonacion de instrucciones
# ---------------------------------------------------------------------------

def _clone_instrs(instrs: List[IRInstruction],
                  suffix: str) -> List[IRInstruction]:
    """
    Clona una lista de instrucciones renombrando:
      - Temporales IR (_tN, _rnN_x) definidos en la lista.
      - Etiquetas locales al cuerpo (IRLabel.name, y los targets de
        IRGoto / IRIfTrue / IRIfFalse que apunten a esas etiquetas).

    Las variables del programa fuente (sin _ inicial: i, total, n, ...) NO
    se renombran: representan la misma variable compartida entre copias.
    Las etiquetas que apuntan FUERA del cuerpo (p.ej. el exit del loop)
    tampoco se tocan porque no estan en defined_labels.
    """
    # Recolectar temporales y etiquetas locales definidos en estas instrucciones
    defined_temps:  set = set()
    defined_labels: set = set()
    for instr in instrs:
        for var in instr.defs():
            if var.startswith("_"):
                defined_temps.add(var)
        if isinstance(instr, IRLabel):
            defined_labels.add(instr.name)

    cloned = []
    for instr in instrs:
        new_instr = copy.deepcopy(instr)

        # Renombrar temporales IR
        for temp in defined_temps:
            new_instr.rename(temp, f"{temp}{suffix}")

        # Renombrar etiquetas locales al cuerpo
        if isinstance(new_instr, IRLabel):
            if new_instr.name in defined_labels:
                new_instr.name = f"{new_instr.name}{suffix}"
        elif isinstance(new_instr, IRGoto):
            if new_instr.target in defined_labels:
                new_instr.target = f"{new_instr.target}{suffix}"
        elif isinstance(new_instr, IRIfTrue):
            if new_instr.target in defined_labels:
                new_instr.target = f"{new_instr.target}{suffix}"
        elif isinstance(new_instr, IRIfFalse):
            if new_instr.target in defined_labels:
                new_instr.target = f"{new_instr.target}{suffix}"

        cloned.append(new_instr)
    return cloned


# ---------------------------------------------------------------------------
# Heuristica para elegir el factor
# ---------------------------------------------------------------------------

def _choose_factor(body_size: int) -> int:
    """
    Heuristica automatica basada en el tamano del cuerpo del loop.
    Objetivo: no mas que ~3x el tamano original despues de unrolling.
    """
    if body_size <= 4:
        return 4
    if body_size <= 8:
        return 2
    return 1   # 1 = sin unrolling


# ---------------------------------------------------------------------------
# Aplicar unrolling a un loop
# ---------------------------------------------------------------------------

def _apply_full_unroll(body: List[IRInstruction],
                       loop: LoopInfo,
                       trip_count: int) -> List[IRInstruction]:
    """
    Full unrolling: elimina el loop completamente y replica el cuerpo
    trip_count veces. Solo se llama cuando trip_count es pequeno y conocido.
    """
    body_instrs = body[loop.body_start:loop.latch_idx]

    unrolled: List[IRInstruction] = []
    for k in range(trip_count):
        suffix = f"_fu{k}" if k > 0 else ""
        if suffix:
            unrolled.extend(_clone_instrs(body_instrs, suffix))
        else:
            unrolled.extend(copy.deepcopy(instr) for instr in body_instrs)

    # Reemplazar el loop completo (header ... exit_label inclusive)
    # con las instrucciones desenrolladas mas el exit label
    before = body[:loop.header_idx]
    after  = body[loop.exit_idx:]   # incluye IRLabel(exit_label)

    return before + unrolled + after


def _apply_partial_unroll(body: List[IRInstruction],
                           loop: LoopInfo,
                           factor: int) -> List[IRInstruction]:
    """
    Partial unrolling con factor F: replica el cuerpo F veces dentro del
    loop, con chequeo de condicion entre copias para manejar el caso en que
    el numero de iteraciones no es multiplo de F.
    """
    cond_instrs  = body[loop.cond_start:loop.iffalse_idx]
    iffalse_instr = body[loop.iffalse_idx]
    body_instrs  = body[loop.body_start:loop.latch_idx]

    new_body: List[IRInstruction] = []

    for k in range(factor):
        suffix = f"_pu{k}" if k > 0 else ""

        # Copia del cuerpo
        if suffix:
            new_body.extend(_clone_instrs(body_instrs, suffix))
        else:
            new_body.extend(copy.deepcopy(i) for i in body_instrs)

        # Chequeo de condicion entre copias (no despues de la ultima)
        if k < factor - 1:
            cond_suffix = f"_pu{k}"
            new_body.extend(_clone_instrs(cond_instrs, cond_suffix))
            # Clonar el iffalse con nuevos temporales
            new_iffalse = copy.deepcopy(iffalse_instr)
            # Renombrar la variable de condicion en el iffalse clonado
            for instr in _clone_instrs(cond_instrs, cond_suffix):
                for var in instr.defs():
                    if var.startswith("_"):
                        new_iffalse.rename_uses(
                            body[loop.iffalse_idx].cond,
                            var
                        )
            new_body.append(new_iffalse)

    # Reconstruir: header + condicion original + new_body + goto + exit
    before       = body[:loop.body_start]           # header + cond original
    goto_and_exit = body[loop.latch_idx:]            # goto + exit label

    return before + new_body + goto_and_exit


# ---------------------------------------------------------------------------
# Interfaz publica
# ---------------------------------------------------------------------------

@dataclass
class UnrollStats:
    """Metricas del pass de loop unrolling."""
    loops_found:        int = 0
    loops_full_unrolled:    int = 0
    loops_partial_unrolled: int = 0
    loops_skipped:      int = 0
    instrs_before:      int = 0
    instrs_after:       int = 0


def unroll_function(ir_func: IRFunction,
                    factor: int = DEFAULT_FACTOR,
                    max_full: int = DEFAULT_MAX_FULL_UNROLL) -> UnrollStats:
    """
    Aplica loop unrolling al body plano de una IRFunction.

    Parametros:
        factor    Factor de unrolling. 0 = usar heuristica automatica.
                  1 = sin unrolling (no-op).
        max_full  Maximo trip count para aplicar full unrolling.
                  0 = desactivar full unrolling.

    Modifica ir_func.body in-place.
    Retorna UnrollStats con las metricas del pass.
    """
    stats = UnrollStats()
    stats.instrs_before = len(ir_func.body)

    # Iterar hasta que no haya mas loops que unrollear
    # (necesario porque al modificar el body los indices cambian)
    changed = True
    while changed:
        changed = False
        loops = _find_loops(ir_func.body)
        stats.loops_found += len(loops)

        for loop in loops:
            body_instrs = ir_func.body[loop.body_start:loop.latch_idx]
            body_size   = len(body_instrs)

            # Intentar full unrolling si el trip count es constante y pequeno
            if max_full > 0:
                tc_info = _try_get_trip_count(ir_func.body, loop)
                if tc_info is not None:
                    trip = tc_info.compute()
                    if trip is not None and 0 < trip <= max_full:
                        ir_func.body = _apply_full_unroll(
                            ir_func.body, loop, trip
                        )
                        stats.loops_full_unrolled += 1
                        changed = True
                        break   # reiniciar busqueda (indices cambiaron)

            # Partial unrolling
            f = factor if factor > 0 else _choose_factor(body_size)
            if f <= 1:
                continue   # no hay unrolling util
            ir_func.body = _apply_partial_unroll(ir_func.body, loop, f)
            stats.loops_partial_unrolled += 1
            changed = True
            break   # reiniciar busqueda

    stats.instrs_after = len(ir_func.body)
    return stats


def unroll_program(ir_program: IRProgram,
                   factor: int = 0,
                   max_full: int = 6) -> UnrollStats:
    """
    Aplica loop unrolling a todas las funciones del programa.
    """
    total = UnrollStats()
    for func in ir_program.functions:
        s = unroll_function(func, factor=factor, max_full=max_full)
        total.loops_full_unrolled    += s.loops_full_unrolled
        total.loops_partial_unrolled += s.loops_partial_unrolled
        total.instrs_before          += s.instrs_before
        total.instrs_after           += s.instrs_after
    return total
