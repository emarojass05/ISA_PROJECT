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

DEFAULT_MAX_FULL_UNROLL = 16   # max trip count for full unrolling
DEFAULT_FACTOR          = 0    # 0 = use heuristic


# ---------------------------------------------------------------------------

@dataclass
class LoopInfo:
    """Describes one natural loop found in a flat function body.

    All indices reference positions in body[]:
        body[header_idx]  = IRLabel(header_label)
        body[iffalse_idx] = IRIfFalse(cond, exit_label)
        body[body_start]  = first instruction of the loop body
        body[latch_idx]   = IRGoto(header_label)  -- back-edge
        body[exit_idx]    = IRLabel(exit_label)
    """
    header_label: str
    exit_label:   str
    header_idx:   int
    cond_start:   int
    iffalse_idx:  int
    body_start:   int
    latch_idx:    int
    exit_idx:     int


# ---------------------------------------------------------------------------

def _find_loops(body: List[IRInstruction]) -> List[LoopInfo]:
    """Scan flat body and return a LoopInfo for each detected natural loop.

    A loop exists when an IRGoto targets a label that appears earlier (back-edge)
    and that label starts with WHILE_START or FOR_START.
    """
    # Map label name -> index in body
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

        # Target must be a loop-start label
        if not (target.startswith("WHILE_START") or
                target.startswith("FOR_START")):
            continue

        # Find the IRIfFalse between header and latch
        iffalse_idx = None
        exit_label  = None
        for j in range(header_idx + 1, latch_idx):
            if isinstance(body[j], (IRIfFalse, IRIfTrue)):
                iffalse_idx = j
                exit_label  = body[j].target
                break

        if iffalse_idx is None:
            continue   # no detectable condition

        if exit_label not in label_idx:
            continue
        exit_idx = label_idx[exit_label]
        if exit_idx <= latch_idx:
            continue   # exit before latch -- unusual structure

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

    # Process innermost loops first
    loops.sort(key=lambda l: l.header_idx, reverse=True)
    return loops


# ---------------------------------------------------------------------------

@dataclass
class TripCountInfo:
    loop_var:  str
    init_val:  int
    bound:     int
    step:      int
    op:        BinOp    # comparison operator

    def compute(self) -> Optional[int]:
        """Return static iteration count, or None if not computable.

        Guards against step/operator sign mismatches that would produce a
        spuriously large iteration count for a loop that actually runs 0 times
        (e.g. i=10; i<0; step=+1 should yield 0, not 12).
        """
        try:
            # LT/LE require a positive step; GT/GE require a negative step.
            if self.op in (BinOp.LT, BinOp.LE) and self.step <= 0:
                return None
            if self.op in (BinOp.GT, BinOp.GE) and self.step >= 0:
                return None

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
    """Try to extract trip count for simple patterns:
        loop_var = CONST_INIT  (before header)
        loop_var OP CONST_BOUND (condition)
        loop_var = loop_var +/- STEP (in body)
    Returns TripCountInfo or None.
    """
    # Extract condition variable from the iffalse instruction
    cond_var = body[loop.iffalse_idx].cond if hasattr(body[loop.iffalse_idx], 'cond') else None
    if cond_var is None:
        return None

    # Find the IRBinOp defining cond_var in the condition section
    cmp_instr = None
    for j in range(loop.cond_start, loop.iffalse_idx):
        instr = body[j]
        if isinstance(instr, IRBinOp) and instr.dest == cond_var:
            cmp_instr = instr
            break

    if cmp_instr is None:
        return None

    cmp_ops = {BinOp.LT, BinOp.LE, BinOp.GT, BinOp.GE}
    if cmp_instr.op not in cmp_ops:
        return None

    loop_var = cmp_instr.left
    bound_str = cmp_instr.right

    # If loop_var is a temp, resolve it to the underlying source variable.
    # The IR generator loads the loop variable into a temp before comparing:
    #   _t = i  (IRCopy)
    #   _tcond = _t < N
    if loop_var.startswith("_"):
        for j in range(loop.cond_start, loop.iffalse_idx):
            instr = body[j]
            if isinstance(instr, IRCopy) and instr.dest == loop_var:
                loop_var = instr.src
                break

    # Bound must be an integer literal
    try:
        bound = int(bound_str, 0)
    except (ValueError, TypeError):
        return None

    # Find init value before the header
    init_val = None
    for j in range(loop.header_idx - 1, -1, -1):
        instr = body[j]
        if isinstance(instr, IRCopy) and instr.dest == loop_var:
            try:
                init_val = int(instr.src, 0)
                break
            except (ValueError, TypeError):
                break
        if isinstance(instr, IRLabel):
            break

    if init_val is None:
        return None

    # Find the step in the loop body
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
        # Pattern: loop_var = temp, where temp = loop_var + step
        # Also handles: loop_var = tmp2, tmp2 = tmp1 + step, tmp1 = loop_var
        if isinstance(instr, IRCopy) and instr.dest == loop_var:
            src = instr.src
            for k in range(j - 1, loop.body_start - 1, -1):
                b = body[k]
                if isinstance(b, IRBinOp) and b.dest == src:
                    if b.op not in (BinOp.ADD, BinOp.SUB):
                        continue
                    # Direct: tmp = loop_var +/- step
                    lhs = b.left
                    if lhs == loop_var:
                        try:
                            s = int(b.right, 0)
                            step = s if b.op == BinOp.ADD else -s
                            break
                        except (ValueError, TypeError):
                            pass
                    else:
                        # Indirect: tmp1 = loop_var; tmp2 = tmp1 +/- step
                        for m in range(k - 1, loop.body_start - 1, -1):
                            c = body[m]
                            if isinstance(c, IRCopy) and c.dest == lhs and c.src == loop_var:
                                try:
                                    s = int(b.right, 0)
                                    step = s if b.op == BinOp.ADD else -s
                                except (ValueError, TypeError):
                                    pass
                                break
                        if step is not None:
                            break
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

def _clone_instrs(instrs: List[IRInstruction],
                  suffix: str) -> List[IRInstruction]:
    """Clone instructions, renaming IR temporals and local labels with suffix.

    Source-level variables (no leading underscore) are not renamed;
    they represent the same shared variable across copies.
    Labels that point outside the body (e.g. the loop exit) are not renamed.
    """
    # Collect IR temporals and local labels defined in these instructions
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

        # Rename IR temporals
        for temp in defined_temps:
            new_instr.rename(temp, f"{temp}{suffix}")

        # Rename labels local to this body
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

def _choose_factor(body_size: int) -> int:
    """Auto-select unroll factor to keep code growth within ~3x."""
    if body_size <= 4:
        return 4
    if body_size <= 8:
        return 2
    return 1   # 1 = no unrolling


# ---------------------------------------------------------------------------

def _apply_full_unroll(body: List[IRInstruction],
                       loop: LoopInfo,
                       trip_count: int) -> List[IRInstruction]:
    """Full unrolling: remove the loop and replicate body trip_count times."""
    body_instrs = body[loop.body_start:loop.latch_idx]

    unrolled: List[IRInstruction] = []
    for k in range(trip_count):
        suffix = f"_fu{k}" if k > 0 else ""
        if suffix:
            unrolled.extend(_clone_instrs(body_instrs, suffix))
        else:
            unrolled.extend(copy.deepcopy(instr) for instr in body_instrs)

    # Replace the entire loop region with the unrolled body + exit label
    before = body[:loop.header_idx]
    after  = body[loop.exit_idx:]   # includes IRLabel(exit_label)

    return before + unrolled + after


def _apply_partial_unroll(body: List[IRInstruction],
                           loop: LoopInfo,
                           factor: int) -> List[IRInstruction]:
    """Partial unrolling: replicate body factor times inside the loop.

    A condition check is inserted between copies to handle trip counts
    that are not multiples of factor.
    """
    cond_instrs  = body[loop.cond_start:loop.iffalse_idx]
    iffalse_instr = body[loop.iffalse_idx]
    body_instrs  = body[loop.body_start:loop.latch_idx]

    new_body: List[IRInstruction] = []

    for k in range(factor):
        suffix = f"_pu{k}" if k > 0 else ""

        # Copy of the body
        if suffix:
            new_body.extend(_clone_instrs(body_instrs, suffix))
        else:
            new_body.extend(copy.deepcopy(i) for i in body_instrs)

        # Condition check between copies (not after the last one)
        if k < factor - 1:
            cond_suffix = f"_pu{k}"
            cloned_cond = _clone_instrs(cond_instrs, cond_suffix)
            new_body.extend(cloned_cond)
            # Clone the iffalse and update its cond variable to the suffixed
            # version.  Find the specific instruction that defines the original
            # cond variable and use its (now-renamed) def as the new cond.
            orig_cond = body[loop.iffalse_idx].cond
            new_cond  = orig_cond  # fallback: keep original if not found
            for instr in cloned_cond:
                defs = instr.defs()
                # The suffixed version of orig_cond is what we need
                expected = f"{orig_cond}{cond_suffix}"
                if expected in defs:
                    new_cond = expected
                    break
            new_iffalse = copy.deepcopy(iffalse_instr)
            if new_cond != orig_cond:
                new_iffalse.rename_uses(orig_cond, new_cond)
            new_body.append(new_iffalse)

    # Reconstruct: header + original condition + new_body + goto + exit
    before        = body[:loop.body_start]
    goto_and_exit = body[loop.latch_idx:]

    return before + new_body + goto_and_exit


# ---------------------------------------------------------------------------

@dataclass
class UnrollStats:
    """Metrics for the loop unrolling pass."""
    loops_found:            int = 0
    loops_full_unrolled:    int = 0
    loops_partial_unrolled: int = 0
    loops_skipped:          int = 0
    instrs_before:          int = 0
    instrs_after:           int = 0


def unroll_function(ir_func: IRFunction,
                    factor: int = DEFAULT_FACTOR,
                    max_full: int = DEFAULT_MAX_FULL_UNROLL) -> UnrollStats:
    """Apply loop unrolling to a function body.

    factor=0 uses the automatic heuristic; factor=1 is a no-op.
    max_full=0 disables full unrolling.
    Modifies ir_func.body in-place.
    """
    stats = UnrollStats()
    stats.instrs_before = len(ir_func.body)

    # Track header labels already partially unrolled to avoid infinite loops.
    # Full unrolling removes the loop entirely so it won't be seen again.
    # Partial unrolling keeps the loop alive, so we must skip it next pass.
    partial_done: set = set()

    # Repeat until no more loops to unroll (indices shift after each edit)
    changed = True
    while changed:
        changed = False
        loops = _find_loops(ir_func.body)
        stats.loops_found += len(loops)

        for loop in loops:
            body_instrs = ir_func.body[loop.body_start:loop.latch_idx]
            body_size   = len(body_instrs)

            # Attempt full unrolling for small known trip counts
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
                        break   # restart search (indices changed)

            # Partial unrolling - skip loops already partially unrolled
            if loop.header_label in partial_done:
                continue

            f = factor if factor > 0 else _choose_factor(body_size)
            if f <= 1:
                continue   # no useful unrolling
            ir_func.body = _apply_partial_unroll(ir_func.body, loop, f)
            partial_done.add(loop.header_label)
            stats.loops_partial_unrolled += 1
            changed = True
            break   # restart search

    stats.instrs_after = len(ir_func.body)
    return stats


def unroll_program(ir_program: IRProgram,
                   factor: int = DEFAULT_FACTOR,
                   max_full: int = DEFAULT_MAX_FULL_UNROLL) -> UnrollStats:
    """Apply loop unrolling to all functions in the program."""
    total = UnrollStats()
    for func in ir_program.functions:
        s = unroll_function(func, factor=factor, max_full=max_full)
        total.loops_full_unrolled    += s.loops_full_unrolled
        total.loops_partial_unrolled += s.loops_partial_unrolled
        total.instrs_before          += s.instrs_before
        total.instrs_after           += s.instrs_after
    return total
