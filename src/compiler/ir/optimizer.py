from __future__ import annotations

import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional

from .ir_program import IRFunction, IRProgram
from .renamer import rename_program, rename_function, RenamerState
from .dce import dce_program, eliminate_dead_code, DCEStats
from .loop_unroller import unroll_program, unroll_function, UnrollStats, DEFAULT_MAX_FULL_UNROLL
from .scheduler import schedule_program, schedule_function, SchedulerStats
from .copy_propagation import propagate_copies_program, propagate_copies_function


# ---------------------------------------------------------------------------

class OptimizationLevel(Enum):
    O0 = 0   # no optimization
    O1 = 1   # rename + DCE
    O2 = 2   # rename + DCE + loop unroll + DCE + rename + schedule


# ---------------------------------------------------------------------------

@dataclass
class OptimizerStats:
    """Aggregated metrics for the full optimization pipeline."""
    level: OptimizationLevel = OptimizationLevel.O0

    instrs_before: int = 0
    instrs_after:  int = 0

    rename_vars_created:   int = 0
    dce_instrs_removed:    int = 0
    unroll_loops_expanded: int = 0
    unroll_instrs_added:   int = 0
    sched_instrs_moved:    int = 0
    sched_blocks_changed:  int = 0

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

def _count_instrs(ir_program: IRProgram) -> int:
    return sum(len(f.body) for f in ir_program.functions)


def _count_instrs_func(ir_func: IRFunction) -> int:
    return len(ir_func.body)


# ---------------------------------------------------------------------------

def optimize_function(ir_func: IRFunction,
                      level: OptimizationLevel = OptimizationLevel.O1,
                      unroll_factor: int = 0,
                      unroll_max_full: int = DEFAULT_MAX_FULL_UNROLL,
                      ) -> OptimizerStats:
    """Apply the optimization pipeline to a single function."""
    stats = OptimizerStats(level=level)
    stats.instrs_before = _count_instrs_func(ir_func)

    t0 = time.perf_counter()

    if level == OptimizationLevel.O0:
        pass

    elif level == OptimizationLevel.O1:
        # rename to break false dependencies
        rs = RenamerState()
        rename_function(ir_func, state=rs)
        stats.rename_vars_created = rs.counter

        # copy propagation eliminates rename-generated copies
        propagate_copies_function(ir_func)

        dce_s: DCEStats = eliminate_dead_code(ir_func)
        stats.dce_instrs_removed = dce_s.instrs_removed

    elif level == OptimizationLevel.O2:
        rs1 = RenamerState()
        rename_function(ir_func, state=rs1)
        stats.rename_vars_created += rs1.counter

        propagate_copies_function(ir_func)

        dce_s1: DCEStats = eliminate_dead_code(ir_func)
        stats.dce_instrs_removed += dce_s1.instrs_removed

        # loop unrolling (factor and max_full configurable)
        unroll_s: UnrollStats = unroll_function(
            ir_func, factor=unroll_factor, max_full=unroll_max_full
        )
        stats.unroll_loops_expanded = (unroll_s.loops_full_unrolled +
                                       unroll_s.loops_partial_unrolled)
        stats.unroll_instrs_added   = max(0, unroll_s.instrs_after -
                                          unroll_s.instrs_before)

        # DCE after unrolling cleans extra temporals
        dce_s2: DCEStats = eliminate_dead_code(ir_func)
        stats.dce_instrs_removed += dce_s2.instrs_removed

        # rename after unrolling maximizes scheduler freedom
        rs2 = RenamerState()
        rename_function(ir_func, state=rs2)
        stats.rename_vars_created += rs2.counter

        propagate_copies_function(ir_func)

        sched_s: SchedulerStats = schedule_function(ir_func)
        stats.sched_instrs_moved    = sched_s.instrs_moved
        stats.sched_blocks_changed  = sched_s.blocks_changed

    stats.elapsed_ms = (time.perf_counter() - t0) * 1000
    stats.instrs_after = _count_instrs_func(ir_func)
    return stats


# ---------------------------------------------------------------------------

def optimize_program(ir_program: IRProgram,
                     level: OptimizationLevel = OptimizationLevel.O1,
                     unroll_factor: int = 0,
                     unroll_max_full: int = DEFAULT_MAX_FULL_UNROLL,
                     ) -> OptimizerStats:
    """Apply the optimization pipeline to the full program.

    Modifies ir_program in-place; returns aggregated OptimizerStats.
    unroll_factor: 0 = heuristic, 1 = disabled, N = explicit factor.
    unroll_max_full: max trip count for full unrolling (0 = disable full unroll).
    """
    stats = OptimizerStats(level=level)
    stats.instrs_before = _count_instrs(ir_program)

    t0 = time.perf_counter()

    if level == OptimizationLevel.O0:
        pass

    elif level == OptimizationLevel.O1:
        # rename to break false dependencies
        rs = rename_program(ir_program)
        stats.rename_vars_created = rs.counter

        # copy propagation eliminates rename-generated copies
        propagate_copies_program(ir_program)

        dce_s: DCEStats = dce_program(ir_program)
        stats.dce_instrs_removed = dce_s.instrs_removed

    elif level == OptimizationLevel.O2:
        rs1 = rename_program(ir_program)
        stats.rename_vars_created += rs1.counter

        propagate_copies_program(ir_program)

        dce_s1: DCEStats = dce_program(ir_program)
        stats.dce_instrs_removed += dce_s1.instrs_removed

        # loop unrolling (factor and max_full configurable via CLI)
        unroll_s: UnrollStats = unroll_program(
            ir_program, factor=unroll_factor, max_full=unroll_max_full
        )
        stats.unroll_loops_expanded = (unroll_s.loops_full_unrolled +
                                       unroll_s.loops_partial_unrolled)
        stats.unroll_instrs_added   = max(0, unroll_s.instrs_after -
                                          unroll_s.instrs_before)

        # DCE after unrolling cleans extra temporals
        dce_s2: DCEStats = dce_program(ir_program)
        stats.dce_instrs_removed += dce_s2.instrs_removed

        # rename after unrolling maximizes scheduler freedom
        rs2 = rename_program(ir_program)
        stats.rename_vars_created += rs2.counter

        propagate_copies_program(ir_program)

        sched_s: SchedulerStats = schedule_program(ir_program)
        stats.sched_instrs_moved   = sched_s.instrs_moved
        stats.sched_blocks_changed = sched_s.blocks_changed

    stats.elapsed_ms = (time.perf_counter() - t0) * 1000
    stats.instrs_after = _count_instrs(ir_program)
    return stats
