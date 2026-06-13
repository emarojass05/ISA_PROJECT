"""
tests/unit/test_ir_types.py

Unit tests for IR data structures.

What is verified:
  1. defs() and uses() for each instruction (foundation for DCE and dependency analysis)
  2. __str__ for each instruction (useful for debugging and IR dumps)
  3. rename() changes operands correctly (foundation for renaming)
  4. IRFunction and IRProgram group instructions and print correctly
  5. _is_literal does not confuse literals with variables

Run:
    python3 -m unittest tests/unit/test_ir_types.py -v
"""

import sys
import os
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

from src.compiler.ir.ir_types import (
    BinOp, UnOp,
    IRBinOp, IRUnOp, IRCopy,
    IRLoad, IRStore,
    IRLabel, IRGoto, IRIfTrue, IRIfFalse,
    IRParam, IRCall, IRReturn,
    _is_literal,
)
from src.compiler.ir.ir_program import IRFunction, IRProgram


# ---------------------------------------------------------------------------
# Arithmetic / logic instruction tests
# ---------------------------------------------------------------------------

class TestIRBinOp(unittest.TestCase):

    def setUp(self):
        self.instr = IRBinOp(dest="t1", left="x", op=BinOp.ADD, right="y")

    def test_defs(self):
        self.assertEqual(self.instr.defs(), {"t1"})

    def test_uses(self):
        self.assertEqual(self.instr.uses(), {"x", "y"})

    def test_str(self):
        self.assertEqual(str(self.instr), "t1 = x + y")

    def test_rename_dest(self):
        self.instr.rename("t1", "t99")
        self.assertEqual(self.instr.dest, "t99")

    def test_rename_left(self):
        self.instr.rename("x", "a")
        self.assertEqual(self.instr.left, "a")

    def test_rename_right(self):
        self.instr.rename("y", "b")
        self.assertEqual(self.instr.right, "b")

    def test_all_operators_have_string(self):
        """All BinOp values must be constructable and printable."""
        for op in BinOp:
            instr = IRBinOp("t0", "a", op, "b")
            self.assertIn(op.value, str(instr))


class TestIRUnOp(unittest.TestCase):

    def test_neg(self):
        instr = IRUnOp(dest="t0", op=UnOp.NEG, operand="x")
        self.assertEqual(instr.defs(), {"t0"})
        self.assertEqual(instr.uses(), {"x"})
        self.assertEqual(str(instr), "t0 = -x")

    def test_not(self):
        instr = IRUnOp(dest="t0", op=UnOp.NOT, operand="flag")
        self.assertEqual(str(instr), "t0 = !flag")

    def test_rename(self):
        instr = IRUnOp(dest="t0", op=UnOp.NEG, operand="x")
        instr.rename("x", "y")
        self.assertEqual(instr.operand, "y")


# ---------------------------------------------------------------------------
# Copy instruction tests
# ---------------------------------------------------------------------------

class TestIRCopy(unittest.TestCase):

    def test_variable_src(self):
        instr = IRCopy(dest="t0", src="x")
        self.assertEqual(instr.defs(), {"t0"})
        self.assertEqual(instr.uses(), {"x"})  # x is a variable
        self.assertEqual(str(instr), "t0 = x")

    def test_literal_src_not_in_uses(self):
        """Numeric literals are not variables -> they must not appear in uses()."""
        instr = IRCopy(dest="t0", src="42")
        self.assertEqual(instr.uses(), set())  # 42 is a literal

    def test_hex_literal_not_in_uses(self):
        instr = IRCopy(dest="t0", src="0xFF")
        self.assertEqual(instr.uses(), set())

    def test_rename(self):
        instr = IRCopy(dest="t0", src="x")
        instr.rename("x", "y")
        self.assertEqual(instr.src, "y")


# ---------------------------------------------------------------------------
# Memory instruction tests
# ---------------------------------------------------------------------------

class TestIRLoad(unittest.TestCase):

    def test_basic(self):
        instr = IRLoad(dest="t0", base="arr", offset=8)
        self.assertEqual(instr.defs(), {"t0"})
        self.assertEqual(instr.uses(), {"arr"})
        self.assertEqual(str(instr), "t0 = mem[arr + 8]")

    def test_rename_base(self):
        instr = IRLoad(dest="t0", base="arr", offset=0)
        instr.rename("arr", "ptr")
        self.assertEqual(instr.base, "ptr")


class TestIRStore(unittest.TestCase):

    def test_basic(self):
        instr = IRStore(base="arr", offset=8, src="t1")
        self.assertEqual(instr.defs(), set())       # store does not define variables
        self.assertEqual(instr.uses(), {"arr", "t1"})
        self.assertEqual(str(instr), "mem[arr + 8] = t1")

    def test_has_side_effect(self):
        """IRStore always has a side effect -> DCE must not eliminate it."""
        instr = IRStore(base="arr", offset=0, src="t1")
        self.assertTrue(instr.has_side_effect)

    def test_rename(self):
        instr = IRStore(base="arr", offset=0, src="t1")
        instr.rename("t1", "t99")
        self.assertEqual(instr.src, "t99")


# ---------------------------------------------------------------------------
# Control flow instruction tests
# ---------------------------------------------------------------------------

class TestIRLabel(unittest.TestCase):

    def test_str(self):
        instr = IRLabel("WHILE_START_0")
        self.assertEqual(str(instr), "WHILE_START_0:")

    def test_defs_uses_empty(self):
        instr = IRLabel("L")
        self.assertEqual(instr.defs(), set())
        self.assertEqual(instr.uses(), set())


class TestIRGoto(unittest.TestCase):

    def test_str(self):
        instr = IRGoto("WHILE_START_0")
        self.assertEqual(str(instr), "goto WHILE_START_0")

    def test_defs_uses_empty(self):
        instr = IRGoto("L")
        self.assertEqual(instr.defs(), set())
        self.assertEqual(instr.uses(), set())


class TestIRIfTrue(unittest.TestCase):

    def test_str(self):
        instr = IRIfTrue(cond="t0", target="LOOP_END")
        self.assertEqual(str(instr), "if t0 goto LOOP_END")

    def test_uses_cond(self):
        instr = IRIfTrue(cond="t0", target="L")
        self.assertEqual(instr.uses(), {"t0"})

    def test_rename_cond(self):
        instr = IRIfTrue(cond="t0", target="L")
        instr.rename("t0", "t99")
        self.assertEqual(instr.cond, "t99")


class TestIRIfFalse(unittest.TestCase):

    def test_str(self):
        instr = IRIfFalse(cond="t1", target="IF_ELSE_0")
        self.assertEqual(str(instr), "iffalse t1 goto IF_ELSE_0")

    def test_uses_cond(self):
        instr = IRIfFalse(cond="t1", target="L")
        self.assertEqual(instr.uses(), {"t1"})


# ---------------------------------------------------------------------------
# Function call instruction tests
# ---------------------------------------------------------------------------

class TestIRParam(unittest.TestCase):

    def test_variable(self):
        instr = IRParam("x")
        self.assertEqual(instr.uses(), {"x"})
        self.assertEqual(str(instr), "param x")

    def test_literal_not_in_uses(self):
        instr = IRParam("5")
        self.assertEqual(instr.uses(), set())

    def test_rename(self):
        instr = IRParam("x")
        instr.rename("x", "y")
        self.assertEqual(instr.value, "y")


class TestIRCall(unittest.TestCase):

    def test_with_return_value(self):
        instr = IRCall(dest="t0", func="factorial", arg_count=1)
        self.assertEqual(instr.defs(), {"t0"})
        self.assertEqual(instr.uses(), set())
        self.assertEqual(str(instr), "t0 = call factorial, 1")

    def test_void_call(self):
        instr = IRCall(dest=None, func="print", arg_count=1)
        self.assertEqual(instr.defs(), set())
        self.assertEqual(str(instr), "call print, 1")

    def test_has_side_effect(self):
        instr = IRCall(dest=None, func="f", arg_count=0)
        self.assertTrue(instr.has_side_effect)

    def test_rename_dest(self):
        instr = IRCall(dest="t0", func="f", arg_count=0)
        instr.rename("t0", "t99")
        self.assertEqual(instr.dest, "t99")


class TestIRReturn(unittest.TestCase):

    def test_with_value(self):
        instr = IRReturn("t0")
        self.assertEqual(instr.uses(), {"t0"})
        self.assertEqual(str(instr), "return t0")

    def test_void(self):
        instr = IRReturn()
        self.assertEqual(instr.uses(), set())
        self.assertEqual(str(instr), "return")

    def test_literal_return_not_in_uses(self):
        instr = IRReturn("0")
        self.assertEqual(instr.uses(), set())

    def test_rename(self):
        instr = IRReturn("t0")
        instr.rename("t0", "t99")
        self.assertEqual(instr.value, "t99")


# ---------------------------------------------------------------------------
# _is_literal tests
# ---------------------------------------------------------------------------

class TestIsLiteral(unittest.TestCase):

    def test_decimal(self):
        self.assertTrue(_is_literal("0"))
        self.assertTrue(_is_literal("42"))
        self.assertTrue(_is_literal("1000"))

    def test_hex(self):
        self.assertTrue(_is_literal("0xFF"))
        self.assertTrue(_is_literal("0x0"))

    def test_variable(self):
        self.assertFalse(_is_literal("x"))
        self.assertFalse(_is_literal("t0"))
        self.assertFalse(_is_literal("arr"))
        self.assertFalse(_is_literal("WHILE_START"))


# ---------------------------------------------------------------------------
# IRFunction and IRProgram tests
# ---------------------------------------------------------------------------

class TestIRFunction(unittest.TestCase):

    def test_emit_and_body_length(self):
        func = IRFunction(name="double", params=["n"], return_type="int")
        func.emit(IRBinOp("t0", "n", BinOp.MUL, "2"))
        func.emit(IRReturn("t0"))
        self.assertEqual(len(func.body), 2)

    def test_str_contains_name_and_instrs(self):
        func = IRFunction(name="double", params=["n"], return_type="int")
        func.emit(IRReturn("n"))
        out = str(func)
        self.assertIn("double", out)
        self.assertIn("return n", out)

    def test_params_in_str(self):
        func = IRFunction(name="add", params=["a", "b"], return_type="int")
        out = str(func)
        self.assertIn("a, b", out)


class TestIRProgram(unittest.TestCase):

    def _make_program(self):
        """Build a sample IRProgram with factorial."""
        prog = IRProgram()

        # factorial(n): if n <= 1 return 1; else return n * factorial(n-1)
        func = IRFunction(name="factorial", params=["n"], return_type="int")
        func.emit(IRLabel("FUNC_factorial"))
        func.emit(IRBinOp("t0", "n", BinOp.LE, "1"))
        func.emit(IRIfFalse("t0", "FACT_ELSE_0"))
        func.emit(IRReturn("1"))
        func.emit(IRLabel("FACT_ELSE_0"))
        func.emit(IRBinOp("t1", "n", BinOp.SUB, "1"))
        func.emit(IRParam("t1"))
        func.emit(IRCall("t2", "factorial", 1))
        func.emit(IRBinOp("t3", "n", BinOp.MUL, "t2"))
        func.emit(IRReturn("t3"))

        prog.add_function(func)
        return prog

    def test_get_function(self):
        prog = self._make_program()
        func = prog.get_function("factorial")
        self.assertIsNotNone(func)
        self.assertEqual(func.name, "factorial")

    def test_get_function_missing(self):
        prog = self._make_program()
        self.assertIsNone(prog.get_function("no_existe"))

    def test_str_contains_all_functions(self):
        prog = self._make_program()
        out = str(prog)
        self.assertIn("factorial", out)
        self.assertIn("return", out)

    def test_instruction_count(self):
        prog = self._make_program()
        func = prog.get_function("factorial")
        self.assertEqual(len(func.body), 10)

    def test_full_defs_uses_pipeline(self):
        """
        Simulates the flow used by liveness analysis:
        collect all defs and uses of a function.
        """
        prog = self._make_program()
        func = prog.get_function("factorial")

        all_defs = set()
        all_uses = set()
        for instr in func.body:
            all_defs |= instr.defs()
            all_uses |= instr.uses()

        self.assertIn("t0", all_defs)
        self.assertIn("t1", all_defs)
        self.assertIn("t2", all_defs)
        self.assertIn("t3", all_defs)

        self.assertIn("n", all_uses)


if __name__ == "__main__":
    unittest.main(verbosity=2)
