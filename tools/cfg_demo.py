"""
tools/cfg_demo.py
=================
Demo interactivo del CFG: compila un archivo .fr y muestra el CFG de
cada funcion con bloques basicos, aristas y (opcionalmente) el formato DOT.

Uso desde la raiz del proyecto:

    # Mostrar CFG de factorial (texto)
    python tools/cfg_demo.py programs/source/factorial.fr

    # Mostrar CFG + formato DOT (para Graphviz)
    python tools/cfg_demo.py programs/source/factorial.fr --dot

    # Solo la funcion 'factorial'
    python tools/cfg_demo.py programs/source/factorial.fr --func factorial

    # Equivalente rapido al flag --cfg de main.py:
    python -m src.compiler.main programs/source/factorial.fr --cfg
"""

import sys
import argparse
from pathlib import Path

# -- path setup (ejecutar desde la raiz del proyecto) --
sys.path.insert(0, str(Path(__file__).parent.parent))

from antlr4 import FileStream, CommonTokenStream
from antlr4.error.ErrorListener import ErrorListener

from src.compiler.generated.LanguageLexer import LanguageLexer
from src.compiler.generated.LanguageParser import LanguageParser
from src.compiler.semantic.symboltable import SymbolTable
from src.compiler.semantic.asmgenerator import AsmGenerator
from src.compiler.semantic.fixuptable import FixupTable
from src.compiler.semantic.labeltable import LabelTable
from src.compiler.ir.ir_generator import IRGenerator
from src.compiler.ir.cfg import CFG


# ---------------------------------------------------------------------------
# Utilidades de parseo (copiadas de main.py para que el script sea standalone)
# ---------------------------------------------------------------------------

class SilentErrorListener(ErrorListener):
    def __init__(self):
        super().__init__()
        self.errors = []

    def syntaxError(self, recognizer, offendingSymbol, line, column, msg, e):
        self.errors.append(f"Syntax error line {line}:{column}: {msg}")


def parse_file(path: str):
    stream = FileStream(path, encoding="utf-8")
    lexer = LanguageLexer(stream)
    lex_err = SilentErrorListener()
    lexer.removeErrorListeners()
    lexer.addErrorListener(lex_err)
    tokens = CommonTokenStream(lexer)
    parser = LanguageParser(tokens)
    par_err = SilentErrorListener()
    parser.removeErrorListeners()
    parser.addErrorListener(par_err)
    tree = parser.program()
    errors = lex_err.errors + par_err.errors
    if errors:
        for e in errors:
            print(f"[ERROR] {e}", file=sys.stderr)
        return None
    return tree


def build_symbol_table(tree, source_file: str) -> SymbolTable:
    """Ejecuta el analisis semantico para poblar la tabla de simbolos."""
    from src.compiler.main import SemanticTableBuilder
    symbol_table = SymbolTable()
    builder = SemanticTableBuilder(symbol_table, source_file=source_file)
    builder.visit(tree)
    return symbol_table


# ---------------------------------------------------------------------------
# Impresion del CFG
# ---------------------------------------------------------------------------

SEPARATOR = "=" * 60
THIN_SEP  = "-" * 60


def print_cfg(cfg: CFG, show_dot: bool = False) -> None:
    print(f"\n{SEPARATOR}")
    print(f"  FUNCION: {cfg.func_name}  |  {len(cfg.blocks)} bloques basicos")
    print(SEPARATOR)

    for block in cfg.blocks:
        print(f"\n  [Block {block.id}]  etiqueta={block.label()}")
        print(f"  {'instrucciones':>14}:")
        for instr in block.instructions:
            print(f"    {instr}")
        pred_str = ", ".join(f"B{p.id}" for p in block.predecessors) or "(ninguno)"
        succ_str = ", ".join(f"B{s.id}" for s in block.successors)   or "(ninguno)"
        print(f"  {'predecesores':>14}: {pred_str}")
        print(f"  {'sucesores':>14}: {succ_str}")

    print(f"\n  Aristas del CFG:")
    for block in cfg.blocks:
        for succ in block.successors:
            print(f"    B{block.id} ({block.label()})  ->  B{succ.id} ({succ.label()})")

    if show_dot:
        print(f"\n  --- DOT (pega esto en https://dreampuf.github.io/GraphvizOnline) ---")
        print(cfg.dot())

    print()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(
        prog="cfg_demo",
        description="Muestra el CFG de cada funcion de un archivo .fr",
    )
    ap.add_argument("source", help="Ruta al archivo .fr")
    ap.add_argument(
        "--dot", action="store_true",
        help="Tambien imprime el grafo en formato DOT (Graphviz)"
    )
    ap.add_argument(
        "--func", default=None,
        help="Mostrar solo la funcion con este nombre"
    )
    args = ap.parse_args()

    source_path = args.source
    if not Path(source_path).exists():
        print(f"[ERROR] Archivo no encontrado: {source_path}", file=sys.stderr)
        sys.exit(1)

    print(f"[INFO] Analizando: {source_path}")

    tree = parse_file(source_path)
    if tree is None:
        sys.exit(1)

    try:
        symbol_table = build_symbol_table(tree, source_path)
    except Exception as exc:
        print(f"[ERROR] Analisis semantico: {exc}", file=sys.stderr)
        sys.exit(1)

    try:
        ir_gen = IRGenerator(symbol_table=symbol_table, source_file=source_path)
        ir_gen.visit(tree)
        ir_program = ir_gen.get_ir()
    except Exception as exc:
        print(f"[ERROR] Generacion de IR: {exc}", file=sys.stderr)
        sys.exit(1)

    funcs = ir_program.functions
    if args.func:
        funcs = [f for f in funcs if f.name == args.func]
        if not funcs:
            print(f"[ERROR] Funcion '{args.func}' no encontrada.", file=sys.stderr)
            sys.exit(1)

    print(f"[OK]   IR generada: {len(ir_program.functions)} funcion(es)")
    print(f"[OK]   Construyendo CFG para {len(funcs)} funcion(es)...")

    for ir_func in funcs:
        cfg = CFG.build_from_function(ir_func)
        print_cfg(cfg, show_dot=args.dot)


if __name__ == "__main__":
    main()
