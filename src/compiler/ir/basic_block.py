"""
basic_block.py - Bloque basico del CFG (Control Flow Graph).

Un bloque basico es una secuencia maximal de instrucciones con:
  - Un solo punto de entrada (la primera instruccion).
  - Un solo punto de salida (la ultima instruccion).

Ningun salto llega al interior del bloque, y ningun salto sale
del interior excepto desde la ultima instruccion.

Referencia: Dragon Book (Aho et al.) Sec. 8.4
"""

from __future__ import annotations
from dataclasses import dataclass, field
from typing import List, TYPE_CHECKING

from .ir_types import IRInstruction, IRLabel


@dataclass
class BasicBlock:
    """
    Nodo del CFG: contiene una lista plana de IRInstruction.

    Atributos:
        id           Identificador entero unico dentro del CFG (0-based).
        instructions Lista de IRInstruction en orden de ejecucion.
        predecessors Lista de bloques que tienen aristas que llegan a este bloque.
        successors   Lista de bloques a los que este bloque puede saltar/caer.
    """
    id:           int
    instructions: List[IRInstruction] = field(default_factory=list)
    predecessors: List["BasicBlock"]  = field(default_factory=list)
    successors:   List["BasicBlock"]  = field(default_factory=list)

    # ------------------------------------------------------------------
    # Mutacion
    # ------------------------------------------------------------------

    def append(self, instr: IRInstruction) -> None:
        """Agrega una instruccion al final del bloque."""
        self.instructions.append(instr)

    # ------------------------------------------------------------------
    # Consultas
    # ------------------------------------------------------------------

    def is_empty(self) -> bool:
        """Retorna True si el bloque no tiene instrucciones."""
        return len(self.instructions) == 0

    def first(self) -> IRInstruction | None:
        """Primera instruccion del bloque, o None si esta vacio."""
        return self.instructions[0] if self.instructions else None

    def last(self) -> IRInstruction | None:
        """Ultima instruccion del bloque, o None si esta vacio."""
        return self.instructions[-1] if self.instructions else None

    def label(self) -> str:
        """
        Nombre descriptivo del bloque para impresion y DOT.
        Si la primera instruccion es un IRLabel, usa su nombre.
        De lo contrario usa 'B<id>'.
        """
        if self.instructions and isinstance(self.instructions[0], IRLabel):
            return self.instructions[0].name
        return f"B{self.id}"

    # ------------------------------------------------------------------
    # Representacion
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
    # Soporte de sets / dicts (necesario porque usamos listas de bloques
    # y necesitamos comparar por identidad, no por contenido)
    # ------------------------------------------------------------------

    def __hash__(self) -> int:
        return id(self)

    def __eq__(self, other: object) -> bool:
        return self is other
