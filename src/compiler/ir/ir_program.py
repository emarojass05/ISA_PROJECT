from __future__ import annotations
from dataclasses import dataclass, field
from typing import List, Optional

from .ir_types import IRInstruction, IRLabel


@dataclass
class IRFunction:
    """One function from the source program, stored as a flat instruction list."""
    name:        str
    params:      List[str]             = field(default_factory=list)
    body:        List[IRInstruction]   = field(default_factory=list)
    return_type: str                   = "void"

    def emit(self, instr: IRInstruction) -> None:
        """Append an instruction to the function body."""
        self.body.append(instr)

    def __str__(self) -> str:
        params_str = ", ".join(self.params)
        lines = [f"function [{self.return_type}] {self.name}({params_str}):"]
        for instr in self.body:
            # Labels at column 0; everything else indented
            if isinstance(instr, IRLabel):
                lines.append(f"  {instr}")
            else:
                lines.append(f"      {instr}")
        return "\n".join(lines)


@dataclass
class IRProgram:
    """Complete program as a collection of IR functions."""
    functions: List[IRFunction] = field(default_factory=list)

    def add_function(self, func: IRFunction) -> None:
        """Register a function in the program."""
        self.functions.append(func)

    def get_function(self, name: str) -> Optional[IRFunction]:
        """Find a function by name; returns None if not found."""
        for func in self.functions:
            if func.name == name:
                return func
        return None

    def __str__(self) -> str:
        return "\n\n".join(str(f) for f in self.functions)
