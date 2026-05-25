import sys
import argparse
from pathlib import Path

from antlr4 import FileStream, CommonTokenStream
from antlr4.error.ErrorListener import ErrorListener

from src.compiler.generated.LanguageLexer import LanguageLexer
from src.compiler.generated.LanguageParser import LanguageParser
from src.compiler.generated.LanguageVisitor import LanguageVisitor

from src.compiler.semantic.fixuptable import FixupTable
from src.compiler.semantic.labeltable import LabelTable
from src.compiler.semantic.symboltable import SymbolTable
from src.compiler.semantic.asmgenerator import AsmGenerator

from src.compiler.backend.encoder import assemble

from src.compiler.ir.ir_generator import IRGenerator
from src.compiler.ir.cfg import CFG
from src.compiler.ir.optimizer import optimize_program, OptimizationLevel
from src.compiler.ir.ir_codegen import IRCodeGenerator


class CompilerErrorListener(ErrorListener):
    def __init__(self):
        super().__init__()
        self.errors = []

    def syntaxError(self, recognizer, offendingSymbol, line, column, msg, e):
        self.errors.append(f"[ERR](SYNTAX) line {line}:{column} {msg}")


class SemanticTableBuilder(LanguageVisitor):
    def __init__(self, symbol_table, source_file=None, visited_imports=None):
        super().__init__()
        self.symbol_table = symbol_table
        self.source_file = source_file
        self.visited_imports = visited_imports if visited_imports is not None else set()

    def clean_type(self, type_spec_ctx):
        return type_spec_ctx.getText().replace("[", "").replace("]", "")

    def visitProgram(self, ctx):
        for import_ctx in ctx.importDecl():
            self.visit(import_ctx)
        for declaration_ctx in ctx.declaration():
            function_ctx = declaration_ctx.functionDecl()
            if function_ctx is not None:
                self.register_function(function_ctx)
        for declaration_ctx in ctx.declaration():
            self.visit(declaration_ctx)
        return None

    def visitImportDecl(self, ctx):
        from pathlib import Path
        raw = ctx.STRING_LITERAL().getText()
        path_str = raw[1:-1]
        if self.source_file:
            import_path = Path(self.source_file).parent / path_str
        else:
            import_path = Path(path_str)
        if not import_path.exists():
            import_path = Path(path_str)
        if not import_path.exists():
            raise Exception(f"Import error: file not found: {path_str!r}")
        real_path = str(import_path.resolve())
        if real_path in self.visited_imports:
            return None
        self.visited_imports.add(real_path)
        result = parse_file(str(import_path))
        if result is None:
            raise Exception(f"Import error: failed to parse {path_str!r}")
        tree, _ = result
        sub_builder = SemanticTableBuilder(
            symbol_table=self.symbol_table,
            source_file=str(import_path),
            visited_imports=self.visited_imports,
        )
        sub_builder.visit(tree)
        return None

    def register_function(self, ctx):
        name = ctx.ID().getText()
        return_type = self.clean_type(ctx.typeSpec())
        line = ctx.ID().getSymbol().line
        parameters = []
        if ctx.params():
            for param_ctx in ctx.params().param():
                param_type = self.clean_type(param_ctx.typeSpec())
                if param_ctx.pointer():
                    param_type += "*"
                param_name = param_ctx.ID().getText()
                parameters.append({"name": param_name, "type": param_type})
        self.symbol_table.declare_function(
            name=name, return_type=return_type, parameters=parameters, line=line
        )

    def visitFunctionDecl(self, ctx):
        function_name = ctx.ID().getText()
        self.symbol_table.enter_scope(function_name, reset_local=True)
        if ctx.params():
            for param_ctx in ctx.params().param():
                param_type = self.clean_type(param_ctx.typeSpec())
                if param_ctx.pointer():
                    param_type += "*"
                param_name = param_ctx.ID().getText()
                line = param_ctx.ID().getSymbol().line
                self.symbol_table.declare_parameter(
                    name=param_name, type_name=param_type, line=line
                )
        self.visit(ctx.block())
        frame_size = self.symbol_table.next_frame_offset
        self.symbol_table.exit_scope()
        _, func_symbol = self.symbol_table.lookup(function_name)
        if func_symbol is not None:
            func_symbol["frame_size"] = frame_size
        return None

    def visitVarDecl(self, ctx):
        name = ctx.ID().getText()
        type_name = self.clean_type(ctx.typeSpec())
        line = ctx.ID().getSymbol().line
        self.symbol_table.declare_variable(name=name, type_name=type_name, line=line)
        self.visit(ctx.expr())
        return None

    def visitVarDeclNoSemi(self, ctx):
        name = ctx.ID().getText()
        type_name = self.clean_type(ctx.typeSpec())
        line = ctx.ID().getSymbol().line
        self.symbol_table.declare_variable(name=name, type_name=type_name, line=line)
        self.visit(ctx.expr())
        return None

    def visitArrayDecl(self, ctx):
        name = ctx.ID().getText()
        type_name = self.clean_type(ctx.typeSpec()) + "[]"
        line = ctx.ID().getSymbol().line
        size = self.get_array_size(ctx)
        symbol = self.symbol_table.declare_variable(
            name=name, type_name=type_name, line=line, size=size
        )
        symbol["kind"] = "array"
        if ctx.expr():
            self.visit(ctx.expr())
        if ctx.arrayLiteral():
            self.visit(ctx.arrayLiteral())
        return None

    def get_array_size(self, ctx):
        if ctx.arrayLiteral():
            return len(ctx.arrayLiteral().expr())
        if ctx.expr():
            text = ctx.expr().getText()
            try:
                return int(text, 0)
            except ValueError:
                return 1
        return 1

    def visitAssignment(self, ctx):
        name = ctx.ID().getText()
        line = ctx.ID().getSymbol().line
        self.symbol_table.add_reference(name, line)
        if ctx.expr():
            self.visit(ctx.expr())
        return None

    def visitAssignmentNoSemi(self, ctx):
        if ctx.ID():
            name = ctx.ID().getText()
            line = ctx.ID().getSymbol().line
            self.symbol_table.add_reference(name, line)
        if ctx.indexedAccess():
            self.visit(ctx.indexedAccess())
        if ctx.expr():
            self.visit(ctx.expr())
        return None

    def visitIndexedAssignment(self, ctx):
        self.visit(ctx.indexedAccess())
        self.visit(ctx.expr())
        return None

    def visitIndexedAccess(self, ctx):
        name = ctx.ID().getText()
        line = ctx.ID().getSymbol().line
        self.symbol_table.add_reference(name, line)
        for expr_ctx in ctx.expr():
            self.visit(expr_ctx)
        return None

    def visitFunctionCall(self, ctx):
        name = ctx.ID().getText()
        line = ctx.ID().getSymbol().line
        symbol = self.symbol_table.add_reference(name, line)
        if symbol["kind"] != "function":
            raise Exception(f"Error line {line}: '{name}' is not a function")
        expected_count = len(symbol.get("parameters", []))
        received_count = len(ctx.args().expr()) if ctx.args() else 0
        if expected_count != received_count:
            raise Exception(
                f"Error line {line}: function '{name}' expected "
                f"{expected_count} arguments, received {received_count}"
            )
        if ctx.args():
            self.visit(ctx.args())
        return None

    def visitPrimaryExpr(self, ctx):
        if ctx.ID():
            name = ctx.ID().getText()
            line = ctx.ID().getSymbol().line
            self.symbol_table.add_reference(name, line)
            return None
        return self.visitChildren(ctx)


def parse_file(file_path: str):
    input_stream = FileStream(file_path, encoding="utf-8")
    lexer = LanguageLexer(input_stream)
    lexer_errors = CompilerErrorListener()
    lexer.removeErrorListeners()
    lexer.addErrorListener(lexer_errors)
    token_stream = CommonTokenStream(lexer)
    parser = LanguageParser(token_stream)
    parser_errors = CompilerErrorListener()
    parser.removeErrorListeners()
    parser.addErrorListener(parser_errors)
    tree = parser.program()
    errors = lexer_errors.errors + parser_errors.errors
    if errors:
        for error in errors:
            print(error)
        return None
    return tree, parser


def format_address(address):
    if address is None:
        return "-"
    if isinstance(address, int):
        return f"0x{address:04X}"
    return str(address)


def print_symbol_table(symbol_table):
    print("\n========== SYMBOL TABLE ==========")
    symbols = symbol_table.get_symbols()
    if not symbols:
        print("[empty]")
        return
    print(
        f"{'Scope':<15} {'Name':<15} {'Kind':<12} "
        f"{'Type':<10} {'Address':<10} {'Size':<6} {'Line':<6}"
    )
    for (_, _), symbol in symbols.items():
        scope = symbol.get("scope", "-")
        name = symbol.get("name", "-")
        kind = symbol.get("kind", "-")
        type_name = symbol.get("type", "-")
        address = format_address(symbol.get("address"))
        size = symbol.get("size", "-")
        line = symbol.get("line", "-")
        print(
            f"{scope:<15} {name:<15} {kind:<12} "
            f"{type_name:<10} {address:<10} {size:<6} {line:<6}"
        )


def print_reference_table(symbol_table):
    print("\n========== REFERENCE TABLE ==========")
    references = symbol_table.get_references()
    if not references:
        print("[empty]")
        return
    print(f"{'Scope':<15} {'Name':<15} {'References'}")
    for (scope, name), lines in references.items():
        references_text = ", ".join(str(line) for line in lines) if lines else "-"
        print(f"{scope:<15} {name:<15} {references_text}")


def print_label_table(label_table):
    print("\n========== LABEL TABLE ==========")
    labels = label_table.get_labels()
    if not labels:
        print("[empty]")
        return
    print(f"{'Label':<30} {'Address'}")
    for label_name, address in labels.items():
        print(f"{label_name:<30} {format_address(address)}")


def print_fixup_table(fixup_table):
    print("\n========== FIXUP TABLE ==========")
    fixups = fixup_table.get_fixups()
    if not fixups:
        print("[empty]")
        return
    print(f"{'Instruction':<15} {'Label':<30} {'Jump Type'}")
    for fixup in fixups:
        instruction_index = fixup.get("instruction_index", "-")
        label_name = fixup.get("label_name", "-")
        jump_type = fixup.get("jump_type", "-")
        print(f"{instruction_index:<15} {label_name:<30} {jump_type}")


def print_hex_code(hex_code):
    print("\n========== HEX ==========")
    if not hex_code:
        print("[empty]")
        return
    for index, code in enumerate(hex_code):
        address = index * 4
        print(f"0x{address:04X}: {code}")


def save_hex_code(hex_code, source_file, output_path=None):
    if output_path is not None:
        output_file = Path(output_path)
        if output_file.suffix == "":
            output_file = output_file.with_suffix(".hex")
    else:
        output_dir = Path("build") / "bin"
        output_dir.mkdir(parents=True, exist_ok=True)
        source_name = Path(source_file).stem
        output_file = output_dir / f"{source_name}.hex"
    output_file.parent.mkdir(parents=True, exist_ok=True)
    with output_file.open("w", encoding="utf-8") as file:
        for code in hex_code:
            file.write(f"{code}\n")
    return output_file


def save_asm_code(asm_source, source_file, output_path=None):
    if output_path is not None:
        asm_file = Path(output_path).with_suffix(".asm")
    else:
        output_dir = Path("build") / "bin"
        output_dir.mkdir(parents=True, exist_ok=True)
        source_name = Path(source_file).stem
        asm_file = output_dir / f"{source_name}.asm"
    asm_file.parent.mkdir(parents=True, exist_ok=True)
    with asm_file.open("w", encoding="utf-8") as file:
        file.write(asm_source)
        file.write("\n")
    return asm_file


def main():
    parser = argparse.ArgumentParser(
        prog="frc",
        description="FRC compiler: translates .fr source files into binary code"
    )
    parser.add_argument("source", help="Path to the .fr source file")
    parser.add_argument(
        "-o", "--output", default=None,
        help="Output binary file (default: build/bin/<name>.hex)"
    )
    parser.add_argument(
        "-v", "--verbose", action="store_true",
        help="Verbose mode: print each compilation phase"
    )
    parser.add_argument(
        "-s", "--asm", action="store_true",
        help="Also save assembly file (.asm) alongside the binary"
    )
    parser.add_argument(
        "-t", "--tree", action="store_true",
        help="Print the abstract syntax tree (AST)"
    )
    parser.add_argument(
        "-m", "--map", action="store_true",
        help="Print symbol table, reference table, labels and fixups"
    )
    parser.add_argument(
        "--ir", action="store_true",
        help="Generate and print the IR (three-address code) for this file"
    )
    parser.add_argument(
        "--ir-save", action="store_true",
        help="Save the IR to build/bin/<name>.ir alongside the binary"
    )
    parser.add_argument(
        "--cfg", action="store_true",
        help="Build and print the CFG (basic blocks) for each function"
    )

    opt_group = parser.add_mutually_exclusive_group()
    opt_group.add_argument(
        "--O1", action="store_true", dest="O1",
        help="Enable O1 optimizations: register renaming + dead code elimination"
    )
    opt_group.add_argument(
        "--O2", action="store_true", dest="O2",
        help="Enable O2 optimizations: O1 + loop unrolling + instruction scheduling"
    )

    args = parser.parse_args()
    source_file = args.source

    if args.verbose:
        print("[INFO] Phase 1-2: Lexical and syntactic analysis...")

    result = parse_file(source_file)
    if result is None:
        sys.exit(1)

    tree, antlr_parser = result

    if args.verbose:
        print("[OK] Parsing completed")

    if args.verbose:
        print("[INFO] Phase 3: Semantic analysis...")

    symbol_table = SymbolTable()
    label_table = LabelTable()
    fixup_table = FixupTable()

    ir_program = None
    opt_stats  = None
    try:
        semantic_builder = SemanticTableBuilder(symbol_table)
        semantic_builder.visit(tree)

        if args.verbose:
            print("[OK] Symbol table built")

        # ── IR generation (optional, does not replace ASM pipeline) ──────────
        _needs_ir = args.ir or args.ir_save or args.cfg or args.O1 or args.O2
        if _needs_ir:
            if args.verbose:
                print("[INFO] Phase 3b: IR generation...")
            ir_generator = IRGenerator(
                symbol_table=symbol_table,
                source_file=source_file,
            )
            ir_generator.visit(tree)
            ir_program = ir_generator.get_ir()
            if args.verbose:
                print("[OK] IR generated")

        # ── Optimization pipeline ─────────────────────────────────────────────
        opt_stats = None
        if ir_program is not None and (args.O1 or args.O2):
            if args.O2:
                opt_level = OptimizationLevel.O2
            else:
                opt_level = OptimizationLevel.O1
            if args.verbose:
                print(f"[INFO] Phase 3c: Optimization ({opt_level.name})...")
            opt_stats = optimize_program(ir_program, level=opt_level)
            if args.verbose:
                print(f"[OK] Optimization complete")
        # ─────────────────────────────────────────────────────────────────────

        if args.verbose:
            print("[INFO] Phase 4: Assembly code generation...")

        # Cuando la IR fue optimizada usamos el IRCodeGenerator como backend.
        # Sin optimizacion (O0) seguimos con el AsmGenerator basado en AST.
        if ir_program is not None and (args.O1 or args.O2):
            if args.verbose:
                print("[INFO] Phase 4 (IR path): IR -> ASM via IRCodeGenerator...")
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
                fixup_table=fixup_table
            )
            asm_generator.visit(tree)
            asm_source = asm_generator.get_asm()

        if args.verbose:
            print("[OK] Assembly generated")

        if args.verbose:
            print("[INFO] Phase 5-6: Resolving jumps and encoding binary...")

        hex_code = assemble(asm_source)

        if args.verbose:
            print("[OK] Binary code generated")

    except Exception as error:
        print(f"[ERR](COMPILER) {error}")
        sys.exit(1)

    if args.tree:
        print("\n========== AST ==========")
        print(tree.toStringTree(recog=antlr_parser))

    if args.map:
        print_symbol_table(symbol_table)
        print_reference_table(symbol_table)
        print_label_table(label_table)
        print_fixup_table(fixup_table)

    if args.verbose:
        print("\n========== ASM ==========")
        print(asm_source)
        print_hex_code(hex_code)

    output_file = save_hex_code(hex_code, source_file, args.output)
    print(f"[OK] HEX saved in {output_file}")

    if args.asm:
        asm_file = save_asm_code(asm_source, source_file, args.output)
        print(f"[OK] ASM saved in {asm_file}")

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


if __name__ == "__main__":
    main()
