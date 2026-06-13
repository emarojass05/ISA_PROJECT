from __future__ import annotations

from dataclasses import dataclass, field
from typing import Set

from .ir_types import (
    IRInstruction, IRStore, IRCall, IRReturn,
    IRLabel, IRGoto, IRIfTrue, IRIfFalse,
)
from .ir_program import IRFunction, IRProgram
from .cfg import CFG
from .liveness import analyze_liveness, instr_liveness


# ---------------------------------------------------------------------------

_SIDE_EFFECT_TYPES = (IRStore, IRCall, IRReturn, IRLabel, IRGoto, IRIfTrue, IRIfFalse)


def _has_side_effect(instr: IRInstruction) -> bool:
    """Return True if the instruction has observable side effects."""
    if isinstance(instr, _SIDE_EFFECT_TYPES):
        return True
    # Some instances carry an explicit has_side_effect flag
    if hasattr(instr, "has_side_effect") and instr.has_side_effect:
        return True
    return False


# ---------------------------------------------------------------------------

@dataclass
class DCEStats:
    """Metrics for the Dead Code Elimination pass."""
    instrs_before:   int = 0
    instrs_after:    int = 0
    instrs_removed:  int = 0
    iters:           int = 0

    @property
    def reduction_pct(self) -> float:
        """Percentage of instructions eliminated."""
        if self.instrs_before == 0:
            return 0.0
        return 100.0 * self.instrs_removed / self.instrs_before


# ---------------------------------------------------------------------------

def _dce_pass(ir_func: IRFunction) -> int:
    """Execute one DCE pass; return number of instructions removed."""
    cfg = CFG.build_from_function(ir_func)
    res = analyze_liveness(cfg)
    removed = 0

    for block in cfg.blocks:
        live_out_set = res.live_out(block)
        il_list = instr_liveness(block, live_out_set)

        kept = []
        for instr, il in zip(block.instructions, il_list):
            # Never remove instructions with side effects
            if _has_side_effect(instr):
                kept.append(instr)
                continue

            defs = instr.defs()
            if not defs:
                # No definition (rare) -> keep
                kept.append(instr)
                continue

            # Remove if none of the defined variables are live after
            if defs.isdisjoint(il.live_after):
                removed += 1
                # Not added to kept -> eliminated
            else:
                kept.append(instr)

        block.instructions = kept

    # Flatten the body from the modified blocks
    ir_func.body = [
        instr
        for block in cfg.blocks
        for instr in block.instructions
    ]

    return removed


# ---------------------------------------------------------------------------

def eliminate_dead_code(ir_func: IRFunction) -> DCEStats:
    """Apply iterative DCE to an IRFunction until no more code can be removed."""
    stats = DCEStats()
    stats.instrs_before = len(ir_func.body)

    changed = True
    while changed:
        stats.iters += 1
        n_removed = _dce_pass(ir_func)
        stats.instrs_removed += n_removed
        changed = (n_removed > 0)

    stats.instrs_after = len(ir_func.body)
    return stats


def dce_program(ir_program: IRProgram) -> DCEStats:
    """Apply DCE to all functions in the program; return accumulated stats."""
    total = DCEStats()
    for func in ir_program.functions:
        s = eliminate_dead_code(func)
        total.instrs_before  += s.instrs_before
        total.instrs_after   += s.instrs_after
        total.instrs_removed += s.instrs_removed
        total.iters          += s.iters
    return total
