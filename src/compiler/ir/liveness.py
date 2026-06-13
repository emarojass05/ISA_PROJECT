from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Set, Tuple

from .basic_block import BasicBlock
from .cfg import CFG
from .ir_types import IRInstruction


# ---------------------------------------------------------------------------

@dataclass
class BlockLiveness:
    """Liveness sets for one BasicBlock."""
    use:      Set[str] = field(default_factory=set)
    defs:     Set[str] = field(default_factory=set)
    live_in:  Set[str] = field(default_factory=set)
    live_out: Set[str] = field(default_factory=set)


@dataclass
class InstrLiveness:
    """Liveness sets for one instruction."""
    live_before: Set[str] = field(default_factory=set)
    live_after:  Set[str] = field(default_factory=set)


@dataclass
class LivenessResult:
    """Full liveness analysis result for a CFG."""
    blocks: Dict[BasicBlock, BlockLiveness] = field(default_factory=dict)
    iters:  int = 0

    def live_in(self, block: BasicBlock) -> Set[str]:
        """Quick access to live_in of a block."""
        return self.blocks[block].live_in

    def live_out(self, block: BasicBlock) -> Set[str]:
        """Quick access to live_out of a block."""
        return self.blocks[block].live_out


# ---------------------------------------------------------------------------

def _compute_use_def(block: BasicBlock) -> Tuple[Set[str], Set[str]]:
    """Compute use and def sets for a block in one forward pass.

    use: variables read before being written in this block.
    def: variables written before being read in this block.
    """
    use_set: Set[str] = set()
    def_set: Set[str] = set()

    for instr in block.instructions:
        for var in instr.uses():
            if var not in def_set:
                use_set.add(var)
        for var in instr.defs():
            if var not in use_set:
                def_set.add(var)

    return use_set, def_set


# ---------------------------------------------------------------------------

def analyze_liveness(cfg: CFG) -> LivenessResult:
    """Run backward dataflow liveness analysis on a CFG to a fixed point."""
    result = LivenessResult()

    # Precompute use/def per block
    for block in cfg.blocks:
        use, defs = _compute_use_def(block)
        result.blocks[block] = BlockLiveness(use=use, defs=defs)

    # Iterate in reverse order (heuristically faster convergence)
    visit_order = list(reversed(cfg.blocks))

    changed = True
    while changed:
        changed = False
        result.iters += 1

        for block in visit_order:
            bl = result.blocks[block]

            # live_out[B] = union of live_in of all successors
            new_live_out: Set[str] = set()
            for succ in block.successors:
                if succ in result.blocks:
                    new_live_out |= result.blocks[succ].live_in

            # live_in[B] = use[B] u (live_out[B] - def[B])
            new_live_in = bl.use | (new_live_out - bl.defs)

            if new_live_out != bl.live_out or new_live_in != bl.live_in:
                bl.live_out = new_live_out
                bl.live_in  = new_live_in
                changed = True

    return result


# ---------------------------------------------------------------------------

def instr_liveness(block: BasicBlock,
                   live_out: Set[str]) -> List[InstrLiveness]:
    """Compute live_before and live_after for each instruction via backward pass.

    Precondition: live_out is the converged live_out set for the block.
    Returns a list of InstrLiveness in the same order as block.instructions.
    """
    n = len(block.instructions)
    result: List[InstrLiveness] = [InstrLiveness() for _ in range(n)]

    live: Set[str] = set(live_out)

    for i in range(n - 1, -1, -1):
        instr = block.instructions[i]
        result[i].live_after  = set(live)
        live -= instr.defs()
        live |= instr.uses()
        result[i].live_before = set(live)

    return result
