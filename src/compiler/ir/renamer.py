from __future__ import annotations
from dataclasses import dataclass, field
from typing import Dict, Set

from .ir_types import IRInstruction
from .ir_program import IRFunction, IRProgram
from .basic_block import BasicBlock
from .cfg import CFG


# ---------------------------------------------------------------------------

@dataclass
class RenamerState:
    """Shared counter that guarantees unique names across the whole program."""
    counter:  int = 0
    renamed:  int = 0

    def fresh(self, original: str) -> str:
        """Generate a fresh name from original, e.g. 'a' -> '_rn0_a'."""
        base = original.lstrip("_")   # strip leading underscores
        name = f"_rn{self.counter}_{base}"
        self.counter += 1
        self.renamed += 1
        return name


# ---------------------------------------------------------------------------

def rename_block(block: BasicBlock, state: RenamerState) -> None:
    """Apply intra-block WAR/WAW renaming to eliminate false dependencies.

    Single forward pass per block:
      1. Rename uses with the current rename_map.
      2. For each def: if WAW (already defined) or WAR (read after prior def),
         create a fresh name; otherwise record as first definition.
      3. Track post-definition reads for future WAR detection.

    Only reads that occur after a local definition count as WAR.
    Reads of live-in variables are not false dependencies.
    """
    rename_map:    Dict[str, str] = {}
    defined_here:  Set[str]       = set()
    used_after_def: Set[str]      = set()

    for instr in block.instructions:
        # Capture original names before any modification
        original_uses = frozenset(instr.uses())
        original_defs = frozenset(instr.defs())

        # Step 1: rename uses with current map
        for var in original_uses:
            if var in rename_map:
                instr.rename_uses(var, rename_map[var])

        # Step 2: handle definitions
        for var in original_defs:
            is_waw = var in defined_here      # written before -> WAW
            is_war = var in used_after_def    # read after prior def -> WAR

            if is_waw or is_war:
                new_name = state.fresh(var)
                instr.rename_def(var, new_name)
                rename_map[var] = new_name
            else:
                defined_here.add(var)

        # Step 3: track post-definition reads for WAR detection.
        # Only variables defined in this block count; live-in reads do not.
        for var in original_uses:
            if var in defined_here:
                used_after_def.add(var)


# ---------------------------------------------------------------------------

def rename_cfg(cfg: CFG, state: RenamerState | None = None) -> RenamerState:
    """Apply renaming to all blocks of a CFG independently."""
    if state is None:
        state = RenamerState()
    for block in cfg.blocks:
        rename_block(block, state)
    return state


def rename_function(ir_func: IRFunction,
                    state: RenamerState | None = None) -> RenamerState:
    """Build CFG, rename block by block, then flatten back to ir_func.body."""
    if state is None:
        state = RenamerState()

    cfg = CFG.build_from_function(ir_func)
    rename_cfg(cfg, state)

    # Re-flatten: rebuild body in block order
    ir_func.body = [
        instr
        for block in cfg.blocks
        for instr in block.instructions
    ]
    return state


def rename_program(ir_program: IRProgram) -> RenamerState:
    """Apply renaming to all functions; counter is global for uniqueness."""
    state = RenamerState()
    for func in ir_program.functions:
        rename_function(func, state)
    return state
