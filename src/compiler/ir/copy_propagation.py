from __future__ import annotations

from typing import Dict, List

from .ir_types import IRInstruction, IRCopy, _is_literal
from .ir_program import IRFunction, IRProgram
from .basic_block import BasicBlock
from .cfg import CFG


# ---------------------------------------------------------------------------

def propagate_copies_block(block: BasicBlock) -> int:
    """Intra-block forward copy propagation. Returns number of substitutions made."""
    copy_map: Dict[str, str] = {}
    subs = 0

    for instr in block.instructions:
        original_uses = list(instr.uses())
        original_defs = list(instr.defs())

        for var in original_uses:
            if var in copy_map:
                instr.rename_uses(var, copy_map[var])
                subs += 1

        for var in original_defs:
            copy_map.pop(var, None)
            stale = [k for k, v in copy_map.items() if v == var]
            for k in stale:
                del copy_map[k]

        if (isinstance(instr, IRCopy)
                and not _is_literal(instr.src)
                and not instr.src.startswith("@")):
            copy_map[instr.dest] = instr.src

    return subs


# ---------------------------------------------------------------------------

def propagate_copies_function(ir_func: IRFunction) -> int:
    """Apply copy propagation to all blocks of a function."""
    cfg = CFG.build_from_function(ir_func)
    total = sum(propagate_copies_block(block) for block in cfg.blocks)
    ir_func.body = [
        instr
        for block in cfg.blocks
        for instr in block.instructions
    ]
    return total


def propagate_copies_program(ir_program: IRProgram) -> int:
    """Apply copy propagation to all functions in the program."""
    return sum(propagate_copies_function(func) for func in ir_program.functions)
