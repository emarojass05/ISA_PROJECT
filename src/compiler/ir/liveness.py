"""
liveness.py - Analisis de vida de variables (Liveness Analysis).

Que hace
--------
Para cada punto del programa determina que variables estan "vivas":
una variable esta viva si su valor actual sera leido en algun momento futuro.

Este analisis es el prerequisito para Dead Code Elimination (DCE):
una instruccion "dest = ..." es codigo muerto si dest NO esta viva
inmediatamente despues de esa instruccion.

Algoritmo
---------
Analisis de flujo de datos hacia atras (backward dataflow).

Para cada bloque B se precomputan:
    use[B]  = variables leidas en B antes de su primera escritura en B
    def[B]  = variables escritas en B antes de su primera lectura en B

Luego se itera hasta punto fijo:
    live_out[B] = union( live_in[S]  para todo sucesor S de B )
    live_in[B]  = use[B]  u  (live_out[B] - def[B])

Complejidad: O(bloques * iteraciones). En la practica converge en 2-3 pasadas.

Liveness intra-bloque
---------------------
Con live_out[B] conocido, un pase hacia atras instruccion a instruccion
produce live_before[i] y live_after[i] para cada instruccion i.
DCE usa live_after[i]: si dest de i no esta en live_after[i], la instruccion
es codigo muerto.

Interfaz publica
----------------
    BlockLiveness       use/def/live_in/live_out de un bloque
    InstrLiveness       live_before/live_after de una instruccion
    LivenessResult      resultado completo del analisis sobre un CFG
    analyze_liveness(cfg)            aplica el analisis a un CFG
    instr_liveness(block, live_out)  liveness intra-bloque de un bloque
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Set, Tuple

from .basic_block import BasicBlock
from .cfg import CFG
from .ir_types import IRInstruction


# ---------------------------------------------------------------------------
# Tipos de resultado
# ---------------------------------------------------------------------------

@dataclass
class BlockLiveness:
    """
    Conjuntos de liveness para un BasicBlock.

    Atributos:
        use       Variables usadas antes de ser definidas en el bloque.
        defs      Variables definidas antes de ser usadas en el bloque.
                  (Llamado 'defs' para no colisionar con el builtin 'def'.)
        live_in   Variables vivas a la ENTRADA del bloque.
        live_out  Variables vivas a la SALIDA del bloque.
    """
    use:      Set[str] = field(default_factory=set)
    defs:     Set[str] = field(default_factory=set)
    live_in:  Set[str] = field(default_factory=set)
    live_out: Set[str] = field(default_factory=set)


@dataclass
class InstrLiveness:
    """
    Conjuntos de liveness para una instruccion individual.

    Atributos:
        live_before  Variables vivas ANTES de ejecutar la instruccion.
        live_after   Variables vivas DESPUES de ejecutar la instruccion.
                     DCE comprueba: si dest not in live_after -> codigo muerto.
    """
    live_before: Set[str] = field(default_factory=set)
    live_after:  Set[str] = field(default_factory=set)


@dataclass
class LivenessResult:
    """
    Resultado completo del analisis de liveness sobre un CFG.

    Atributos:
        blocks   Mapa bloque -> BlockLiveness con los conjuntos convergidos.
        iters    Numero de iteraciones hasta punto fijo.
    """
    blocks: Dict[BasicBlock, BlockLiveness] = field(default_factory=dict)
    iters:  int = 0

    def live_in(self, block: BasicBlock) -> Set[str]:
        """Acceso rapido a live_in de un bloque."""
        return self.blocks[block].live_in

    def live_out(self, block: BasicBlock) -> Set[str]:
        """Acceso rapido a live_out de un bloque."""
        return self.blocks[block].live_out


# ---------------------------------------------------------------------------
# Paso 1: calcular use y def de cada bloque
# ---------------------------------------------------------------------------

def _compute_use_def(block: BasicBlock) -> Tuple[Set[str], Set[str]]:
    """
    Calcula los conjuntos use y def de un bloque en una sola pasada.

    Regla:
      - Una variable entra en 'use' si es leida ANTES de ser escrita en el bloque.
      - Una variable entra en 'def' si es escrita ANTES de ser leida en el bloque.

    Pasada hacia adelante instruccion a instruccion:
      Para cada instruccion:
        1. Para cada variable en uses(instr):
             si no esta en def_set -> va a use_set (la necesita del exterior)
        2. Para cada variable en defs(instr):
             si no esta en use_set -> va a def_set (la produce para el exterior)
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
# Paso 2: iteracion hasta punto fijo
# ---------------------------------------------------------------------------

def analyze_liveness(cfg: CFG) -> LivenessResult:
    """
    Aplica el analisis de liveness backward dataflow a un CFG completo.

    Algoritmo:
      1. Precomputar use/def para cada bloque.
      2. Inicializar live_in y live_out a conjuntos vacios.
      3. Iterar en orden inverso (de salidas hacia entradas) hasta punto fijo:
           live_out[B] = union( live_in[S] para todo sucesor S de B )
           live_in[B]  = use[B] u (live_out[B] - def[B])
      4. Repetir hasta que ningun conjunto cambie.

    Retorna LivenessResult con los conjuntos convergidos y el numero de iteraciones.
    """
    result = LivenessResult()

    # Paso 1: precomputar use/def
    for block in cfg.blocks:
        use, defs = _compute_use_def(block)
        result.blocks[block] = BlockLiveness(use=use, defs=defs)

    # Paso 2-4: iteracion hasta punto fijo
    # Orden de visita: bloques en orden inverso (heuristicamente mas rapido)
    visit_order = list(reversed(cfg.blocks))

    changed = True
    while changed:
        changed = False
        result.iters += 1

        for block in visit_order:
            bl = result.blocks[block]

            # live_out[B] = union de live_in de todos los sucesores
            new_live_out: Set[str] = set()
            for succ in block.successors:
                if succ in result.blocks:
                    new_live_out |= result.blocks[succ].live_in

            # live_in[B] = use[B] u (live_out[B] - def[B])
            new_live_in = bl.use | (new_live_out - bl.defs)

            # Detectar cambios
            if new_live_out != bl.live_out or new_live_in != bl.live_in:
                bl.live_out = new_live_out
                bl.live_in  = new_live_in
                changed = True

    return result


# ---------------------------------------------------------------------------
# Liveness intra-bloque (para uso de DCE)
# ---------------------------------------------------------------------------

def instr_liveness(block: BasicBlock,
                   live_out: Set[str]) -> List[InstrLiveness]:
    """
    Calcula live_before y live_after para cada instruccion del bloque.

    Precondicion: live_out es el conjunto live_out del bloque (ya convergido).

    Algoritmo: pase hacia atras sobre las instrucciones.
      - Empezar con live = live_out (lo que esta vivo al salir del bloque)
      - Para cada instruccion en orden inverso:
          live_after  = live (estado antes de procesar esta instruccion)
          live = live - defs(instr)    (la definicion mata las vars que define)
          live = live | uses(instr)    (los usos la resucitan)
          live_before = live

    Retorna una lista con un InstrLiveness por instruccion, en el mismo orden
    que block.instructions (no en reversa).
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
