"""
tools/ir_demo.py — Demo visual de la IR de tres direcciones.

Construye manualmente ejemplos de IR y muestra:
  - La IR en formato legible
  - La tabla de defs/uses por instrucción
  - Una demostración de rename()

Uso:
    python3 tools/ir_demo.py              # corre todos los ejemplos
    python3 tools/ir_demo.py while        # solo el ejemplo 'while'
    python3 tools/ir_demo.py if           # solo el ejemplo 'if'
    python3 tools/ir_demo.py factorial    # solo el ejemplo 'factorial'
    python3 tools/ir_demo.py rename       # demo de rename
    python3 tools/ir_demo.py custom       # escribe tu propio ejemplo aquí abajo
"""

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from src.compiler.ir.ir_types import *
from src.compiler.ir.ir_program import IRFunction, IRProgram


# ---------------------------------------------------------------------------
# Helpers de impresión
# ---------------------------------------------------------------------------

def print_ir(prog: IRProgram):
    print("\n┌─── IR GENERADA " + "─" * 45)
    for func in prog.functions:
        for line in str(func).splitlines():
            print("│  " + line)
    print("└" + "─" * 61)


def print_defs_uses(func: IRFunction):
    print(f"\n┌─── DEFS / USES  ({func.name}) " + "─" * 32)
    print(f"│  {'#':<4} {'Instrucción':<38} {'defs':<18} uses")
    print("│  " + "─" * 75)
    for i, instr in enumerate(func.body):
        d = str(instr.defs()) if instr.defs() else "∅"
        u = str(instr.uses()) if instr.uses() else "∅"
        print(f"│  {i:<4} {str(instr):<38} {d:<18} {u}")
    print("└" + "─" * 61)


def print_rename_demo(func: IRFunction, old: str, new: str):
    print(f"\n┌─── RENAME  '{old}'  →  '{new}' " + "─" * 32)
    import copy
    func2 = copy.deepcopy(func)
    for instr in func2.body:
        instr.rename(old, new)
    for line in str(func2).splitlines():
        print("│  " + line)
    print("└" + "─" * 61)


def separator(title: str):
    print(f"\n{'═' * 63}")
    print(f"  EJEMPLO: {title}")
    print(f"{'═' * 63}")


# ---------------------------------------------------------------------------
# Ejemplo 1 — while loop
# Equivale a:
#   fonc [int] suma([int] n) {
#       [int] i = 0;
#       [int] acc = 0;
#       alors (i < n) {
#           acc = acc + i;
#           i++;
#       }
#       ret acc;
#   }
# ---------------------------------------------------------------------------

def ejemplo_while():
    separator("while loop  —  suma de 0..n")
    prog = IRProgram()
    f = IRFunction(name="suma", params=["n"], return_type="int")

    f.emit(IRLabel("FUNC_suma"))
    f.emit(IRCopy("i",   "0"))
    f.emit(IRCopy("acc", "0"))

    f.emit(IRLabel("WHILE_START_0"))
    f.emit(IRBinOp("t0", "i", BinOp.LT, "n"))
    f.emit(IRIfFalse("t0", "WHILE_END_0"))

    f.emit(IRBinOp("t1", "acc", BinOp.ADD, "i"))
    f.emit(IRCopy("acc", "t1"))
    f.emit(IRBinOp("t2", "i",   BinOp.ADD, "1"))
    f.emit(IRCopy("i",   "t2"))

    f.emit(IRGoto("WHILE_START_0"))
    f.emit(IRLabel("WHILE_END_0"))
    f.emit(IRReturn("acc"))

    prog.add_function(f)
    print_ir(prog)
    print_defs_uses(f)


# ---------------------------------------------------------------------------
# Ejemplo 2 — if / else
# Equivale a:
#   fonc [int] max([int] a, [int] b) {
#       si (a > b) {
#           ret a;
#       } sinon {
#           ret b;
#       }
#   }
# ---------------------------------------------------------------------------

def ejemplo_if():
    separator("if / else  —  máximo de dos números")
    prog = IRProgram()
    f = IRFunction(name="max", params=["a", "b"], return_type="int")

    f.emit(IRLabel("FUNC_max"))
    f.emit(IRBinOp("t0", "a", BinOp.GT, "b"))
    f.emit(IRIfFalse("t0", "IF_ELSE_0"))

    f.emit(IRReturn("a"))

    f.emit(IRLabel("IF_ELSE_0"))
    f.emit(IRReturn("b"))

    prog.add_function(f)
    print_ir(prog)
    print_defs_uses(f)


# ---------------------------------------------------------------------------
# Ejemplo 3 — llamada recursiva
# Equivale a:
#   fonc [int] factorial([int] n) {
#       si (n <= 1) { ret 1; }
#       ret n * factorial(n - 1);
#   }
# ---------------------------------------------------------------------------

def ejemplo_factorial():
    separator("factorial  —  llamada recursiva")
    prog = IRProgram()
    f = IRFunction(name="factorial", params=["n"], return_type="int")

    f.emit(IRLabel("FUNC_factorial"))
    f.emit(IRBinOp("t0", "n", BinOp.LE, "1"))
    f.emit(IRIfFalse("t0", "FACT_ELSE_0"))
    f.emit(IRReturn("1"))

    f.emit(IRLabel("FACT_ELSE_0"))
    f.emit(IRBinOp("t1", "n", BinOp.SUB, "1"))
    f.emit(IRParam("t1"))
    f.emit(IRCall("t2", "factorial", 1))
    f.emit(IRBinOp("t3", "n", BinOp.MUL, "t2"))
    f.emit(IRReturn("t3"))

    prog.add_function(f)
    print_ir(prog)
    print_defs_uses(f)
    print_rename_demo(f, "t2", "t_rec")


# ---------------------------------------------------------------------------
# Ejemplo 4 — demo de rename
# Muestra cómo el renombramiento propaga un cambio por todas
# las instrucciones que usan o definen esa variable.
# ---------------------------------------------------------------------------

def ejemplo_rename():
    separator("rename  —  eliminar dependencia WAW")
    print("""
  Programa original con dependencia WAW en 't0':
    t0 = a + b      ← primera escritura a t0
    t0 = t0 * c     ← segunda escritura a t0 (WAW con la anterior)

  Después del renombramiento:
    t0  = a + b
    t0_ = t0 * c    ← t0 renombrado a t0_ para eliminar la dependencia
""")
    prog = IRProgram()
    f = IRFunction(name="demo_waw", params=["a", "b", "c"], return_type="int")

    f.emit(IRLabel("FUNC_demo_waw"))
    f.emit(IRBinOp("t0", "a",  BinOp.ADD, "b"))
    f.emit(IRBinOp("t0", "t0", BinOp.MUL, "c"))   # WAW: t0 escrito dos veces
    f.emit(IRReturn("t0"))

    prog.add_function(f)
    print("  ANTES:")
    print_ir(prog)
    print_defs_uses(f)
    print_rename_demo(f, "t0", "t0_")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

EJEMPLOS = {
    "while":     ejemplo_while,
    "if":        ejemplo_if,
    "factorial": ejemplo_factorial,
    "rename":    ejemplo_rename,
}

if __name__ == "__main__":
    arg = sys.argv[1].lower() if len(sys.argv) > 1 else "all"

    if arg == "all":
        for fn in EJEMPLOS.values():
            fn()
    elif arg in EJEMPLOS:
        EJEMPLOS[arg]()
    else:
        opciones = ", ".join(EJEMPLOS.keys())
        print(f"Ejemplo '{arg}' no existe. Opciones: {opciones}, all")
        sys.exit(1)
        opciones = ", ".join(EJEMPLOS.keys())
        print("Ejemplo '" + arg + "' no existe. Opciones: " + opciones + ", all")
        sys.exit(1)
