"""
tools/ir_demo.py - Visual demo of three-address IR.

Manually builds IR examples and shows:
  - The IR in readable format
  - The defs/uses table per instruction
  - A rename() demonstration

Usage:
    python3 tools/ir_demo.py              # run all examples
    python3 tools/ir_demo.py while        # only the 'while' example
    python3 tools/ir_demo.py if           # only the 'if' example
    python3 tools/ir_demo.py factorial    # only the 'factorial' example
    python3 tools/ir_demo.py rename       # rename demo
    python3 tools/ir_demo.py custom       # write your own example below
"""

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from src.compiler.ir.ir_types import *
from src.compiler.ir.ir_program import IRFunction, IRProgram


# ---------------------------------------------------------------------------
# Print helpers
# ---------------------------------------------------------------------------

def print_ir(prog: IRProgram):
    print("\n+--- IR GENERATED " + "-" * 45)
    for func in prog.functions:
        for line in str(func).splitlines():
            print("|  " + line)
    print("+" + "-" * 61)


def print_defs_uses(func: IRFunction):
    print(f"\n+--- DEFS / USES  ({func.name}) " + "-" * 32)
    print(f"|  {'#':<4} {'Instruction':<38} {'defs':<18} uses")
    print("|  " + "-" * 75)
    for i, instr in enumerate(func.body):
        d = str(instr.defs()) if instr.defs() else "{}"
        u = str(instr.uses()) if instr.uses() else "{}"
        print(f"|  {i:<4} {str(instr):<38} {d:<18} {u}")
    print("+" + "-" * 61)


def print_rename_demo(func: IRFunction, old: str, new: str):
    print(f"\n+--- RENAME  '{old}'  ->  '{new}' " + "-" * 32)
    import copy
    func2 = copy.deepcopy(func)
    for instr in func2.body:
        instr.rename(old, new)
    for line in str(func2).splitlines():
        print("|  " + line)
    print("+" + "-" * 61)


def separator(title: str):
    print(f"\n{'=' * 63}")
    print(f"  EXAMPLE: {title}")
    print(f"{'=' * 63}")


# ---------------------------------------------------------------------------
# Example 1 - while loop
# Equivalent to:
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

def example_while():
    separator("while loop  -  sum of 0..n")
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
# Example 2 - if / else
# Equivalent to:
#   fonc [int] max([int] a, [int] b) {
#       si (a > b) {
#           ret a;
#       } sinon {
#           ret b;
#       }
#   }
# ---------------------------------------------------------------------------

def example_if():
    separator("if / else  -  maximum of two numbers")
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
# Example 3 - recursive call
# Equivalent to:
#   fonc [int] factorial([int] n) {
#       si (n <= 1) { ret 1; }
#       ret n * factorial(n - 1);
#   }
# ---------------------------------------------------------------------------

def example_factorial():
    separator("factorial  -  recursive call")
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
# Example 4 - rename demo
# Shows how renaming propagates a change through all instructions that
# use or define that variable.
# ---------------------------------------------------------------------------

def example_rename():
    separator("rename  -  eliminate WAW dependency")
    print("""
  Original program with WAW dependency on 't0':
    t0 = a + b      <- first write to t0
    t0 = t0 * c     <- second write to t0 (WAW with the previous)

  After renaming:
    t0  = a + b
    t0_ = t0 * c    <- t0 renamed to t0_ to eliminate the dependency
""")
    prog = IRProgram()
    f = IRFunction(name="demo_waw", params=["a", "b", "c"], return_type="int")

    f.emit(IRLabel("FUNC_demo_waw"))
    f.emit(IRBinOp("t0", "a",  BinOp.ADD, "b"))
    f.emit(IRBinOp("t0", "t0", BinOp.MUL, "c"))   # WAW: t0 written twice
    f.emit(IRReturn("t0"))

    prog.add_function(f)
    print("  BEFORE:")
    print_ir(prog)
    print_defs_uses(f)
    print_rename_demo(f, "t0", "t0_")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

EXAMPLES = {
    "while":     example_while,
    "if":        example_if,
    "factorial": example_factorial,
    "rename":    example_rename,
}

if __name__ == "__main__":
    arg = sys.argv[1].lower() if len(sys.argv) > 1 else "all"

    if arg == "all":
        for fn in EXAMPLES.values():
            fn()
    elif arg in EXAMPLES:
        EXAMPLES[arg]()
    else:
        options = ", ".join(EXAMPLES.keys())
        print(f"Example '{arg}' not found. Options: {options}, all")
        sys.exit(1)
        options = ", ".join(EXAMPLES.keys())
        print("Example '" + arg + "' not found. Options: " + options + ", all")
        sys.exit(1)
