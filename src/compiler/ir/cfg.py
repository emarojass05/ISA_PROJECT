"""
cfg.py - Control Flow Graph (CFG) construido a partir de una IRFunction.

Algoritmo (Dragon Book, Sec. 8.4):

  PASO 1 - Identificar lideres:
    a) La primera instruccion de la funcion siempre es lider.
    b) Toda instruccion IRLabel que es el destino de algun salto
       (IRGoto / IRIfTrue / IRIfFalse) es lider.
    c) Toda instruccion que sigue inmediatamente a un salto o a un
       IRReturn es lider (si existe).

  PASO 2 - Partir en bloques:
    Cada lider inicia un bloque basico que se extiende hasta justo
    antes del siguiente lider (o hasta el final de la funcion).

  PASO 3 - Construir aristas:
    Se examina la ultima instruccion de cada bloque:
      - IRReturn      -> sin sucesor.
      - IRGoto t      -> arista al bloque cuyo lider tiene etiqueta t.
      - IRIfTrue  c t -> arista al bloque de etiqueta t
                         + arista fall-through al bloque siguiente.
      - IRIfFalse c t -> idem IRIfTrue.
      - cualquier otra-> fall-through al bloque siguiente.
"""

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
# Helpers internos
# ---------------------------------------------------------------------------

def _is_jump(instr: IRInstruction) -> bool:
    """True si la instruccion transfiere el control (salto o return)."""
    return isinstance(instr, (IRGoto, IRIfTrue, IRIfFalse, IRReturn))


def _jump_targets(instr: IRInstruction) -> List[str]:
    """Retorna las etiquetas destino de un salto (lista vacia si no es salto)."""
    if isinstance(instr, (IRGoto, IRIfTrue, IRIfFalse)):
        return [instr.target]
    return []


# ---------------------------------------------------------------------------
# Clase CFG
# ---------------------------------------------------------------------------

@dataclass
class CFG:
    """
    Grafo de flujo de control de una funcion IR.

    Atributos:
        func_name  Nombre de la funcion de origen.
        blocks     Lista de BasicBlock en orden de aparicion en el codigo.
                   blocks[0] es siempre el bloque de entrada (entry).
    """
    func_name: str
    blocks:    List[BasicBlock] = field(default_factory=list)

    # ------------------------------------------------------------------
    # Propiedades
    # ------------------------------------------------------------------

    @property
    def entry(self) -> Optional[BasicBlock]:
        """Bloque de entrada (primero). None si el CFG esta vacio."""
        return self.blocks[0] if self.blocks else None

    # ------------------------------------------------------------------
    # Constructor principal
    # ------------------------------------------------------------------

    @classmethod
    def build_from_function(cls, ir_func: IRFunction) -> "CFG":
        """
        Construye el CFG a partir de una IRFunction con la lista plana de
        instrucciones en ir_func.body.

        Retorna un CFG con los bloques y aristas correctamente enlazados.
        """
        instructions: List[IRInstruction] = ir_func.body
        cfg = cls(func_name=ir_func.name)

        if not instructions:
            return cfg

        # ---- Paso 1: recopilar destinos de todos los saltos ----
        jump_target_labels: set[str] = set()
        for instr in instructions:
            for lbl in _jump_targets(instr):
                jump_target_labels.add(lbl)

        # ---- Paso 1: identificar indices de instrucciones lideres ----
        leaders: set[int] = {0}   # la primera instruccion siempre es lider

        for i, instr in enumerate(instructions):
            # La instruccion siguiente a cualquier salto/return es lider
            if _is_jump(instr) and i + 1 < len(instructions):
                leaders.add(i + 1)
            # Las IRLabel que son destino de algun salto son lideres
            if isinstance(instr, IRLabel) and instr.name in jump_target_labels:
                leaders.add(i)

        sorted_leaders = sorted(leaders)

        # ---- Paso 2: crear bloques basicos ----
        for block_id, leader_idx in enumerate(sorted_leaders):
            # El bloque termina justo antes del siguiente lider
            if block_id + 1 < len(sorted_leaders):
                end_idx = sorted_leaders[block_id + 1]
            else:
                end_idx = len(instructions)

            block = BasicBlock(id=block_id)
            for instr in instructions[leader_idx:end_idx]:
                block.append(instr)
            cfg.blocks.append(block)

        # ---- Paso 3a: construir mapa label -> bloque ----
        label_to_block: Dict[str, BasicBlock] = {}
        for block in cfg.blocks:
            for instr in block.instructions:
                if isinstance(instr, IRLabel):
                    label_to_block[instr.name] = block

        # ---- Paso 3b: agregar aristas ----
        for i, block in enumerate(cfg.blocks):
            if block.is_empty():
                continue

            last = block.last()
            next_block = cfg.blocks[i + 1] if i + 1 < len(cfg.blocks) else None

            if isinstance(last, IRReturn):
                # Sin sucesor: fin del camino de ejecucion
                pass

            elif isinstance(last, IRGoto):
                target = label_to_block.get(last.target)
                if target is not None:
                    cfg._add_edge(block, target)

            elif isinstance(last, (IRIfTrue, IRIfFalse)):
                # Arista al destino del salto condicional
                target = label_to_block.get(last.target)
                if target is not None:
                    cfg._add_edge(block, target)
                # Arista fall-through al bloque siguiente
                if next_block is not None:
                    cfg._add_edge(block, next_block)

            else:
                # Cualquier otro caso: caida al siguiente bloque
                if next_block is not None:
                    cfg._add_edge(block, next_block)

        return cfg

    # ------------------------------------------------------------------
    # Operaciones internas
    # ------------------------------------------------------------------

    def _add_edge(self, src: BasicBlock, dst: BasicBlock) -> None:
        """Agrega la arista dirigida src -> dst (sin duplicados)."""
        if dst not in src.successors:
            src.successors.append(dst)
        if src not in dst.predecessors:
            dst.predecessors.append(src)

    # ------------------------------------------------------------------
    # Utilidades de consulta
    # ------------------------------------------------------------------

    def get_block_by_label(self, label_name: str) -> Optional[BasicBlock]:
        """Busca el bloque cuya primera instruccion es IRLabel(label_name)."""
        for block in self.blocks:
            if block.label() == label_name:
                return block
        return None

    # ------------------------------------------------------------------
    # Impresion
    # ------------------------------------------------------------------

    def __str__(self) -> str:
        lines = [
            f"CFG [{self.func_name}]  ({len(self.blocks)} bloques)",
            "=" * 52,
        ]
        for block in self.blocks:
            lines.append(str(block))
            lines.append("")
        return "\n".join(lines)

    def dot(self) -> str:
        """
        Genera representacion en formato DOT (Graphviz) del CFG.
        Para visualizar: echo '<salida>' | dot -Tpng -o cfg.png
        """
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
            body = "\\n".join(body_lines) or "(vacio)"
            node_label = f"{block.label()}\\n{body}"
            lines.append(f'  B{block.id} [label="{node_label}"];')
        for block in self.blocks:
            for succ in block.successors:
                lines.append(f"  B{block.id} -> B{succ.id};")
        lines.append("}")
        return "\n".join(lines)
