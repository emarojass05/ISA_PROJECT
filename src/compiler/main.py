import sys

from antlr4 import FileStream, CommonTokenStream
from antlr4.error.ErrorListener import ErrorListener

from src.compiler.generated.LanguageLexer import LanguageLexer
from src.compiler.generated.LanguageParser import LanguageParser
from src.compiler.generated.LanguageVisitor import LanguageVisitor
from src.compiler.semantic.ControlFlowVisitor import ControlFlowVisitor

from src.compiler.semantic.fixuptable import FixupTable
from src.compiler.semantic.labeltable import LabelTable
from src.compiler.semantic.symboltable import SymbolTable



class CompilerErrorListener(ErrorListener):
    def __init__(self):
        super().__init__()
        self.errors = []

    def syntaxError(self, recognizer, offendingSymbol, line, column, msg, e):
        self.errors.append(f"[ERR](SYNTAX) line {line}:{column} {msg}")


class SemanticTableBuilder(LanguageVisitor):
    def __init__(self, symbol_table):
        super().__init__()
        self.symbol_table = symbol_table

    def clean_type(self, type_spec_ctx):
        return type_spec_ctx.getText().replace("[", "").replace("]", "")

    def visitProgram(self, ctx):
        for declaration_ctx in ctx.declaration():
            function_ctx = declaration_ctx.functionDecl()

            if function_ctx is not None:
                self.register_function(function_ctx)

        for declaration_ctx in ctx.declaration():
            self.visit(declaration_ctx)

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

                parameters.append({
                    "name": param_name,
                    "type": param_type
                })

        self.symbol_table.declare_function(
            name=name,
            return_type=return_type,
            parameters=parameters,
            line=line
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
                    name=param_name,
                    type_name=param_type,
                    line=line
                )

        self.visit(ctx.block())

        self.symbol_table.exit_scope()

        return None

    def visitVarDecl(self, ctx):
        name = ctx.ID().getText()
        type_name = self.clean_type(ctx.typeSpec())
        line = ctx.ID().getSymbol().line

        self.symbol_table.declare_variable(
            name=name,
            type_name=type_name,
            line=line
        )

        self.visit(ctx.expr())

        return None

    def visitVarDeclNoSemi(self, ctx):
        name = ctx.ID().getText()
        type_name = self.clean_type(ctx.typeSpec())
        line = ctx.ID().getSymbol().line

        self.symbol_table.declare_variable(
            name=name,
            type_name=type_name,
            line=line
        )

        self.visit(ctx.expr())

        return None

    def visitArrayDecl(self, ctx):
        name = ctx.ID().getText()
        type_name = self.clean_type(ctx.typeSpec()) + "[]"
        line = ctx.ID().getSymbol().line
        size = self.get_array_size(ctx)

        symbol = self.symbol_table.declare_variable(
            name=name,
            type_name=type_name,
            line=line,
            size=size
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

    print(f"{'Label':<25} {'Address'}")

    for label_name, address in labels.items():
        print(f"{label_name:<25} {format_address(address)}")


def print_fixup_table(fixup_table):
    print("\n========== FIXUP TABLE ==========")

    fixups = fixup_table.get_fixups()

    if not fixups:
        print("[empty]")
        return

    print(f"{'Instruction':<15} {'Label':<25} {'Jump Type'}")

    for fixup in fixups:
        instruction_index = fixup.get("instruction_index", "-")
        label_name = fixup.get("label_name", "-")
        jump_type = fixup.get("jump_type", "-")

        print(f"{instruction_index:<15} {label_name:<25} {jump_type}")


def main():
    if len(sys.argv) != 2:
        print("Usage: python -m src.compiler.main <source_file.fr>")
        sys.exit(1)

    result = parse_file(sys.argv[1])

    if result is None:
        sys.exit(1)

    tree, parser = result

    symbol_table = SymbolTable()
    label_table = LabelTable()
    fixup_table = FixupTable()

    try:
        semantic_builder = SemanticTableBuilder(symbol_table)
        semantic_builder.visit(tree)

        control_flow_visitor = ControlFlowVisitor(
            label_table=label_table,
            fixup_table=fixup_table
        )
        control_flow_visitor.visit(tree)

    except Exception as error:
        print(f"[ERR](SEMANTIC) {error}")
        sys.exit(1)

    print("[OK] Parse completed")
    print(tree.toStringTree(recog=parser))

    print_symbol_table(symbol_table)
    print_reference_table(symbol_table)
    print_label_table(label_table)
    print_fixup_table(fixup_table)


if __name__ == "__main__":
    main()