import argparse
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

    try:
        semantic_builder = SemanticTableBuilder(symbol_table, source_file=source_file)
        semantic_builder.visit(tree)

        if args.verbose:
            print("[OK] Symbol table built")
            print("[INFO] Phase 4: Assembly code generation")

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