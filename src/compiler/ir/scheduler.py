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

def _is_label(i: IRInstruction) -> bool:
    return isinstance(i, IRLabel)

def _is_terminator(i: IRInstruction) -> bool:
    return isinstance(i, (IRGoto, IRIfTrue, IRIfFalse, IRReturn))

def _is_memory(i: IRInstruction) -> bool:
    return isinstance(i, (IRLoad, IRStore))

def _is_barrier(i: IRInstruction) -> bool:
    """IRCall is a two-sided barrier: nothing may cross it."""
    return isinstance(i, IRCall)


# ---------------------------------------------------------------------------

@dataclass
class DepNode:
    """One instruction in the dependency DAG."""
    idx:         int
    instr:       IRInstruction
    succs:       List[int] = field(default_factory=list)
    preds_count: int = 0
    priority:    int = 0


# ---------------------------------------------------------------------------

def _build_dag(instrs: List[IRInstruction]) -> List[DepNode]:
    """Build the dependency DAG for a list of instructions."""
    n = len(instrs)
    nodes = [DepNode(idx=i, instr=instrs[i]) for i in range(n)]

    last_def: Dict[str, int] = {}
    last_uses: Dict[str, List[int]] = {}
    last_mem: int = -1
    last_barrier: int = -1

    def add_edge(src: int, dst: int) -> None:
        if dst not in nodes[src].succs:
            nodes[src].succs.append(dst)
            nodes[dst].preds_count += 1

    for j, instr in enumerate(instrs):
        uses_j = instr.uses()
        defs_j = instr.defs()

        # Forward barrier: everything after last barrier depends on it
        if last_barrier >= 0 and j != last_barrier:
            add_edge(last_barrier, j)

        # Backward barrier: if j is IRCall, all prior instructions precede it
        if _is_barrier(instr):
            for k in range(j):
                add_edge(k, j)

        # RAW: j reads a variable defined by an earlier instruction
        for var in uses_j:
            if var in last_def:
                add_edge(last_def[var], j)

        # WAR: j defines a variable read by earlier instructions
        for var in defs_j:
            if var in last_uses:
                for k in last_uses[var]:
                    if k != j:
                        add_edge(k, j)

        # WAW: j defines a variable already defined
        for var in defs_j:
            if var in last_def and last_def[var] != j:
                add_edge(last_def[var], j)

        # MEM: conservative ordering between all memory accesses
        if _is_memory(instr):
            if last_mem >= 0:
                add_edge(last_mem, j)
            last_mem = j

        if _is_barrier(instr):
            last_barrier = j

        for var in defs_j:
            last_def[var] = j
        for var in uses_j:
            last_uses.setdefault(var, [])
            if j not in last_uses[var]:
                last_uses[var].append(j)

    return nodes


# ---------------------------------------------------------------------------

def _compute_priorities(nodes: List[DepNode]) -> None:
    """Compute critical-path priority for each node.

    priority[i] = 1 + max(priority[succ] for succ in succs[i])
    """
    n = len(nodes)
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

def _list_schedule(nodes: List[DepNode]) -> List[IRInstruction]:
    """Run list scheduling: pick highest-priority ready node at each step."""
    pending = [node.preds_count for node in nodes]
    ready = [i for i, p in enumerate(pending) if p == 0]
    scheduled: List[IRInstruction] = []
    scheduled_set: Set[int] = set()

    while ready:
        best = max(ready, key=lambda i: (nodes[i].priority, nodes[i].idx))
        ready.remove(best)
        scheduled.append(nodes[best].instr)
        scheduled_set.add(best)
        for s in nodes[best].succs:
            pending[s] -= 1
            if pending[s] == 0:
                ready.append(s)

    return scheduled


# ---------------------------------------------------------------------------

def schedule_block(block) -> int:
    """Reorder one BasicBlock with list scheduling; return instructions moved.

    Fixed constraints:
      - Initial label (if any) stays at position 0.
      - Terminators stay at the end.
      - Everything in between is schedulable.
    """
    instrs = block.instructions
    if len(instrs) <= 1:
        return 0

    prefix: List[IRInstruction] = []
    suffix: List[IRInstruction] = []
    body:   List[IRInstruction] = []

    i = 0
    if instrs and _is_label(instrs[0]):
        prefix.append(instrs[0])
        i = 1

    j = len(instrs) - 1
    while j >= i and _is_terminator(instrs[j]):
        suffix.insert(0, instrs[j])
        j -= 1

    body = list(instrs[i:j+1])

    if len(body) <= 1:
        return 0

    original_strs = [str(x) for x in body]

    nodes = _build_dag(body)
    _compute_priorities(nodes)
    new_body = _list_schedule(nodes)

    moves = sum(1 for a, b in zip(original_strs, [str(x) for x in new_body]) if a != b)

    block.instructions = prefix + new_body + suffix
    return moves


# ---------------------------------------------------------------------------

@dataclass
class SchedulerStats:
    """Metrics for the instruction scheduling pass."""
    blocks_scheduled: int = 0
    instrs_moved:     int = 0
    blocks_changed:   int = 0


# ---------------------------------------------------------------------------

def schedule_function(ir_func: IRFunction) -> SchedulerStats:
    """Apply list scheduling to all basic blocks of a function."""
    stats = SchedulerStats()
    cfg = CFG.build_from_function(ir_func)

    for block in cfg.blocks:
        stats.blocks_scheduled += 1
        moved = schedule_block(block)
        stats.instrs_moved += moved
        if moved > 0:
            stats.blocks_changed += 1

    ir_func.body = [
        instr
        for block in cfg.blocks
        for instr in block.instructions
    ]
    return stats


def schedule_program(ir_program: IRProgram) -> SchedulerStats:
    """Apply instruction scheduling to all functions in the program."""
    total = SchedulerStats()
    for func in ir_program.functions:
        s = schedule_function(func)
        total.blocks_scheduled += s.blocks_scheduled
        total.instrs_moved     += s.instrs_moved
        total.blocks_changed   += s.blocks_changed
    return total
