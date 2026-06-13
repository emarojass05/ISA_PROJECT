

import sys
import os
import argparse
from pathlib import Path

# -- Project root ----------------------------------------------------------
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

# -- User site-packages (graphviz may be installed in ~/.local) ------------
import pathlib as _pl
_user_site = _pl.Path(os.path.expanduser("~")) / ".local" / "lib"
for _p in _user_site.glob("python*/site-packages"):
    if str(_p) not in sys.path:
        sys.path.append(str(_p))

try:
    import graphviz
except ImportError:
    print("[ERROR] Missing library 'graphviz'.")
    print("        Install with:  pip install graphviz")
    sys.exit(1)

from antlr4 import FileStream, CommonTokenStream
from antlr4.error.ErrorListener import ErrorListener

from src.compiler.generated.LanguageLexer import LanguageLexer
from src.compiler.generated.LanguageParser import LanguageParser
from src.compiler.semantic.symboltable import SymbolTable
from src.compiler.ir.ir_generator import IRGenerator
from src.compiler.ir.cfg import CFG
from src.compiler.ir.optimizer import optimize_program, OptimizationLevel
from src.compiler.ir.ir_types import IRReturn, IRIfTrue, IRIfFalse


# -- Error listener --------------------------------------------------------
class _QuietErrorListener(ErrorListener):
    def __init__(self):
        super().__init__()
        self.errors = []

    def syntaxError(self, recognizer, offendingSymbol, line, column, msg, e):
        self.errors.append(f"line {line}:{column} - {msg}")


# -- Pipeline: source -> IRProgram -----------------------------------------
def compile_to_ir(source_file: str, opt_level: OptimizationLevel):
    input_stream = FileStream(source_file, encoding="utf-8")
    lexer = LanguageLexer(input_stream)
    lexer.removeErrorListeners()
    lex_err = _QuietErrorListener()
    lexer.addErrorListener(lex_err)

    token_stream = CommonTokenStream(lexer)
    parser = LanguageParser(token_stream)
    parser.removeErrorListeners()
    parse_err = _QuietErrorListener()
    parser.addErrorListener(parse_err)

    tree = parser.program()
    all_errors = lex_err.errors + parse_err.errors
    if all_errors:
        print(f"[ERROR] Errores de sintaxis en {source_file}:")
        for e in all_errors:
            print(f"  {e}")
        sys.exit(1)

    try:
        from src.compiler.main import SemanticTableBuilder
        symbol_table = SymbolTable()
        SemanticTableBuilder(symbol_table, source_file=source_file).visit(tree)
    except Exception as exc:
        print(f"[ERROR] Semantic error: {exc}")
        sys.exit(1)

    ir_gen = IRGenerator(symbol_table=symbol_table, source_file=source_file)
    ir_gen.visit(tree)
    ir_program = ir_gen.get_ir()

    if opt_level != OptimizationLevel.O0:
        optimize_program(ir_program, level=opt_level)

    return ir_program


# -- Helpers ---------------------------------------------------------------
def _block_role(cfg, block):
    if cfg.blocks and block is cfg.blocks[0]:
        return "entry"
    if block.last() and isinstance(block.last(), IRReturn):
        return "exit"
    return "normal"

def _escape(s: str) -> str:
    return (s.replace("&", "&amp;")
             .replace("<", "&lt;")
             .replace(">", "&gt;")
             .replace('"', "&quot;"))

def _edge_attrs(block, i):
    last = block.last()
    if isinstance(last, (IRIfTrue, IRIfFalse)):
        if i == 0:
            return 'label="T" color="#28A745" fontcolor="#28A745" penwidth=2'
        else:
            return 'label="F" color="#DC3545" fontcolor="#DC3545" penwidth=2'
    return 'color="#555555" penwidth=1.5'


# -- DOT generator (block style) -------------------------------------------
def _dot_blocks(cfg, func_name: str, opt_label: str) -> str:
    COLORS = {
        "entry":  ("#D4EDDA", "#28A745"),
        "exit":   ("#F8D7DA", "#DC3545"),
        "normal": ("#D1ECF1", "#17A2B8"),
    }

    lines = [
        f'digraph "CFG_{func_name}" {{',
        '  graph [rankdir=TB fontname="Helvetica" splines=ortho nodesep=0.7 ranksep=0.9'
        f'         label="CFG - {func_name}  [{opt_label}]" labelloc=t fontsize=13 fontcolor="#333333"]',
        '  node  [shape=none margin=0]',
        '  edge  [fontname="Helvetica" fontsize=10]',
        '',
    ]

    for block in cfg.blocks:
        role = _block_role(cfg, block)
        bg, border = COLORS[role]
        label = block.label() or f"B{block.id}"
        rows = "".join(
            f'<TR><TD ALIGN="LEFT" BALIGN="LEFT">'
            f'<FONT FACE="Courier New" POINT-SIZE="9">{_escape(str(instr))}</FONT>'
            f'</TD></TR>'
            for instr in block.instructions
        )
        html = (
            f'<<TABLE BORDER="2" CELLBORDER="0" CELLSPACING="3" '
            f'BGCOLOR="{bg}" COLOR="{border}" STYLE="ROUNDED">'
            f'<TR><TD BGCOLOR="{border}">'
            f'<FONT COLOR="white" FACE="Helvetica Bold" POINT-SIZE="10"><B>{_escape(label)}</B></FONT>'
            f'</TD></TR>{rows}</TABLE>>'
        )
        lines.append(f'  B{block.id} [label={html}]')

    lines.append('')
    for block in cfg.blocks:
        for i, succ in enumerate(block.successors):
            lines.append(f'  B{block.id} -> B{succ.id} [{_edge_attrs(block, i)}]')

    lines.append('}')
    return "\n".join(lines)


# -- IRProgram rendering ---------------------------------------------------
def render_cfg(ir_program, out_dir: Path, fmt: str, view: bool, opt_label: str) -> list:
    out_dir.mkdir(parents=True, exist_ok=True)
    rendered = []

    for ir_func in ir_program.functions:
        cfg = CFG.build_from_function(ir_func)
        dot_src = _dot_blocks(cfg, ir_func.name, opt_label.lstrip("_"))

        safe_name = ir_func.name.replace("/", "_").replace("\\", "_")
        output_path = out_dir / f"cfg_{safe_name}{opt_label}"

        graph = graphviz.Source(dot_src, filename=str(output_path), format=fmt)
        final_path = graph.render(cleanup=True, view=view)
        rendered.append((ir_func.name, final_path))

        n_blocks = len(cfg.blocks)
        n_edges  = sum(len(b.successors) for b in cfg.blocks)
        print(f"  [OK] {ir_func.name}: {n_blocks} blocks, {n_edges} edges  ->  {final_path}")

    return rendered


# -- Comparison mode: O0 vs O2, HTML side by side -------------------------
def render_compare(source_file: str, out_dir: Path, fmt: str, compare_with: str = "O2"):
    out_dir.mkdir(parents=True, exist_ok=True)
    source_name = Path(source_file).stem

    results = {}
    compare_levels = [(OptimizationLevel.O0, "O0"), (OptimizationLevel.O2, "O2")]
    if compare_with == "O1":
        compare_levels = [(OptimizationLevel.O0, "O0"), (OptimizationLevel.O1, "O1")]
    for level, label in compare_levels:
        print(f"\n  Compilando {label}...")
        ir = compile_to_ir(source_file, level)
        cfgs = {}
        for ir_func in ir.functions:
            cfg = CFG.build_from_function(ir_func)
            dot_src = _dot_blocks(cfg, ir_func.name, label)
            safe = ir_func.name.replace("/", "_").replace("\\", "_")
            path = out_dir / f"cfg_{safe}_{label}"
            g = graphviz.Source(dot_src, filename=str(path), format="svg")
            svg_path = g.render(cleanup=True)
            with open(svg_path, "r", encoding="utf-8") as f:
                svg_content = f.read()
            svg_inline = svg_content[svg_content.find("<svg"):]
            cfgs[ir_func.name] = {
                "svg":    svg_inline,
                "blocks": len(cfg.blocks),
                "edges":  sum(len(b.successors) for b in cfg.blocks),
                "instrs": sum(len(b.instructions) for b in cfg.blocks),
            }
        results[label] = cfgs
        print(f"  {label}: {len(cfgs)} function(s) processed")

    # -- HTML --------------------------------------------------------------
    sections = ""
    level_b = "O1" if compare_with == "O1" else "O2"
    for fn in results["O0"]:
        o0 = results["O0"].get(fn, {})
        o2 = results[level_b].get(fn, {})

        def fmt_delta(d):
            if d < 0: return f'<span style="color:#28A745">▼ {abs(d)}</span>'
            if d > 0: return f'<span style="color:#DC3545">▲ {d}</span>'
            return '<span style="color:#888">= 0</span>'

        db = o2.get("blocks",0) - o0.get("blocks",0)
        de = o2.get("edges", 0) - o0.get("edges", 0)
        di = o2.get("instrs",0) - o0.get("instrs",0)

        sections += f"""
        <section>
          <h2>function: <code>{fn}</code></h2>
          <table class="diff">
            <tr><th>Metric</th><th>O0 (no opt.)</th><th>{level_b} (opt.)</th><th>Delta</th></tr>
            <tr><td>Basic blocks</td><td>{o0.get('blocks','-')}</td><td>{o2.get('blocks','-')}</td><td>{fmt_delta(db)}</td></tr>
            <tr><td>Edges</td><td>{o0.get('edges','-')}</td><td>{o2.get('edges','-')}</td><td>{fmt_delta(de)}</td></tr>
            <tr><td>IR instructions</td><td>{o0.get('instrs','-')}</td><td>{o2.get('instrs','-')}</td><td>{fmt_delta(di)}</td></tr>
          </table>
          <div class="graphs">
            <div class="graph-box">
              <h3>O0 - No optimizations</h3>
              {o0.get('svg','<p>(not available)</p>')}
            </div>
            <div class="graph-box">
              <h3>{level_b} - With optimizations</h3>
              {o2.get('svg','<p>(not available)</p>')}
            </div>
          </div>
        </section>"""

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>CFG Comparison -- {source_name}</title>
  <style>
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{ font-family: 'Segoe UI', Helvetica, Arial, sans-serif;
            background: #f5f7fa; color: #333; padding: 30px; }}
    h1   {{ font-size: 1.6rem; margin-bottom: 6px; color: #1a1a2e; }}
    .subtitle {{ color: #666; font-size: 0.95rem; margin-bottom: 30px; }}
    section  {{ background: white; border-radius: 10px; padding: 24px;
                margin-bottom: 30px; box-shadow: 0 2px 8px rgba(0,0,0,.08); }}
    h2   {{ font-size: 1.15rem; margin-bottom: 16px; color: #1a1a2e; }}
    h3   {{ font-size: 0.95rem; font-weight: 600; margin-bottom: 10px;
            color: #555; text-align: center; }}
    code {{ background: #eef; padding: 2px 6px; border-radius: 4px; font-size: 1rem; }}
    .diff {{ width: 100%; border-collapse: collapse; margin-bottom: 20px; font-size: 0.88rem; }}
    .diff th {{ background: #1a1a2e; color: white; padding: 8px 12px; text-align: left; }}
    .diff td {{ padding: 7px 12px; border-bottom: 1px solid #eee; }}
    .diff tr:last-child td {{ border-bottom: none; }}
    .diff tr:nth-child(even) td {{ background: #fafafa; }}
    .graphs {{ display: flex; gap: 20px; }}
    .graph-box {{ flex: 1; border: 1px solid #e0e0e0; border-radius: 8px;
                  padding: 16px; background: #fafafa; overflow: auto; }}
    .graph-box svg {{ width: 100%; height: auto; }}
    @media (max-width: 900px) {{ .graphs {{ flex-direction: column; }} }}
  </style>
</head>
<body>
  <h1>CFG - Optimization Comparison</h1>
  <p class="subtitle">File: <strong>{source_file}</strong> &nbsp;|&nbsp;
     Generated by <code>visualize_cfg.py --compare</code></p>
  {sections}
</body>
</html>"""

    html_path = out_dir / f"cfg_compare_{source_name}.html"
    with open(html_path, "w", encoding="utf-8") as f:
        f.write(html)

    print(f"\n  [OK] HTML comparison  ->  {html_path}")
    return str(html_path)


# -- Main ------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(
        description="Visualiza el CFG de un archivo fuente FRC (.fr)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    ap.add_argument("source",    help="Source .fr file")
    ap.add_argument("--O1",      action="store_true", help="Optimize with O1")
    ap.add_argument("--O2",      action="store_true", help="Optimize with O2")
    ap.add_argument("--compare", action="store_true",
                    help="Generate O0 vs O2 comparison (or O1 with --O1) as side-by-side HTML")
    ap.add_argument("--fmt",     default="svg", choices=["svg", "png", "pdf"],
                    help="Formato de imagen (default: svg)")
    ap.add_argument("--out",     default=None,
                    help="Directorio de salida (default: build/cfg/)")
    ap.add_argument("--view",    action="store_true",
                    help="Open images when done")
    args = ap.parse_args()

    source_file = args.source
    if not Path(source_file).exists():
        print(f"[ERROR] File not found: {source_file}")
        sys.exit(1)

    out_dir = Path(args.out) if args.out else ROOT / "build" / "cfg"

    print(f"\n=== CFG Visualizer ===")
    print(f"  Source : {source_file}")
    print(f"  Format : {args.fmt}")
    print(f"  Output : {out_dir}/")

    if args.compare:
        cw = "O1" if args.O1 else "O2"
        print(f"  Mode   : comparison O0 vs {cw}\n")
        render_compare(source_file, out_dir, args.fmt, compare_with=cw)
        return

    if args.O2:
        opt_level, opt_label = OptimizationLevel.O2, "_O2"
    elif args.O1:
        opt_level, opt_label = OptimizationLevel.O1, "_O1"
    else:
        opt_level, opt_label = OptimizationLevel.O0, "_O0"

    print(f"  Level  : {opt_level.name}\n")

    ir_program = compile_to_ir(source_file, opt_level)
    rendered   = render_cfg(ir_program, out_dir, args.fmt, args.view, opt_label)
    print(f"\n{len(rendered)} image(s) generated in:  {out_dir}/")


if __name__ == "__main__":
    main()
