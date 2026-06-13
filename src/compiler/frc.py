import argparse
import difflib
import sys
from pathlib import Path

from src.compiler.main import (
    parse_file,
    SemanticTableBuilder,
    print_symbol_table,
    print_reference_table,
    print_label_table,
    print_fixup_table,
    print_hex_code,
)

from src.compiler.semantic.fixuptable import FixupTable
from src.compiler.semantic.labeltable import LabelTable
from src.compiler.semantic.symboltable import SymbolTable
from src.compiler.semantic.asmgenerator import AsmGenerator

from src.compiler.backend.encoder import assemble

from src.compiler.ir.ir_generator import IRGenerator
from src.compiler.ir.cfg import CFG
from src.compiler.ir.optimizer import optimize_program, OptimizationLevel
from src.compiler.ir.renamer import rename_program
from src.compiler.ir.copy_propagation import propagate_copies_program
from src.compiler.ir.dce import dce_program
from src.compiler.ir.loop_unroller import unroll_program
from src.compiler.ir.scheduler import schedule_program
from src.compiler.ir.ir_codegen import IRCodeGenerator


_DIFF_W = 72


def _capture_ir(ir_program) -> "dict[str, list[str]]":
    """Snapshot the IR body of every function as a list of strings."""
    return {f.name: [str(i) for i in f.body] for f in ir_program.functions}


def _show_ir_diff(pass_name: str,
                  before: "dict[str, list[str]]",
                  after:  "dict[str, list[str]]") -> None:
    """Print a compact unified diff of IR changes introduced by a pass."""
    W = _DIFF_W
    print(f"\n{'═'*W}")
    print(f"  IR DIFF  ·  {pass_name}")
    print(f"{'═'*W}")

    any_change = False
    for fname, b_lines in before.items():
        a_lines = after.get(fname, [])
        if b_lines == a_lines:
            continue
        any_change = True
        delta = len(a_lines) - len(b_lines)
        sign  = f"+{delta}" if delta >= 0 else str(delta)
        print(f"  func '{fname}'   {len(b_lines)} → {len(a_lines)} instr  ({sign})")
        print(f"{'─'*W}")

        hunks = list(difflib.unified_diff(
            b_lines, a_lines,
            fromfile="before", tofile="after",
            lineterm="", n=2,
        ))

        shown = 0
        for line in hunks:
            if line.startswith("---") or line.startswith("+++"):
                continue
            if shown >= 60:
                print(f"  ... ({len(hunks) - shown} more diff lines, use --ir to see full IR)")
                break
            if line.startswith("+"):
                print(f"  +  {line[1:]}")
            elif line.startswith("-"):
                print(f"  -  {line[1:]}")
            elif line.startswith("@@"):
                print(f"  {line}")
            else:
                print(f"     {line[1:]}")
            shown += 1
        print()

    if not any_change:
        print(f"  (no changes)")
    print(f"{'═'*W}")


def _any_opt(args) -> bool:
    """True when at least one optimization pass is requested."""
    return args.O1 or args.O2 or args.rename or args.dce or (args.loopu is not None) or args.schedule


def _has_individual(args) -> bool:
    """True when any fine-grained pass flag is present."""
    return args.rename or args.dce or (args.loopu is not None) or args.schedule


def _run_individual_passes(ir_program, args) -> None:
    """Apply the resolved pass set and print a minimal stats block."""
    do_rename   = args.O1 or args.O2 or args.rename
    do_dce      = args.O1 or args.O2 or args.dce
    do_loopu    = args.O2 or (args.loopu is not None)
    do_schedule = args.O2 or args.schedule
    # --loopu N overrides the O2 default factor of 0
    factor      = args.loopu if args.loopu is not None else 0

    instrs_before = sum(len(f.body) for f in ir_program.functions)

    if do_rename:
        snap = _capture_ir(ir_program)
        rename_program(ir_program)
        propagate_copies_program(ir_program)
        _show_ir_diff("rename + copy_propagation", snap, _capture_ir(ir_program))
    if do_dce:
        snap = _capture_ir(ir_program)
        dce_program(ir_program)
        _show_ir_diff("dead_code_elimination", snap, _capture_ir(ir_program))
    if do_loopu:
        snap = _capture_ir(ir_program)
        unroll_program(ir_program, factor=factor)
        dce_program(ir_program)
        _show_ir_diff(f"loop_unroll(factor={factor}) + dce", snap, _capture_ir(ir_program))
        if do_rename:
            snap = _capture_ir(ir_program)
            rename_program(ir_program)
            propagate_copies_program(ir_program)
            _show_ir_diff("rename + copy_propagation (post-unroll)", snap, _capture_ir(ir_program))
    if do_schedule:
        snap = _capture_ir(ir_program)
        schedule_program(ir_program)
        _show_ir_diff("instruction_scheduling", snap, _capture_ir(ir_program))

    instrs_after = sum(len(f.body) for f in ir_program.functions)

    # Build human-readable label
    has_ind = _has_individual(args)
    if args.O2 and not has_ind:
        label = "O2"
    elif args.O1 and not has_ind:
        label = "O1"
    else:
        parts = (
            (["rename"] if do_rename else []) +
            (["dce"]    if do_dce    else []) +
            ([f"loopu({factor})"] if do_loopu else []) +
            (["sched"]  if do_schedule else [])
        )
        label = "+".join(parts) if parts else "O0"

    print(f"\n========== OPTIMIZER ({label}) ==========")
    print(f"Instructions before: {instrs_before}")
    print(f"Instructions after : {instrs_after}")
    print(f"Instructions saved : {instrs_before - instrs_after}")


def is_asm_source(source_file):
    return Path(source_file).suffix.lower() in {".s", ".asm"}


def resolve_default_output(source_file, suffix, output_dir):
    source_name = Path(source_file).stem
    return Path(output_dir) / f"{source_name}{suffix}"


def save_hex_code(hex_code, source_file, output_path=None):
    if output_path is not None:
        output_file = Path(output_path)

        if output_file.suffix == "":
            output_file = output_file.with_suffix(".hex")
    else:
        output_file = resolve_default_output(
            source_file=source_file,
            suffix=".hex",
            output_dir=Path("build") / "bin",
        )

    output_file.parent.mkdir(parents=True, exist_ok=True)

    with output_file.open("w", encoding="utf-8") as file:
        for code in hex_code:
            file.write(f"{code}\n")

    return output_file


def save_asm_code(asm_source, source_file, output_path=None):
    if output_path is not None:
        asm_file = Path(output_path)

        if asm_file.suffix == "":
            asm_file = asm_file.with_suffix(".s")
    else:
        asm_file = resolve_default_output(
            source_file=source_file,
            suffix=".s",
            output_dir=Path("build") / "asm",
        )

    asm_file.parent.mkdir(parents=True, exist_ok=True)

    with asm_file.open("w", encoding="utf-8") as file:
        file.write(asm_source)
        file.write("\n")

    return asm_file


def compile_asm_source(args):
    source_path = Path(args.source)

    with source_path.open("r", encoding="utf-8") as file:
        asm_source = file.read()

    if args.verbose:
        print("[INFO] Input detected as assembly source")
        print("[INFO] Phase: assembling to HEX")

    if args.compile_only:
        asm_file = save_asm_code(
            asm_source=asm_source,
            source_file=args.source,
            output_path=args.output,
        )
        print(f"[OK] ASM saved in {asm_file}")
        return 0

    hex_code = assemble(asm_source)

    if args.verbose:
        print("[OK] HEX generated")
        print_hex_code(hex_code)

    output_file = save_hex_code(
        hex_code=hex_code,
        source_file=args.source,
        output_path=args.output,
    )

    print(f"[OK] HEX saved in {output_file}")
    return 0


def compile_fr_source(args):
    source_file = args.source

    if args.verbose:
        print("[INFO] Phase 1-2: Lexical and syntactic analysis")

    result = parse_file(source_file)

    if result is None:
        return 1

    tree, antlr_parser = result

    if args.verbose:
        print("[OK] Parsing completed")
        print("[INFO] Phase 3: Semantic analysis")

    symbol_table = SymbolTable()
    label_table = LabelTable()
    fixup_table = FixupTable()

    ir_program = None
    opt_stats = None

    try:
        semantic_builder = SemanticTableBuilder(symbol_table, source_file=source_file)
        semantic_builder.visit(tree)

        if args.verbose:
            print("[OK] Symbol table built")

        # IR generation
        _needs_ir = args.ir or args.ir_save or args.cfg or _any_opt(args)
        if _needs_ir:
            if args.verbose:
                print("[INFO] Phase 3b: IR generation")
            ir_generator = IRGenerator(
                symbol_table=symbol_table,
                source_file=source_file,
            )
            ir_generator.visit(tree)
            ir_program = ir_generator.get_ir()
            if args.verbose:
                print("[OK] IR generated")

        # Optimization pipeline
        if ir_program is not None and _any_opt(args):
            if args.verbose:
                print("[INFO] Phase 3c: Optimization")
            if (args.O1 or args.O2) and not _has_individual(args):
                # preset level — use full pipeline for detailed stats
                opt_level = OptimizationLevel.O2 if args.O2 else OptimizationLevel.O1
                snap = _capture_ir(ir_program)
                opt_stats = optimize_program(ir_program, level=opt_level)
                _show_ir_diff(opt_level.name, snap, _capture_ir(ir_program))
            else:
                # individual flags (possibly combined with O1/O2)
                _run_individual_passes(ir_program, args)
            if args.verbose:
                print("[OK] Optimization complete")

        if args.verbose:
            print("[INFO] Phase 4: Assembly code generation")

        if ir_program is not None and _any_opt(args):
            if args.verbose:
                print("[INFO] Phase 4 (IR path): IR -> ASM via IRCodeGenerator")
            ir_codegen = IRCodeGenerator(
                symbol_table=symbol_table,
                label_table=label_table,
                fixup_table=fixup_table,
            )
            asm_source = ir_codegen.generate(ir_program)
        else:
            asm_generator = AsmGenerator(
                symbol_table=symbol_table,
                label_table=label_table,
                fixup_table=fixup_table,
                source_file=source_file,
            )
            asm_generator.visit(tree)
            asm_source = asm_generator.get_asm()

        if args.verbose:
            print("[OK] Assembly generated")

        if args.ast:
            print("\n========== AST ==========")
            print(tree.toStringTree(recog=antlr_parser))

        if args.verbose or args.map:
            print_symbol_table(symbol_table)
            print_reference_table(symbol_table)
            print_label_table(label_table)
            print_fixup_table(fixup_table)

        if args.compile_only:
            asm_file = save_asm_code(
                asm_source=asm_source,
                source_file=source_file,
                output_path=args.output,
            )
            print(f"[OK] ASM saved in {asm_file}")
            return 0

        if args.verbose:
            print("[INFO] Phase 5-6: Resolving jumps and encoding HEX")

        hex_code = assemble(asm_source)

        if args.verbose:
            print("[OK] HEX generated")
            print("\n========== ASM ==========")
            print(asm_source)
            print_hex_code(hex_code)

        output_file = save_hex_code(
            hex_code=hex_code,
            source_file=source_file,
            output_path=args.output,
        )

        print(f"[OK] HEX saved in {output_file}")

        if opt_stats is not None:
            print(f"\n========== OPTIMIZER ({opt_stats.level.name}) ==========")
            print(opt_stats)

        if args.ir and ir_program is not None:
            print("\n========== IR ==========")
            print(ir_program)

        if args.ir_save and ir_program is not None:
            output_dir = Path("build") / "bin"
            output_dir.mkdir(parents=True, exist_ok=True)
            ir_file = output_dir / f"{Path(source_file).stem}.ir"
            ir_file.write_text(str(ir_program), encoding="utf-8")
            print(f"[OK] IR saved in {ir_file}")

        if args.cfg and ir_program is not None:
            print("\n========== CFG ==========")
            for ir_func in ir_program.functions:
                cfg = CFG.build_from_function(ir_func)
                print(cfg)

        return 0

    except Exception as error:
        print(f"[ERR](COMPILER) {error}")
        return 1


def main():
    parser = argparse.ArgumentParser(
        prog="frc",
        description="FRC compiler: translates .fr, .s or .asm source files",
    )

    parser.add_argument(
        "source",
        help="Path to the .fr, .s or .asm source file",
    )

    parser.add_argument(
        "-o",
        "--output",
        default=None,
        help="Output file path",
    )

    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Print each compilation phase",
    )

    parser.add_argument(
        "-A",
        "--ast",
        action="store_true",
        help="Print the syntax tree",
    )

    parser.add_argument(
        "-c",
        "--compile-only",
        action="store_true",
        help="Compile only: .fr to .s, or copy/normalize .s/.asm output",
    )

    parser.add_argument(
        "-D",
        "--include-dir",
        action="append",
        default=[],
        help="Add an import search directory",
    )

    parser.add_argument(
        "-L",
        "--link-files",
        default="",
        help="Comma-separated files to link",
    )

    parser.add_argument(
        "-m",
        "--map",
        action="store_true",
        help="Print symbol, reference, label and fixup tables",
    )

    parser.add_argument(
        "--ir",
        action="store_true",
        help="Generate and print the IR (three-address code) for this file",
    )

    parser.add_argument(
        "--ir-save",
        action="store_true",
        help="Save the IR to build/bin/<name>.ir alongside the binary",
    )

    parser.add_argument(
        "--cfg",
        action="store_true",
        help="Build and print the CFG (basic blocks) for each function",
    )

    # preset levels
    opt_group = parser.add_mutually_exclusive_group()
    opt_group.add_argument(
        "--O1",
        action="store_true",
        dest="O1",
        help="Preset: rename + DCE",
    )
    opt_group.add_argument(
        "--O2",
        action="store_true",
        dest="O2",
        help="Preset: rename + DCE + loop unrolling + scheduling",
    )

    # individual passes (combinable with each other and with --O1/--O2)
    parser.add_argument(
        "--rename",
        action="store_true",
        help="Static renaming to break WAR/WAW false dependencies",
    )
    parser.add_argument(
        "--dce",
        action="store_true",
        help="Dead code elimination via liveness analysis",
    )
    parser.add_argument(
        "--loopu",
        nargs="?",
        const=0,
        default=None,
        type=int,
        metavar="FACTOR",
        help="Loop unrolling; optional FACTOR (0 or omitted = heuristic)",
    )
    parser.add_argument(
        "--schedule",
        action="store_true",
        help="Instruction scheduling within basic blocks",
    )

    args = parser.parse_args()

    if args.include_dir and args.verbose:
        print(f"[INFO] Include directories: {args.include_dir}")
        print("[WARN](F_IMPORT) Import resolution through -D is not implemented yet")

    if args.link_files and args.verbose:
        print(f"[INFO] Link files: {args.link_files}")
        print("[WARN](LINK) Linking through -L is not implemented yet")

    try:
        if is_asm_source(args.source):
            exit_code = compile_asm_source(args)
        else:
            exit_code = compile_fr_source(args)

        sys.exit(exit_code)

    except Exception as error:
        print(f"[ERR](FRC) {error}")
        sys.exit(1)


if __name__ == "__main__":
    main()