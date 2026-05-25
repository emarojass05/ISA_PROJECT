"""
renamer.py - Renombramiento estatico de registros para eliminar
dependencias falsas WAR y WAW dentro de bloques basicos.

Problema que resuelve
---------------------
El IRGenerator reutiliza el nombre original de las variables del programa
fuente (x, total, i, ...). Cuando una variable se escribe mas de una vez
en el mismo bloque basico, el reordenador de instrucciones no puede mover
libremente esas escrituras porque teme corromper el valor. Sin embargo,
muchas de esas dependencias son FALSAS: no hay un flujo de datos real
entre las dos escrituras, solo comparten nombre.

    WAW (Write After Write):  a = 1 ; a = 2  -> la segunda "a" es distinta
    WAR (Write After Read):   b = a + 1 ; a = 5  -> la "a" escrita es distinta

Solucion
--------
Asignar un nombre fresco a cada definicion adicional dentro del bloque y
propagar ese nombre nuevo a todos los usos posteriores en el mismo bloque.

    Antes:              Despues:
      a = 1               a = 1
      b = a + 1           b = a + 1
      a = 5               _rn0_a = 5        <- WAR eliminado
      c = a + 2           c = _rn0_a + 2    <- usa el nombre nuevo

Ahora el scheduler puede reubicar "_rn0_a = 5" sin riesgo porque es una
variable independiente de "a".

Alcance
-------
El renombramiento es INTRA-BLOQUE: solo opera dentro de cada BasicBlock.
No cruza aristas del CFG. Esto es suficiente para el reordenamiento local
que implementa el scheduler.

IMPORTANTE: solo se detecta WAR cuando la lectura previa de la variable
provino de una escritura DENTRO DEL MISMO BLOQUE. Las lecturas de variables
live-in (que vienen de bloques anteriores, incluyendo aristas de retorno en
loops) no generan WAR falso, para no romper la propagacion entre bloques.

Interfaz publica
----------------
    rename_program(ir_program)   aplica el pass a todas las funciones
    rename_function(ir_func)     aplica el pass a una funcion (modifica body)
    rename_cfg(cfg)              aplica el pass a un CFG ya construido
    rename_block(block, state)   aplica el pass a un BasicBlock individual
"""

from __future__ import annotations
from dataclasses import dataclass, field
from typing import Dict, Set

from .ir_types import IRInstruction
from .ir_program import IRFunction, IRProgram
from .basic_block import BasicBlock
from .cfg import CFG


# ---------------------------------------------------------------------------
# Estado del renamer (contador global de versiones)
# ---------------------------------------------------------------------------

@dataclass
class RenamerState:
    """
    Contador compartido entre bloques para garantizar nombres unicos
    en todo el programa.

    Atributos:
        counter      Numero de versiones generadas hasta ahora.
        renamed      Total de definiciones renombradas (para metricas).
    """
    counter:  int = 0
    renamed:  int = 0

    def fresh(self, original: str) -> str:
        """
        Genera un nombre fresco a partir del nombre original.
        Ejemplo: "a" -> "_rn0_a",  "_t3" -> "_rn1_t3"
        """
        base = original.lstrip("_")   # quita underscores iniciales
        name = f"_rn{self.counter}_{base}"
        self.counter += 1
        self.renamed += 1
        return name


# ---------------------------------------------------------------------------
# Logica principal: renombramiento de un bloque basico
# ---------------------------------------------------------------------------

def rename_block(block: BasicBlock, state: RenamerState) -> None:
    """
    Aplica renombramiento WAR/WAW a todas las instrucciones de un bloque.

    Algoritmo (intra-bloque, una sola pasada):

      Para cada instruccion en orden:
        1. Capturar uses y defs ORIGINALES (antes de cualquier cambio).
        2. Renombrar los USES con el mapa actual (rename_map).
        3. Para cada variable en defs:
             - Si ya fue definida antes en este bloque (WAW)
               O si fue usada despues de una definicion en este bloque (WAR)
               -> dependencia falsa -> crear nombre fresco y renombrar dest.
             - Si no -> primera definicion, registrar en defined_here.
        4. Registrar usos de variables ya definidas en el bloque,
           para detectar WAR en instrucciones posteriores.

    IMPORTANTE (WAR correcto):
        Solo se agrega una variable al conjunto WAR si fue leida DESPUES
        de ser definida en el mismo bloque. Las lecturas de variables
        live-in (no definidas en el bloque) NO se cuentan como WAR.
        Esto evita renombrar actualizaciones de loop (e.g. i = i + 1)
        que rompen la propagacion entre bloques.

    Variables del estado local:
        rename_map      { var_original: var_actual }
        defined_here    vars con al menos una definicion en este bloque
        used_after_def  vars leidas DESPUES de ser definidas en el bloque
                        (se usan para detectar WAR futuro)
    """
    rename_map:    Dict[str, str] = {}
    defined_here:  Set[str]       = set()
    used_after_def: Set[str]      = set()

    for instr in block.instructions:
        # Capturar nombres originales ANTES de cualquier modificacion
        original_uses = frozenset(instr.uses())
        original_defs = frozenset(instr.defs())

        # Paso 1 - renombrar usos con el mapa actual
        for var in original_uses:
            if var in rename_map:
                instr.rename_uses(var, rename_map[var])

        # Paso 2 - manejar definiciones
        for var in original_defs:
            is_waw = var in defined_here      # ya fue escrita antes -> WAW
            is_war = var in used_after_def    # fue leida (post-def) antes -> WAR

            if is_waw or is_war:
                new_name = state.fresh(var)
                instr.rename_def(var, new_name)
                rename_map[var] = new_name
            else:
                defined_here.add(var)

        # Paso 3 - registrar usos para deteccion WAR futura.
        # Solo aplica si la variable ya fue definida en este bloque:
        # las lecturas de variables live-in no son dependencias falsas.
        for var in original_uses:
            if var in defined_here:
                used_after_def.add(var)


# ---------------------------------------------------------------------------
# Interfaces publicas
# ---------------------------------------------------------------------------

def rename_cfg(cfg: CFG, state: RenamerState | None = None) -> RenamerState:
    """
    Aplica renombramiento a todos los bloques de un CFG.

    El renombramiento es independiente por bloque: cada bloque tiene su
    propio mapa de nombres. Esto es correcto para renombramiento intra-bloque.

    Retorna el RenamerState con las metricas acumuladas.
    """
    if state is None:
        state = RenamerState()
    for block in cfg.blocks:
        rename_block(block, state)
    return state


def rename_function(ir_func: IRFunction,
                    state: RenamerState | None = None) -> RenamerState:
    """
    Construye el CFG de la funcion, aplica renombramiento bloque a bloque
    y re-aplana el resultado de vuelta al body de la IRFunction.

    Modifica ir_func.body in-place.
    """
    if state is None:
        state = RenamerState()

    cfg = CFG.build_from_function(ir_func)
    rename_cfg(cfg, state)

    # Re-aplanar: reconstruir body en orden de bloques
    ir_func.body = [
        instr
        for block in cfg.blocks
        for instr in block.instructions
    ]
    return state


def rename_program(ir_program: IRProgram) -> RenamerState:
    """
    Aplica renombramiento a todas las funciones del programa.
    El contador de versiones es global para garantizar unicidad.
    """
    state = RenamerState()
    for func in ir_program.functions:
        rename_function(func, state)
    return state
