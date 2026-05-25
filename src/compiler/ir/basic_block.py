from __future__ import annotations
from dataclasses import dataclass, field
from typing import List, TYPE_CHECKING

from .ir_types import IRInstruction, IRLabel


@dataclass
class BasicBlock:
    """CFG node: holds a flat list of IRInstruction."""
    id:           int
    instructions: List[IRInstruction] = field(default_factory=list)
    predecessors: List["BasicBlock"]  = field(default_factory=list)
    successors:   List["BasicBlock"]  = field(default_factory=list)

    # ------------------------------------------------------------------

    def append(self, instr: IRInstruction) -> None:
        """Append an instruction to the end of the block."""
        self.instructions.append(instr)

    # ------------------------------------------------------------------

    def is_empty(self) -> bool:
        """Return True if the block has no instructions."""
        return len(self.instructions) == 0

    def first(self) -> IRInstruction | None:
        """First instruction of the block, or None if empty."""
        return self.instructions[0] if self.instructions else None

    def last(self) -> IRInstruction | None:
        """Last instruction of the block, or None if empty."""
        return self.instructions[-1] if self.instructions else None

    def label(self) -> str:
        """Block name for printing: IRLabel name if present, else 'B<id>'."""
        if self.instructions and isinstance(self.instructions[0], IRLabel):
            return self.instructions[0].name
        return f"B{self.id}"

    # ------------------------------------------------------------------

    def __str__(self) -> str:
        lines = [f"[Block {self.id}  label={self.label()}]"]
        for instr in self.instructions:
            if isinstance(instr, IRLabel):
                lines.append(f"  {instr}")
            else:
                lines.append(f"      {instr}")
        pred_ids = [f"B{p.id}" for p in self.predecessors]
        succ_ids = [f"B{s.id}" for s in self.successors]
        lines.append(f"  preds={pred_ids}  succs={succ_ids}")
        return "\n".join(lines)

    def __repr__(self) -> str:
        return f"BasicBlock(id={self.id}, label={self.label()!r})"

    # ------------------------------------------------------------------
    # Identity-based hashing (blocks stored in lists, compared by identity)
    # ------------------------------------------------------------------

    def __hash__(self) -> int:
        return id(self)

    def __eq__(self, other: object) -> bool:
        return self is other
