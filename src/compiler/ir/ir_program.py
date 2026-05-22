"""
ir_program.py — Contenedores de la IR: IRFunction e IRProgram.

Estructura:
    IRProgram
        └── IRFunction (una por función del programa fuente)
                └── list[IRInstruction]  (instrucciones planas, en orden)

Las instrucciones son una lista plana (flat). La división en bloques básicos
y la construcción del CFG se hace en la siguiente tarea (ir-basic-blocks-cfg)
a partir de esta lista.
"""

from __future__ import annotations
from dataclasses import dataclass, field
from typing import List, Optional

from .ir_types import IRInstruction, IRLabel


@dataclass
class IRFunction:
    """
    Representa una función del programa en IR.

    Atributos:
        name        Nombre de la función (ej. "factorial")
        params      Lista de nombres de parámetros formales (ej. ["n", "acc"])
        body        Lista plana de instrucciones IR en orden de emisión
        return_type Tipo de retorno como string (ej. "int", "void") — informativo
    """
    name:        str
    params:      List[str]             = field(default_factory=list)
    body:        List[IRInstruction]   = field(default_factory=list)
    return_type: str                   = "void"

    def emit(self, instr: IRInstruction) -> None:
        """Agrega una instrucción al final del cuerpo de la función."""
        self.body.append(instr)

    def __str__(self) -> str:
        params_str = ", ".join(self.params)
        lines = [f"function [{self.return_type}] {self.name}({params_str}):"]
        for instr in self.body:
            # Las etiquetas van sin indentación; el resto con 4 espacios
            if isinstance(instr, IRLabel):
                lines.append(f"  {instr}")
            else:
                lines.append(f"      {instr}")
        return "\n".join(lines)


@dataclass
class IRProgram:
    """
    Representa el programa completo como una colección de funciones IR.

    Uso típico:
        program = IRProgram()
        func = IRFunction(name="main", params=[])
        func.emit(IRCopy("t0", "5"))
        func.emit(IRReturn("t0"))
        program.add_function(func)
        print(program)
    """
    functions: List[IRFunction] = field(default_factory=list)

    def add_function(self, func: IRFunction) -> None:
        """Registra una función en el programa."""
        self.functions.append(func)

    def get_function(self, name: str) -> Optional[IRFunction]:
        """Busca una función por nombre. Retorna None si no existe."""
        for func in self.functions:
            if func.name == name:
                return func
        return None

    def __str__(self) -> str:
        return "\n\n".join(str(f) for f in self.functions)
