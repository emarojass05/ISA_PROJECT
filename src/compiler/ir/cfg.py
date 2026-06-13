from __future__ import annotations
from dataclasses import dataclass, field
from typing import Dict, List, Optional

from .ir_program import IRFunction
from .ir_types import (
    IRInstruction, IRLabel, IRGoto,
    IRIfTrue, IRIfFalse, IRReturn,
)
from .basic_block import BasicBlock


# ---------------------------------------------------------------------------

def _is_jump(instr: IRInstruction) -> bool:
    """True if the instruction transfers control (jump or return)."""
    return isinstance(instr, (IRGoto, IRIfTrue, IRIfFalse, IRReturn))


def _jump_targets(instr: IRInstruction) -> List[str]:
    """Return the target labels of a jump (empty list if not a jump)."""
    if isinstance(instr, (IRGoto, IRIfTrue, IRIfFalse)):
        return [instr.target]
    return []


# ---------------------------------------------------------------------------

@dataclass
class CFG:
    """Control flow graph of an IR function."""
    func_name: str
    blocks:    List[BasicBlock] = field(default_factory=list)

    # ------------------------------------------------------------------

    @property
    def entry(self) -> Optional[BasicBlock]:
        """Entry block (first). None if the CFG is empty."""
        return self.blocks[0] if self.blocks else None

    # ------------------------------------------------------------------

    @classmethod
    def build_from_function(cls, ir_func: IRFunction) -> "CFG":
        """Build CFG from an IRFunction using the Dragon Book algorithm."""
        instructions: List[IRInstruction] = ir_func.body
        cfg = cls(func_name=ir_func.name)

        if not instructions:
            return cfg

        # Step 1: collect jump target labels
        jump_target_labels: set[str] = set()
        for instr in instructions:
            for lbl in _jump_targets(instr):
                jump_target_labels.add(lbl)

        # Step 1: identify leader indices
        leaders: set[int] = {0}   # first instruction is always a leader

        for i, instr in enumerate(instructions):
            # Instruction following any jump/return is a leader
            if _is_jump(instr) and i + 1 < len(instructions):
                leaders.add(i + 1)
            # IRLabel targets of jumps are leaders
            if isinstance(instr, IRLabel) and instr.name in jump_target_labels:
                leaders.add(i)

        sorted_leaders = sorted(leaders)

        # Step 2: create basic blocks
        for block_id, leader_idx in enumerate(sorted_leaders):
            # Block ends just before the next leader
            if block_id + 1 < len(sorted_leaders):
                end_idx = sorted_leaders[block_id + 1]
            else:
                end_idx = len(instructions)

            block = BasicBlock(id=block_id)
            for instr in instructions[leader_idx:end_idx]:
                block.append(instr)
            cfg.blocks.append(block)

        # Step 3a: build label -> block map
        label_to_block: Dict[str, BasicBlock] = {}
        for block in cfg.blocks:
            for instr in block.instructions:
                if isinstance(instr, IRLabel):
                    label_to_block[instr.name] = block

        # Step 3b: add edges
        for i, block in enumerate(cfg.blocks):
            if block.is_empty():
                continue

            last = block.last()
            next_block = cfg.blocks[i + 1] if i + 1 < len(cfg.blocks) else None

            if isinstance(last, IRReturn):
                pass  # no successor

            elif isinstance(last, IRGoto):
                target = label_to_block.get(last.target)
                if target is not None:
                    cfg._add_edge(block, target)

            elif isinstance(last, (IRIfTrue, IRIfFalse)):
                # Edge to the conditional jump target
                target = label_to_block.get(last.target)
                if target is not None:
                    cfg._add_edge(block, target)
                # Fall-through edge to the next block
                if next_block is not None:
                    cfg._add_edge(block, next_block)

            else:
                # Fall through to the next block
                if next_block is not None:
                    cfg._add_edge(block, next_block)

        return cfg

    # ------------------------------------------------------------------

    def _add_edge(self, src: BasicBlock, dst: BasicBlock) -> None:
        """Add directed edge src -> dst (no duplicates)."""
        if dst not in src.successors:
            src.successors.append(dst)
        if src not in dst.predecessors:
            dst.predecessors.append(src)

    # ------------------------------------------------------------------

    def get_block_by_label(self, label_name: str) -> Optional[BasicBlock]:
        """Find the block whose first instruction is IRLabel(label_name)."""
        for block in self.blocks:
            if block.label() == label_name:
                return block
        return None

    # ------------------------------------------------------------------

    def __str__(self) -> str:
        lines = [
            f"CFG [{self.func_name}]  ({len(self.blocks)} blocks)",
            "=" * 52,
        ]
        for block in self.blocks:
            lines.append(str(block))
            lines.append("")
        return "\n".join(lines)

    def dot(self) -> str:
        """Generate a Graphviz DOT representation of the CFG."""
        lines = [f'digraph "{self.func_name}" {{']
        lines.append('  node [shape=box fontname="Courier" fontsize=9];')
        for block in self.blocks:
            body_lines: List[str] = []
            for instr in block.instructions:
                s = (
                    str(instr)
                    .replace("&", "&amp;")
                    .replace('"', '\\"')
                    .replace("<", "\\<")
                    .replace(">", "\\>")
                )
                body_lines.append(s)
            body = "\\n".join(body_lines) or "(empty)"
            node_label = f"{block.label()}\\n{body}"
            lines.append(f'  B{block.id} [label="{node_label}"];')
        for block in self.blocks:
            for succ in block.successors:
                lines.append(f"  B{block.id} -> B{succ.id};")
        lines.append("}")
        return "\n".join(lines)
