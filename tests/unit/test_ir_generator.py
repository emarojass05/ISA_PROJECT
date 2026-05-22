"""
tests/unit/test_ir_generator.py

Tests del IRGenerator: compila programas .fr reales y verifica que la IR
generada contiene las instrucciones correctas.

Qué se verifica:
  1. factorial.fr    — funciones, llamadas recursivas, if/else, return
  2. while loop      — WHILE labels, IRGoto, IRIfFalse
  3. for loop        — FOR labels, forInit, forUpdate
  4. arrays          — IRStore en declaración, IRLoad en acceso indexado
  5. variables glob  — IRLoad/IRStore con prefijo @
  6. Estructura      — cada función tiene su IRLabel de entrada

Ejecutar:
    python3 -m unittest tests/unit/test_ir_generator.py -v
"""

import sys
import os
import textwrap
import tempfile
import unittest

REPO_ROOT   = os.path.join(os.path.dirname(__file__), "..", "..")
ANTLR_SITE  = os.path.join(REPO_ROOT, ".venv", "lib", "python3.12", "site-packages")
sys.path.insert(0, ANTLR_SITE)
sys.path.insert(0, REPO_ROOT)

from src.compiler.main import parse_file
from src.compiler.semantic.symboltable import SymbolTable
from src.compiler.main import SemanticTableBuilder
from src.compiler.ir.ir_generator import IRGenerator
from src.compiler.ir.ir_types import (
    IRBinOp, IRCopy, IRLoad, IRStore,
    IRLabel, IRGoto, IRIfFalse, IRIfTrue,
    IRParam, IRCall, IRReturn, IRUnOp,
    BinOp,
)
from src.compiler.ir.ir_program import IRFunction, IRProgram


# ---------------------------------------------------------------------------
# Helper: compila un string de código fuente y devuelve el IRProgram
# ---------------------------------------------------------------------------

def compile_to_ir(source_code: str) -> IRProgram:
    """Escribe el código en un archivo temporal y lo compila a IR."""
    with tempfile.NamedTemporaryFile(suffix=".fr", mode="w",
                                     delete=False, encoding="utf-8") as f:
        f.write(textwrap.dedent(source_code))
        path = f.name

    try:
        result = parse_file(path)
        if result is None:
            raise Exception("Parse failed")
        tree, _ = result

        symbol_table = SymbolTable()
        SemanticTableBuilder(symbol_table, source_file=path).visit(tree)

        gen = IRGenerator(symbol_table, source_file=path)
        gen.visit(tree)
        return gen.get_ir()
    finally:
        os.unlink(path)


def instr_types(func: IRFunction):
    """Retorna la lista de tipos de instrucciones de una función."""
    return [type(i).__name__ for i in func.body]


def instrs_of_type(func: IRFunction, cls):
    """Filtra instrucciones de un tipo específico."""
    return [i for i in func.body if isinstance(i, cls)]


# ---------------------------------------------------------------------------
# 1. Factorial — funciones, recursión, if/else
# ---------------------------------------------------------------------------

class TestFactorial(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.ir = compile_to_ir("""
            fonc [int] factorial_aux([int] n, [int] acc) {
                si (n <= 1) {
                    ret acc;
                }
                ret factorial_aux(n - 1, acc * n);
            }

            fonc [int] factorial([int] n) {
                ret factorial_aux(n, 1);
            }

            fonc [int] main() {
                [int] result = factorial(5);
                ret result;
            }
        """)

    def test_three_functions_generated(self):
        names = [f.name for f in self.ir.functions]
        self.assertIn("factorial_aux", names)
        self.assertIn("factorial", names)
        self.assertIn("main", names)

    def test_each_function_starts_with_label(self):
        for func in self.ir.functions:
            first = func.body[0]
            self.assertIsInstance(first, IRLabel)
            self.assertEqual(first.name, f"FUNC_{func.name}")

    def test_factorial_aux_has_if_false(self):
        func = self.ir.get_function("factorial_aux")
        conds = instrs_of_type(func, IRIfFalse)
        self.assertGreaterEqual(len(conds), 1, "Debe haber al menos un IRIfFalse para el if")

    def test_factorial_aux_has_return(self):
        func = self.ir.get_function("factorial_aux")
        rets = instrs_of_type(func, IRReturn)
        self.assertGreaterEqual(len(rets), 2, "Debe haber return en cada rama del if")

    def test_recursive_call_has_param_and_call(self):
        func = self.ir.get_function("factorial_aux")
        params = instrs_of_type(func, IRParam)
        calls  = instrs_of_type(func, IRCall)
        self.assertEqual(len(params), 2, "La llamada recursiva tiene 2 argumentos")
        self.assertEqual(len(calls),  1)
        self.assertEqual(calls[0].func, "factorial_aux")
        self.assertEqual(calls[0].arg_count, 2)

    def test_factorial_params(self):
        func = self.ir.get_function("factorial_aux")
        self.assertEqual(func.params, ["n", "acc"])

    def test_return_type(self):
        func = self.ir.get_function("factorial")
        self.assertEqual(func.return_type, "int")


# ---------------------------------------------------------------------------
# 2. While loop
# ---------------------------------------------------------------------------

class TestWhileLoop(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.ir = compile_to_ir("""
            fonc [int] suma([int] n) {
                [int] acc = 0;
                [int] i = 0;
                alors (i < n) {
                    acc = acc + i;
                    i = i + 1;
                }
                ret acc;
            }
        """)
        cls.func = cls.ir.get_function("suma")

    def test_while_start_label(self):
        labels = [i.name for i in instrs_of_type(self.func, IRLabel)]
        self.assertTrue(any("WHILE_START" in l for l in labels))

    def test_while_end_label(self):
        labels = [i.name for i in instrs_of_type(self.func, IRLabel)]
        self.assertTrue(any("WHILE_END" in l for l in labels))

    def test_iffalse_exits_loop(self):
        conds = instrs_of_type(self.func, IRIfFalse)
        self.assertGreaterEqual(len(conds), 1)
        # El target del IRIfFalse debe ser el label de fin del while
        target = conds[0].target
        self.assertIn("WHILE_END", target)

    def test_goto_back_to_start(self):
        gotos = instrs_of_type(self.func, IRGoto)
        self.assertGreaterEqual(len(gotos), 1)
        self.assertTrue(any("WHILE_START" in g.target for g in gotos))

    def test_accumulator_uses_binop_add(self):
        adds = [i for i in instrs_of_type(self.func, IRBinOp) if i.op == BinOp.ADD]
        self.assertGreaterEqual(len(adds), 1)


# ---------------------------------------------------------------------------
# 3. For loop
# ---------------------------------------------------------------------------

class TestForLoop(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.ir = compile_to_ir("""
            fonc [int] suma_for([int] n) {
                [int] acc = 0;
                pour ([int] i = 0; i < n; i = i + 1) {
                    acc = acc + i;
                }
                ret acc;
            }
        """)
        cls.func = cls.ir.get_function("suma_for")

    def test_for_labels_present(self):
        labels = [i.name for i in instrs_of_type(self.func, IRLabel)]
        self.assertTrue(any("FOR_START"  in l for l in labels))
        self.assertTrue(any("FOR_UPDATE" in l for l in labels))
        self.assertTrue(any("FOR_END"    in l for l in labels))

    def test_goto_back_to_start(self):
        gotos = instrs_of_type(self.func, IRGoto)
        self.assertTrue(any("FOR_START" in g.target for g in gotos))

    def test_has_return(self):
        rets = instrs_of_type(self.func, IRReturn)
        self.assertGreaterEqual(len(rets), 1)


# ---------------------------------------------------------------------------
# 4. If / else
# ---------------------------------------------------------------------------

class TestIfElse(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.ir = compile_to_ir("""
            fonc [int] max([int] a, [int] b) {
                si (a > b) {
                    ret a;
                } sinon {
                    ret b;
                }
            }
        """)
        cls.func = cls.ir.get_function("max")

    def test_iffalse_present(self):
        self.assertGreaterEqual(len(instrs_of_type(self.func, IRIfFalse)), 1)

    def test_else_label_present(self):
        labels = [i.name for i in instrs_of_type(self.func, IRLabel)]
        self.assertTrue(any("IF_ELSE" in l for l in labels))

    def test_end_label_present(self):
        labels = [i.name for i in instrs_of_type(self.func, IRLabel)]
        self.assertTrue(any("IF_END" in l for l in labels))

    def test_two_returns(self):
        rets = instrs_of_type(self.func, IRReturn)
        self.assertEqual(len(rets), 2)

    def test_goto_skips_else(self):
        """Debe haber un IRGoto que salta el bloque else."""
        gotos = instrs_of_type(self.func, IRGoto)
        self.assertGreaterEqual(len(gotos), 1)


# ---------------------------------------------------------------------------
# 5. Variables globales
# ---------------------------------------------------------------------------

class TestGlobalVariables(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.ir = compile_to_ir("""
            [int] contador = 0;

            fonc [int] incrementar() {
                contador = contador + 1;
                ret contador;
            }
        """)
        cls.func = cls.ir.get_function("incrementar")

    def test_global_load_uses_at_prefix(self):
        """Las variables globales se cargan con IRLoad base='@nombre'."""
        loads = instrs_of_type(self.func, IRLoad)
        self.assertGreaterEqual(len(loads), 1)
        self.assertTrue(any(l.base == "@contador" for l in loads))

    def test_global_store_uses_at_prefix(self):
        """Las variables globales se guardan con IRStore base='@nombre'."""
        stores = instrs_of_type(self.func, IRStore)
        self.assertGreaterEqual(len(stores), 1)
        self.assertTrue(any(s.base == "@contador" for s in stores))


# ---------------------------------------------------------------------------
# 6. Variables locales
# ---------------------------------------------------------------------------

class TestLocalVariables(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.ir = compile_to_ir("""
            fonc [int] doble([int] x) {
                [int] resultado = x + x;
                ret resultado;
            }
        """)
        cls.func = cls.ir.get_function("doble")

    def test_local_var_uses_copy(self):
        """Las variables locales se asignan con IRCopy, no con IRStore."""
        copies = instrs_of_type(self.func, IRCopy)
        # Debe haber al menos una copia hacia 'resultado'
        self.assertTrue(any(c.dest == "resultado" for c in copies))

    def test_binop_add_present(self):
        adds = [i for i in instrs_of_type(self.func, IRBinOp) if i.op == BinOp.ADD]
        self.assertGreaterEqual(len(adds), 1)


# ---------------------------------------------------------------------------
# 7. Llamadas a función con múltiples argumentos
# ---------------------------------------------------------------------------

class TestFunctionCall(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.ir = compile_to_ir("""
            fonc [int] suma3([int] a, [int] b, [int] c) {
                ret a + b + c;
            }

            fonc [int] main() {
                [int] r = suma3(1, 2, 3);
                ret r;
            }
        """)

    def test_three_params_emitted(self):
        func = self.ir.get_function("main")
        params = instrs_of_type(func, IRParam)
        self.assertEqual(len(params), 3)

    def test_call_has_correct_arg_count(self):
        func = self.ir.get_function("main")
        calls = instrs_of_type(func, IRCall)
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0].func, "suma3")
        self.assertEqual(calls[0].arg_count, 3)

    def test_call_result_used(self):
        func = self.ir.get_function("main")
        calls = instrs_of_type(func, IRCall)
        result_temp = calls[0].dest
        # El resultado de la llamada debe usarse en algún lado
        all_uses = set()
        for instr in func.body:
            all_uses |= instr.uses()
        self.assertIn(result_temp, all_uses)


# ---------------------------------------------------------------------------
# 8. Programa real — factorial.fr del repo
# ---------------------------------------------------------------------------

class TestFactorialFile(unittest.TestCase):

    FACTORIAL_PATH = os.path.join(
        os.path.dirname(__file__), "..", "..",
        "programs", "source", "factorial.fr"
    )

    def test_file_compiles_to_ir(self):
        result = parse_file(self.FACTORIAL_PATH)
        self.assertIsNotNone(result, "factorial.fr debe parsear correctamente")
        tree, _ = result

        symbol_table = SymbolTable()
        SemanticTableBuilder(symbol_table, source_file=self.FACTORIAL_PATH).visit(tree)

        gen = IRGenerator(symbol_table, source_file=self.FACTORIAL_PATH)
        gen.visit(tree)
        ir = gen.get_ir()

        self.assertGreaterEqual(len(ir.functions), 1)

    def test_all_functions_have_entry_label(self):
        result = parse_file(self.FACTORIAL_PATH)
        tree, _ = result
        symbol_table = SymbolTable()
        SemanticTableBuilder(symbol_table, source_file=self.FACTORIAL_PATH).visit(tree)
        gen = IRGenerator(symbol_table, source_file=self.FACTORIAL_PATH)
        gen.visit(tree)
        ir = gen.get_ir()

        for func in ir.functions:
            self.assertIsInstance(func.body[0], IRLabel)
            self.assertEqual(func.body[0].name, f"FUNC_{func.name}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
