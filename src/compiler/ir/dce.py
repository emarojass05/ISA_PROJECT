"""
dce.py - Dead Code Elimination (DCE).

Que hace
--------
Elimina instrucciones cuyo resultado nunca es utilizado. Una instruccion
"dest = ..." es codigo muerto si 'dest' no esta viva inmediatamente despues
de esa instruccion (segun el analisis de liveness).

Prerequisito
------------
Requiere liveness.py para calcular live_after por instruccion.

Reglas de eliminacion
---------------------
Una instruccion se ELIMINA si y solo si cumple TODAS estas condiciones:
  1. Define exactamente una variable (defs() retorna un conjunto no vacio).
  2. Esa variable NO esta en live_after de la instruccion.
  3. La instruccion NO tiene efectos de lado observables.

Efectos de lado que impiden la eliminacion:
  - IRStore   escritura en memoria
  - IRCall    llamada a funcion (puede tener efectos externos)
  - IRReturn  retorno de funcion
  - IRLabel   etiqueta (punto de salto, estructural)
  - IRGoto    salto incondicional
  - IRIfTrue  salto condicional
  - IRIfFalse salto condicional

Iteracion hasta punto fijo
--------------------------
Eliminar una instruccion puede hacer que la variable que la alimentaba
quede tambien muerta. Por eso se itera:

  Ejemplo:
    _t0 = a + b    <- si _t1 se elimina, _t0 queda muerta tambien
    _t1 = _t0 * 2  <- muerta (nadie usa _t1)

  Primera pasada: elimina "_t1 = _t0 * 2"
  Segunda pasada: elimina "_t0 = a + b" (ahora _t0 tambien esta muerta)

Se itera hasta que no se elimine ninguna instruccion.

Interfaz publica
----------------
    DCEStats                metricas del pass
    eliminate_dead_code(ir_func)     aplica DCE a una IRFunction
    dce_program(ir_program)          aplica DCE a todo el programa
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Set

from .ir_types import (
    IRInstruction, IRStore, IRCall, IRReturn,
    IRLabel, IRGoto, IRIfTrue, IRIfFalse,
)
from .ir_program import IRFunction, IRProgram
from .cfg import CFG
from .liveness import analyze_liveness, instr_liveness


# ---------------------------------------------------------------------------
# Tipos de instruccion con efectos de lado (nunca se eliminan)
# ---------------------------------------------------------------------------

_SIDE_EFFECT_TYPES = (IRStore, IRCall, IRReturn, IRLabel, IRGoto, IRIfTrue, IRIfFalse)


def _has_side_effect(instr: IRInstruction) -> bool:
    """
    Retorna True si la instruccion tiene efectos de lado observables
    y por lo tanto nunca puede ser eliminada por DCE.
    """
    if isinstance(instr, _SIDE_EFFECT_TYPES):
        return True
    # Algunos IRCall tienen has_side_effect explicito
    if hasattr(instr, "has_side_effect") and instr.has_side_effect:
        return True
    return False


# ---------------------------------------------------------------------------
# Metricas
# ---------------------------------------------------------------------------

@dataclass
class DCEStats:
    """Metricas del pass de Dead Code Elimination."""
    instrs_before:   int = 0
    instrs_after:    int = 0
    instrs_removed:  int = 0
    iters:           int = 0

    @property
    def reduction_pct(self) -> float:
        """Porcentaje de instrucciones eliminadas."""
        if self.instrs_before == 0:
            return 0.0
        return 100.0 * self.instrs_removed / self.instrs_before


# ---------------------------------------------------------------------------
# Un pase de DCE sobre el body plano
# ---------------------------------------------------------------------------

def _dce_pass(ir_func: IRFunction) -> int:
    """
    Ejecuta un pase de DCE sobre el body de una funcion.

    Construye el CFG, corre liveness, y elimina instrucciones muertas
    bloque a bloque.

    Retorna el numero de instrucciones eliminadas en este pase.
    """
    cfg = CFG.build_from_function(ir_func)
    res = analyze_liveness(cfg)
    removed = 0

    for block in cfg.blocks:
        live_out_set = res.live_out(block)
        il_list = instr_liveness(block, live_out_set)

        kept = []
        for instr, il in zip(block.instructions, il_list):
            # Nunca eliminar instrucciones con efectos de lado
            if _has_side_effect(instr):
                kept.append(instr)
                continue

            defs = instr.defs()
            if not defs:
                # Instruccion sin definicion (raro pero posible) -> conservar
                kept.append(instr)
                continue

            # Eliminar si NINGUNA de las variables definidas esta viva despues
            if defs.isdisjoint(il.live_after):
                removed += 1
                # No se agrega a kept -> eliminada
            else:
                kept.append(instr)

        block.instructions = kept

    # Re-aplanar el body desde los bloques modificados
    ir_func.body = [
        instr
        for block in cfg.blocks
        for instr in block.instructions
    ]

    return removed


# ---------------------------------------------------------------------------
# Interfaz publica
# ---------------------------------------------------------------------------

def eliminate_dead_code(ir_func: IRFunction) -> DCEStats:
    """
    Aplica Dead Code Elimination iterativa a una IRFunction.

    Itera hasta punto fijo: cada pasada puede exponer nueva
    codigo muerto al eliminar instrucciones previas.

    Modifica ir_func.body in-place.
    Retorna DCEStats con las metricas del pass.
    """
    stats = DCEStats()
    stats.instrs_before = len(ir_func.body)

    changed = True
    while changed:
        stats.iters += 1
        n_removed = _dce_pass(ir_func)
        stats.instrs_removed += n_removed
        changed = (n_removed > 0)

    stats.instrs_after = len(ir_func.body)
    return stats


def dce_program(ir_program: IRProgram) -> DCEStats:
    """
    Aplica DCE a todas las funciones del programa.
    Retorna estadisticas acumuladas.
    """
    total = DCEStats()
    for func in ir_program.functions:
        s = eliminate_dead_code(func)
        total.instrs_before  += s.instrs_before
        total.instrs_after   += s.instrs_after
        total.instrs_removed += s.instrs_removed
        total.iters          += s.iters
    return total
