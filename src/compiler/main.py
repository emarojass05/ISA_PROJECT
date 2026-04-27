import sys

from antlr4 import FileStream, CommonTokenStream
from antlr4.error.ErrorListener import ErrorListener

from src.compiler.generated.LanguageLexer import LanguageLexer
from src.compiler.generated.LanguageParser import LanguageParser


class CompilerErrorListener(ErrorListener):
    def __init__(self):
        super().__init__()
        self.errors = []

    def syntaxError(self, recognizer, offendingSymbol, line, column, msg, e):
        self.errors.append(f"[ERR](SYNTAX) line {line}:{column} {msg}")


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


def main():
    if len(sys.argv) != 2:
        print("Usage: python -m src.compiler.main <source_file.fr>")
        sys.exit(1)

    result = parse_file(sys.argv[1])

    if result is None:
        sys.exit(1)

    tree, parser = result

    print("[OK] Parse completed")
    print(tree.toStringTree(recog=parser))


if __name__ == "__main__":
    main()