"""
optimizer.py - Pipeline de optimizacion IR.

Que hace
--------
Encadena todos los passes de optimizacion sobre un IRProgram en el orden
correcto, segun el nivel de optimizacion solicitado.

Niveles de optimizacion
-----------------------
  O0  Sin optimizacion (pass-through).
  O1  Optimizaciones conservadoras:
        1. Rename  - elimina dependencias WAR/WAW falsas
        2. DCE     - elimina codigo muerto
  O2  Optimizaciones agresivas (todo O1 mas):
        3. Loop unrolling - despliega loops de trip-count conocido
        4. Scheduling     - reordena instrucciones para reducir RAW hazards

Cadena de passes
----------------
  rename -> DCE -> [loop_unroll -> DCE -> rename] -> schedule

  El DCE despues del unrolling limpia variables temporales extra generadas
  por el unrolling. El rename antes del scheduling maximiza los movimientos
  que el scheduler puede hacer.

Interfaz publica
----------------
  OptimizationLevel              enum O0 / O1 / O2
  OptimizerStats                 metricas agregadas de todos los passes
  optimize_program(prog, level)  aplica el pipeline y retorna stats
  optimize_function(func, level) aplica el pipeline a una sola funcion
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional

from .ir_program import IRFunction, IRProgram
from .renamer import rename_program, rename_function, RenamerState
from .dce import dce_program, eliminate_dead_code, DCEStats
from .loop_unroller import unroll_program, unroll_function, UnrollStats
from .scheduler import schedule_program, schedule_function, SchedulerStats


# ---------------------------------------------------------------------------
# Nivel de optimizacion
# ---------------------------------------------------------------------------

class OptimizationLevel(Enum):
    O0 = 0   # Sin optimizacion
    O1 = 1   # Rename + DCE
    O2 = 2   # Rename + DCE + Loop unroll + DCE + Rename + Schedule


# ---------------------------------------------------------------------------
# Metricas del pipeline
# ---------------------------------------------------------------------------

@dataclass
class OptimizerStats:
    """Metricas agregadas del pipeline de optimizacion."""
    level: OptimizationLevel = OptimizationLevel.O0

    # Conteos globales de instrucciones
    instrs_before: int = 0
    instrs_after:  int = 0

    # Stats por pass (None si el pass no se ejecuto)
    rename_vars_created:   int = 0
    dce_instrs_removed:    int = 0          # total entre todas las pasadas DCE
    unroll_loops_expanded: int = 0
    unroll_instrs_added:   int = 0
    sched_instrs_moved:    int = 0
    sched_blocks_changed:  int = 0

    # Tiempo de compilacion del pipeline
    elapsed_ms: float = 0.0

    @property
    def instrs_saved(self) -> int:
        return self.instrs_before - self.instrs_after

    def __str__(self) -> str:
        lines = [
            f"Optimization level : {self.level.name}",
            f"Instructions before: {self.instrs_before}",
            f"Instructions after : {self.instrs_after}",
            f"Instructions saved : {self.instrs_saved}",
        ]
        if self.level.value >= 1:
            lines += [
                f"  [rename] vars created  : {self.rename_vars_created}",
                f"  [dce]    instrs removed: {self.dce_instrs_removed}",
            ]
        if self.level.value >= 2:
            lines += [
                f"  [unroll] loops expanded: {self.unroll_loops_expanded}",
                f"  [unroll] instrs added  : {self.unroll_instrs_added}",
                f"  [sched]  instrs moved  : {self.sched_instrs_moved}",
                f"  [sched]  blocks changed: {self.sched_blocks_changed}",
            ]
        lines.append(f"Pipeline time      : {self.elapsed_ms:.1f} ms")
        return "\n".join(lines)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _count_instrs(ir_program: IRProgram) -> int:
    return sum(len(f.body) for f in ir_program.functions)


def _count_instrs_func(ir_func: IRFunction) -> int:
    return len(ir_func.body)


# ---------------------------------------------------------------------------
# Pipeline por funcion
# ---------------------------------------------------------------------------

def optimize_function(ir_func: IRFunction,
                      level: OptimizationLevel = OptimizationLevel.O1
                      ) -> OptimizerStats:
    """
    Aplica el pipeline de optimizacion a una sola funcion.

    Util para pruebas unitarias o compilacion funcion por funcion.
    """
    stats = OptimizerStats(level=level)
    stats.instrs_before = _count_instrs_func(ir_func)

    t0 = time.perf_counter()

    if level == OptimizationLevel.O0:
        pass

    elif level == OptimizationLevel.O1:
        # Pass 1: Rename
        rs = RenamerState()
        rename_function(ir_func, state=rs)
        stats.rename_vars_created = rs.counter

        # Pass 2: DCE
        dce_s: DCEStats = eliminate_dead_code(ir_func)
        stats.dce_instrs_removed = dce_s.instrs_removed

    elif level == OptimizationLevel.O2:
        # Pass 1: Rename inicial
        rs1 = RenamerState()
        rename_function(ir_func, state=rs1)
        stats.rename_vars_created += rs1.counter

        # Pass 2: DCE inicial
        dce_s1: DCEStats = eliminate_dead_code(ir_func)
        stats.dce_instrs_removed += dce_s1.instrs_removed

        # Pass 3: Loop unrolling
        unroll_s: UnrollStats = unroll_function(ir_func)
        stats.unroll_loops_expanded = (unroll_s.loops_full_unrolled +
                                       unroll_s.loops_partial_unrolled)
        stats.unroll_instrs_added   = max(0, unroll_s.instrs_after -
                                          unroll_s.instrs_before)

        # Pass 4: DCE post-unrolling (limpia temporales extra)
        dce_s2: DCEStats = eliminate_dead_code(ir_func)
        stats.dce_instrs_removed += dce_s2.instrs_removed

        # Pass 5: Rename post-unrolling (maximiza independencia para scheduler)
        rs2 = RenamerState()
        rename_function(ir_func, state=rs2)
        stats.rename_vars_created += rs2.counter

        # Pass 6: Instruction scheduling
        sched_s: SchedulerStats = schedule_function(ir_func)
        stats.sched_instrs_moved    = sched_s.instrs_moved
        stats.sched_blocks_changed  = sched_s.blocks_changed

    stats.elapsed_ms = (time.perf_counter() - t0) * 1000
    stats.instrs_after = _count_instrs_func(ir_func)
    return stats


# ---------------------------------------------------------------------------
# Pipeline por programa (interfaz principal)
# ---------------------------------------------------------------------------

def optimize_program(ir_program: IRProgram,
                     level: OptimizationLevel = OptimizationLevel.O1
                     ) -> OptimizerStats:
    """
    Aplica el pipeline de optimizacion a todo el programa.

    Modifica ir_program in-place.
    Retorna OptimizerStats con metricas agregadas.
    """
    stats = OptimizerStats(level=level)
    stats.instrs_before = _count_instrs(ir_program)

    t0 = time.perf_counter()

    if level == OptimizationLevel.O0:
        pass   # nada que hacer

    elif level == OptimizationLevel.O1:
        # Pass 1: Rename (programa completo)
        rs = rename_program(ir_program)
        stats.rename_vars_created = rs.counter

        # Pass 2: DCE
        dce_s: DCEStats = dce_program(ir_program)
        stats.dce_instrs_removed = dce_s.instrs_removed

    elif level == OptimizationLevel.O2:
        # Pass 1: Rename inicial
        rs1 = rename_program(ir_program)
        stats.rename_vars_created += rs1.counter

        # Pass 2: DCE inicial
        dce_s1: DCEStats = dce_program(ir_program)
        stats.dce_instrs_removed += dce_s1.instrs_removed

        # Pass 3: Loop unrolling
        unroll_s: UnrollStats = unroll_program(ir_program)
        stats.unroll_loops_expanded = (unroll_s.loops_full_unrolled +
                                       unroll_s.loops_partial_unrolled)
        stats.unroll_instrs_added   = max(0, unroll_s.instrs_after -
                                          unroll_s.instrs_before)

        # Pass 4: DCE post-unrolling
        dce_s2: DCEStats = dce_program(ir_program)
        stats.dce_instrs_removed += dce_s2.instrs_removed

        # Pass 5: Rename post-unrolling
        rs2 = rename_program(ir_program)
        stats.rename_vars_created += rs2.counter

        # Pass 6: Instruction scheduling
        sched_s: SchedulerStats = schedule_program(ir_program)
        stats.sched_instrs_moved   = sched_s.instrs_moved
        stats.sched_blocks_changed = sched_s.blocks_changed

    stats.elapsed_ms = (time.perf_counter() - t0) * 1000
    stats.instrs_after = _count_instrs(ir_program)
    return stats
