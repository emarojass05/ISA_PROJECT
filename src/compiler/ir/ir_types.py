"""
ir_types.py — Instrucciones de representación intermedia (IR) de tres direcciones.

Cada instrucción de 3-direcciones tiene la forma:
    dest = operand1  op  operand2

Los operandos son strings: nombres de variables ("x"), temporales ("t0", "t1")
o literales enteros como string ("42", "0").

Cada clase expone dos métodos clave que las optimizaciones van a usar:
    defs() -> set[str]   variables que esta instrucción *define* (escribe)
    uses() -> set[str]   variables que esta instrucción *lee*

Esto es la base para:
    - Análisis de liveness (DCE)
    - Detección de dependencias RAW/WAR/WAW (reordenamiento)
    - Renombramiento de registros
"""

from __future__ import annotations
from dataclasses import dataclass
from enum import Enum
from typing import Optional


# ---------------------------------------------------------------------------
# Operadores
# ---------------------------------------------------------------------------

class BinOp(Enum):
    """Operadores binarios soportados por la ISA GAEM y el lenguaje FRC."""
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
    # Comparaciones (producen 0 o 1)
    EQ  = "=="
    NEQ = "!="
    GT  = ">"
    LT  = "<"
    GE  = ">="
    LE  = "<="


class UnOp(Enum):
    """Operadores unarios."""
    NEG = "-"   # negación aritmética
    NOT = "!"   # negación lógica


# ---------------------------------------------------------------------------
# Clase base
# ---------------------------------------------------------------------------

class IRInstruction:
    """
    Base de todas las instrucciones IR.

    Por defecto defs() y uses() retornan conjuntos vacíos.
    Cada subclase sobreescribe los que correspondan.
    """

    def defs(self) -> set[str]:
        """Conjunto de variables que esta instrucción define (escribe)."""
        return set()

    def uses(self) -> set[str]:
        """Conjunto de variables que esta instrucción usa (lee)."""
        return set()

    def rename(self, old: str, new: str) -> None:
        """
        Reemplaza todas las ocurrencias del operando 'old' por 'new'.
        Usado por el renombramiento de registros.
        Cada subclase sobreescribe este método.
        """
        pass


# ---------------------------------------------------------------------------
# Instrucciones concretas
# ---------------------------------------------------------------------------

@dataclass
class IRBinOp(IRInstruction):
    """
    Operación binaria de tres direcciones.
    Forma:  dest = left  op  right

    Ejemplo:  t1 = x + y
    """
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

    def __str__(self) -> str:
        return f"{self.dest} = {self.left} {self.op.value} {self.right}"


@dataclass
class IRUnOp(IRInstruction):
    """
    Operación unaria.
    Forma:  dest = op operand

    Ejemplo:  t1 = -x     t2 = !flag
    """
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

    def __str__(self) -> str:
        return f"{self.dest} = {self.op.value}{self.operand}"


@dataclass
class IRCopy(IRInstruction):
    """
    Copia simple entre operandos.
    Forma:  dest = src

    Ejemplo:  t1 = x
    También se usa para cargar literales:  t1 = 42
    """
    dest: str
    src:  str

    def defs(self) -> set[str]:
        return {self.dest}

    def uses(self) -> set[str]:
        # Los literales (solo dígitos o hex) no son variables → no se cuentan
        return {self.src} if not _is_literal(self.src) else set()

    def rename(self, old: str, new: str) -> None:
        if self.dest == old: self.dest = new
        if self.src  == old: self.src  = new

    def __str__(self) -> str:
        return f"{self.dest} = {self.src}"


@dataclass
class IRLoad(IRInstruction):
    """
    Carga desde memoria.
    Forma:  dest = mem[base + offset]

    Corresponde a la instrucción 'lw' de la ISA GAEM.
    Ejemplo:  t1 = mem[arr + 8]
    """
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

    def __str__(self) -> str:
        return f"{self.dest} = mem[{self.base} + {self.offset}]"


@dataclass
class IRStore(IRInstruction):
    """
    Escritura en memoria.
    Forma:  mem[base + offset] = src

    Corresponde a la instrucción 'sw' de la ISA GAEM.
    Ejemplo:  mem[arr + 8] = t1

    Nota: IRStore no *define* variables, pero sí *usa* base y src.
    Es un efecto de lado visible → el DCE no puede eliminarlo.
    """
    base:   str
    offset: int
    src:    str

    def defs(self) -> set[str]:
        return set()   # no define variables

    def uses(self) -> set[str]:
        return {self.base, self.src}

    def rename(self, old: str, new: str) -> None:
        if self.base == old: self.base = new
        if self.src  == old: self.src  = new

    def __str__(self) -> str:
        return f"mem[{self.base} + {self.offset}] = {self.src}"

    @property
    def has_side_effect(self) -> bool:
        return True


@dataclass
class IRLabel(IRInstruction):
    """
    Definición de etiqueta (punto de salto).
    Forma:  name:

    Ejemplo:  WHILE_START_0:
    """
    name: str

    def __str__(self) -> str:
        return f"{self.name}:"


@dataclass
class IRGoto(IRInstruction):
    """
    Salto incondicional.
    Forma:  goto target

    Corresponde a 'j label' en GAEM.
    """
    target: str

    def __str__(self) -> str:
        return f"goto {self.target}"


@dataclass
class IRIfTrue(IRInstruction):
    """
    Salto condicional: salta si la condición es verdadera (distinto de cero).
    Forma:  if cond goto target

    Corresponde a 'bne cond, zero, label' en GAEM.
    Ejemplo:  if t1 goto WHILE_END_0
    """
    cond:   str
    target: str

    def uses(self) -> set[str]:
        return {self.cond}

    def rename(self, old: str, new: str) -> None:
        if self.cond == old: self.cond = new

    def __str__(self) -> str:
        return f"if {self.cond} goto {self.target}"


@dataclass
class IRIfFalse(IRInstruction):
    """
    Salto condicional: salta si la condición es falsa (igual a cero).
    Forma:  iffalse cond goto target

    Corresponde a 'beq cond, zero, label' en GAEM.
    Ejemplo:  iffalse t1 goto IF_ELSE_0
    """
    cond:   str
    target: str

    def uses(self) -> set[str]:
        return {self.cond}

    def rename(self, old: str, new: str) -> None:
        if self.cond == old: self.cond = new

    def __str__(self) -> str:
        return f"iffalse {self.cond} goto {self.target}"


@dataclass
class IRParam(IRInstruction):
    """
    Empuja un argumento para la siguiente llamada a función.
    Forma:  param value

    Se emiten N instrucciones IRParam antes de un IRCall con N argumentos.
    Ejemplo:
        param x
        param y
        t0 = call suma, 2
    """
    value: str

    def uses(self) -> set[str]:
        return {self.value} if not _is_literal(self.value) else set()

    def rename(self, old: str, new: str) -> None:
        if self.value == old: self.value = new

    def __str__(self) -> str:
        return f"param {self.value}"


@dataclass
class IRCall(IRInstruction):
    """
    Llamada a función.
    Forma:  dest = call func, arg_count    (con valor de retorno)
            call func, arg_count           (sin valor de retorno / void)

    Los argumentos ya fueron emitidos como instrucciones IRParam previas.
    'arg_count' indica cuántos IRParam preceden a este IRCall.

    Corresponde a 'jal ra, FUNC_xxx' en GAEM.
    """
    dest:      Optional[str]
    func:      str
    arg_count: int

    def defs(self) -> set[str]:
        return {self.dest} if self.dest else set()

    def uses(self) -> set[str]:
        # Los argumentos reales están en los IRParam anteriores
        return set()

    def rename(self, old: str, new: str) -> None:
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
    """
    Retorno de función.
    Forma:  return value    (con valor)
            return          (void)

    Corresponde a 'jr ra' en GAEM.
    """
    value: Optional[str] = None

    def uses(self) -> set[str]:
        if self.value and not _is_literal(self.value):
            return {self.value}
        return set()

    def rename(self, old: str, new: str) -> None:
        if self.value == old: self.value = new

    def __str__(self) -> str:
        return f"return {self.value}" if self.value else "return"


# ---------------------------------------------------------------------------
# Utilidades internas
# ---------------------------------------------------------------------------

def _is_literal(operand: str) -> bool:
    """
    Retorna True si el operando es un literal numérico (no una variable).
    Ejemplos: "42", "0", "0xFF" → True
              "t0", "x", "arr"  → False
    """
    try:
        int(operand, 0)
        return True
    except (ValueError, TypeError):
        return False
