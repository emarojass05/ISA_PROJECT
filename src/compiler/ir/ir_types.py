from __future__ import annotations
from dataclasses import dataclass
from enum import Enum
from typing import Optional


# ---------------------------------------------------------------------------

class BinOp(Enum):
    """Binary operators supported by the GAEM ISA."""
    ADD = "+"
    SUB = "-"
    MUL = "*"
    DIV = "/"
    MOD = "%"
    AND = "&"
    OR  = "|"
    XOR = "^"
    SHL = "<<"
    SHR = ">>"
    # Comparisons (produce 0 or 1)
    EQ  = "=="
    NEQ = "!="
    GT  = ">"
    LT  = "<"
    GE  = ">="
    LE  = "<="


class UnOp(Enum):
    """Unary operators."""
    NEG = "-"   # arithmetic negation
    NOT = "!"   # logical negation


# ---------------------------------------------------------------------------

class IRInstruction:
    """Base class for all IR instructions."""

    def defs(self) -> set[str]:
        """Variables defined (written) by this instruction."""
        return set()

    def uses(self) -> set[str]:
        """Variables used (read) by this instruction."""
        return set()

    def rename(self, old: str, new: str) -> None:
        """Replace all occurrences of operand old with new."""
        pass

    def rename_uses(self, old: str, new: str) -> None:
        """Replace old with new only in use positions, never in the def."""
        pass

    def rename_def(self, old: str, new: str) -> None:
        """Replace old with new only in the definition position."""
        pass


# ---------------------------------------------------------------------------

@dataclass
class IRBinOp(IRInstruction):
    """Three-address binary operation: dest = left op right."""
    dest:  str
    left:  str
    op:    BinOp
    right: str

    def defs(self) -> set[str]:
        return {self.dest}

    def uses(self) -> set[str]:
        return {self.left, self.right}

    def rename(self, old: str, new: str) -> None:
        if self.dest  == old: self.dest  = new
        if self.left  == old: self.left  = new
        if self.right == old: self.right = new

    def rename_uses(self, old: str, new: str) -> None:
        if self.left  == old: self.left  = new
        if self.right == old: self.right = new

    def rename_def(self, old: str, new: str) -> None:
        if self.dest == old: self.dest = new

    def __str__(self) -> str:
        return f"{self.dest} = {self.left} {self.op.value} {self.right}"


@dataclass
class IRUnOp(IRInstruction):
    """Unary operation: dest = op operand."""
    dest:    str
    op:      UnOp
    operand: str

    def defs(self) -> set[str]:
        return {self.dest}

    def uses(self) -> set[str]:
        return {self.operand}

    def rename(self, old: str, new: str) -> None:
        if self.dest    == old: self.dest    = new
        if self.operand == old: self.operand = new

    def rename_uses(self, old: str, new: str) -> None:
        if self.operand == old: self.operand = new

    def rename_def(self, old: str, new: str) -> None:
        if self.dest == old: self.dest = new

    def __str__(self) -> str:
        return f"{self.dest} = {self.op.value}{self.operand}"


@dataclass
class IRCopy(IRInstruction):
    """Simple copy or literal load: dest = src."""
    dest: str
    src:  str

    def defs(self) -> set[str]:
        return {self.dest}

    def uses(self) -> set[str]:
        # Numeric literals are not variables
        return {self.src} if not _is_literal(self.src) else set()

    def rename(self, old: str, new: str) -> None:
        if self.dest == old: self.dest = new
        if self.src  == old: self.src  = new

    def rename_uses(self, old: str, new: str) -> None:
        if self.src == old: self.src = new

    def rename_def(self, old: str, new: str) -> None:
        if self.dest == old: self.dest = new

    def __str__(self) -> str:
        return f"{self.dest} = {self.src}"


@dataclass
class IRLoad(IRInstruction):
    """Memory load: dest = mem[base + offset]. Maps to 'lw' in GAEM."""
    dest:   str
    base:   str
    offset: int

    def defs(self) -> set[str]:
        return {self.dest}

    def uses(self) -> set[str]:
        return {self.base}

    def rename(self, old: str, new: str) -> None:
        if self.dest == old: self.dest = new
        if self.base == old: self.base = new

    def rename_uses(self, old: str, new: str) -> None:
        if self.base == old: self.base = new

    def rename_def(self, old: str, new: str) -> None:
        if self.dest == old: self.dest = new

    def __str__(self) -> str:
        return f"{self.dest} = mem[{self.base} + {self.offset}]"


@dataclass
class IRStore(IRInstruction):
    """Memory write: mem[base + offset] = src. Maps to 'sw' in GAEM.

    Has observable side effects; DCE must never remove it.
    """
    base:   str
    offset: int
    src:    str

    def defs(self) -> set[str]:
        return set()   # no variable defined

    def uses(self) -> set[str]:
        return {self.base, self.src}

    def rename(self, old: str, new: str) -> None:
        if self.base == old: self.base = new
        if self.src  == old: self.src  = new

    def rename_uses(self, old: str, new: str) -> None:
        if self.base == old: self.base = new
        if self.src  == old: self.src  = new

    def rename_def(self, old: str, new: str) -> None:
        pass  # IRStore has no destination

    def __str__(self) -> str:
        return f"mem[{self.base} + {self.offset}] = {self.src}"

    @property
    def has_side_effect(self) -> bool:
        return True


@dataclass
class IRLabel(IRInstruction):
    """Label definition (jump target): name:"""
    name: str

    def __str__(self) -> str:
        return f"{self.name}:"


@dataclass
class IRGoto(IRInstruction):
    """Unconditional jump: goto target. Maps to 'j label' in GAEM."""
    target: str

    def __str__(self) -> str:
        return f"goto {self.target}"


@dataclass
class IRIfTrue(IRInstruction):
    """Conditional jump if cond != 0: if cond goto target."""
    cond:   str
    target: str

    def uses(self) -> set[str]:
        return {self.cond}

    def rename(self, old: str, new: str) -> None:
        if self.cond == old: self.cond = new

    def rename_uses(self, old: str, new: str) -> None:
        if self.cond == old: self.cond = new

    def rename_def(self, old: str, new: str) -> None:
        pass

    def __str__(self) -> str:
        return f"if {self.cond} goto {self.target}"


@dataclass
class IRIfFalse(IRInstruction):
    """Conditional jump if cond == 0: iffalse cond goto target."""
    cond:   str
    target: str

    def uses(self) -> set[str]:
        return {self.cond}

    def rename(self, old: str, new: str) -> None:
        if self.cond == old: self.cond = new

    def rename_uses(self, old: str, new: str) -> None:
        if self.cond == old: self.cond = new

    def rename_def(self, old: str, new: str) -> None:
        pass

    def __str__(self) -> str:
        return f"iffalse {self.cond} goto {self.target}"


@dataclass
class IRParam(IRInstruction):
    """Push one argument before a function call: param value."""
    value: str

    def uses(self) -> set[str]:
        return {self.value} if not _is_literal(self.value) else set()

    def rename(self, old: str, new: str) -> None:
        if self.value == old: self.value = new

    def rename_uses(self, old: str, new: str) -> None:
        if self.value == old: self.value = new

    def rename_def(self, old: str, new: str) -> None:
        pass

    def __str__(self) -> str:
        return f"param {self.value}"


@dataclass
class IRCall(IRInstruction):
    """Function call. Args are the preceding IRParam instructions."""
    dest:      Optional[str]
    func:      str
    arg_count: int

    def defs(self) -> set[str]:
        return {self.dest} if self.dest else set()

    def uses(self) -> set[str]:
        # Actual arguments are carried by preceding IRParam instructions
        return set()

    def rename(self, old: str, new: str) -> None:
        if self.dest == old: self.dest = new

    def rename_uses(self, old: str, new: str) -> None:
        pass  # args live in IRParam, not here

    def rename_def(self, old: str, new: str) -> None:
        if self.dest == old: self.dest = new

    def __str__(self) -> str:
        if self.dest:
            return f"{self.dest} = call {self.func}, {self.arg_count}"
        return f"call {self.func}, {self.arg_count}"

    @property
    def has_side_effect(self) -> bool:
        return True


@dataclass
class IRReturn(IRInstruction):
    """Function return. Maps to 'jr ra' in GAEM."""
    value: Optional[str] = None

    def uses(self) -> set[str]:
        if self.value and not _is_literal(self.value):
            return {self.value}
        return set()

    def rename(self, old: str, new: str) -> None:
        if self.value == old: self.value = new

    def rename_uses(self, old: str, new: str) -> None:
        if self.value == old: self.value = new

    def rename_def(self, old: str, new: str) -> None:
        pass  # IRReturn defines no variable

    def __str__(self) -> str:
        return f"return {self.value}" if self.value else "return"


# ---------------------------------------------------------------------------

def _is_literal(operand: str) -> bool:
    """Return True if operand is a numeric literal, not a variable name."""
    try:
        int(operand, 0)
        return True
    except (ValueError, TypeError):
        return False
