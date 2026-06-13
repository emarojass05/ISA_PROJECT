from __future__ import annotations

from src.compiler.generated.LanguageVisitor import LanguageVisitor
from src.compiler.ir.ir_types import (
    BinOp, UnOp,
    IRBinOp, IRUnOp, IRCopy, IRLoad, IRStore,
    IRLabel, IRGoto, IRIfTrue, IRIfFalse,
    IRParam, IRCall, IRReturn,
)
from src.compiler.ir.ir_program import IRFunction, IRProgram


# ---------------------------------------------------------------------------

_OP_MAP: dict[str, BinOp] = {
    "+":  BinOp.ADD,
    "-":  BinOp.SUB,
    "*":  BinOp.MUL,
    "/":  BinOp.DIV,
    "%":  BinOp.MOD,
    "&":  BinOp.AND,
    "|":  BinOp.OR,
    "^":  BinOp.XOR,
    "<<": BinOp.SHL,
    ">>": BinOp.SHR,
    "==": BinOp.EQ,
    "!=": BinOp.NEQ,
    ">":  BinOp.GT,
    "<":  BinOp.LT,
    ">=": BinOp.GE,
    "<=": BinOp.LE,
    "&&": BinOp.AND,
    "||": BinOp.OR,
}

WORD_SIZE = 4  # bytes per word (GAEM ISA)


# ---------------------------------------------------------------------------

class IRGenerator(LanguageVisitor):
    """AST visitor that builds an IRProgram from the ANTLR4 parse tree."""

    def __init__(self, symbol_table, source_file=None, visited_imports=None):
        super().__init__()
        self.symbol_table    = symbol_table
        self.ir_program      = IRProgram()
        self.current_func    = None          # active IRFunction
        self.temp_counter    = 0
        self.label_counter   = 0
        self.loop_stack      = []            # for continue/break targets
        self.source_file     = source_file
        self.visited_imports = visited_imports if visited_imports is not None else set()
        self.imported_trees  = []

    def get_ir(self) -> IRProgram:
        return self.ir_program

    # -----------------------------------------------------------------------

    def _new_temp(self) -> str:
        name = f"_t{self.temp_counter}"
        self.temp_counter += 1
        return name

    def _new_label(self, prefix: str) -> str:
        name = f"{prefix}_{self.label_counter}"
        self.label_counter += 1
        return name

    def _emit(self, instr) -> None:
        self.current_func.emit(instr)

    def _get_symbol(self, name: str, line=None):
        _, symbol = self.symbol_table.lookup(name)
        if symbol is None:
            msg = f"Symbol '{name}' not declared"
            if line is not None:
                msg = f"Error line {line}: {msg}"
            raise Exception(msg)
        return symbol

    def _is_local(self, symbol: dict) -> bool:
        return symbol.get("is_local", False) or symbol.get("kind") == "parameter"

    def _emit_load(self, dest: str, symbol: dict) -> None:
        """Load a variable value into dest; local -> IRCopy, global -> IRLoad."""
        if self._is_local(symbol):
            self._emit(IRCopy(dest, symbol["name"]))
        else:
            self._emit(IRLoad(dest, f"@{symbol['name']}", 0))

    def _emit_store(self, src: str, symbol: dict) -> None:
        """Store src into a variable; local -> IRCopy, global -> IRStore."""
        if self._is_local(symbol):
            self._emit(IRCopy(symbol["name"], src))
        else:
            self._emit(IRStore(f"@{symbol['name']}", 0, src))

    # -----------------------------------------------------------------------

    def visitProgram(self, ctx):
        # 1) Process imports first
        for imp in ctx.importDecl():
            self.visit(imp)

        # 2) Global declarations (variables/arrays, not functions)
        for decl in ctx.declaration():
            if decl.functionDecl() is None:
                self.visit(decl)

        # 3) Imported functions
        for tree in self.imported_trees:
            for decl in tree.declaration():
                if decl.functionDecl() is not None:
                    self.visit(decl)

        # 4) Local functions
        for decl in ctx.declaration():
            if decl.functionDecl() is not None:
                self.visit(decl)

        return None

    def visitImportDecl(self, ctx):
        from pathlib import Path
        from src.compiler.main import parse_file

        raw      = ctx.STRING_LITERAL().getText()
        path_str = raw[1:-1]

        if self.source_file:
            import_path = Path(self.source_file).parent / path_str
        else:
            import_path = Path(path_str)

        if not import_path.exists():
            import_path = Path(path_str)
        if not import_path.exists():
            return None

        real_path = str(import_path.resolve())
        if real_path in self.visited_imports:
            return None

        self.visited_imports.add(real_path)

        result = parse_file(str(import_path))
        if result is None:
            raise Exception(f"Import error: failed to parse {path_str!r}")

        tree, _ = result
        self.imported_trees.append(tree)

        for decl in tree.declaration():
            if decl.functionDecl() is None:
                self.visit(decl)

        for imp in tree.importDecl():
            self.visit(imp)

        return None

    def visitAnnotation(self, ctx):
        return None

    # -----------------------------------------------------------------------

    def visitFunctionDecl(self, ctx):
        func_name   = ctx.ID().getText()
        func_symbol = self._get_symbol(func_name)

        params      = [p["name"] for p in func_symbol.get("parameters", [])]
        return_type = func_symbol.get("type", "void")

        ir_func = IRFunction(name=func_name, params=params, return_type=return_type)

        # Save context to support nested functions (edge case)
        prev_func        = self.current_func
        self.current_func = ir_func

        self._emit(IRLabel(f"FUNC_{func_name}"))

        self.symbol_table.enter_scope(func_name, reset_local=False)
        self.visit(ctx.block())
        self.symbol_table.exit_scope()

        self.ir_program.add_function(ir_func)
        self.current_func = prev_func

        return None

    # -----------------------------------------------------------------------

    def visitVarDecl(self, ctx):
        # Global variables do not generate IR; the backend handles them
        if self.current_func is None:
            return None
        name   = ctx.ID().getText()
        symbol = self._get_symbol(name, ctx.ID().getSymbol().line)
        temp   = self.visit(ctx.expr())
        self._emit_store(temp, symbol)
        return None

    def visitVarDeclNoSemi(self, ctx):
        # Global variables do not generate IR; the backend handles them
        if self.current_func is None:
            return None
        name   = ctx.ID().getText()
        symbol = self._get_symbol(name, ctx.ID().getSymbol().line)
        temp   = self.visit(ctx.expr())
        self._emit_store(temp, symbol)
        return None

    def visitArrayDecl(self, ctx):
        # Global arrays do not generate IR; the backend handles them
        if self.current_func is None:
            return None
        name   = ctx.ID().getText()
        symbol = self._get_symbol(name, ctx.ID().getSymbol().line)

        if ctx.arrayLiteral():
            base = name if self._is_local(symbol) else f"@{name}"
            for index, expr_ctx in enumerate(ctx.arrayLiteral().expr()):
                temp = self.visit(expr_ctx)
                self._emit(IRStore(base, index * WORD_SIZE, temp))

        return None

    # -----------------------------------------------------------------------

    def visitAssignment(self, ctx):
        name   = ctx.ID().getText()
        symbol = self._get_symbol(name, ctx.ID().getSymbol().line)

        if ctx.incrementOp():
            current = self._new_temp()
            self._emit_load(current, symbol)
            result = self._new_temp()
            if ctx.incrementOp().getText() == "++":
                self._emit(IRBinOp(result, current, BinOp.ADD, "1"))
            else:
                self._emit(IRBinOp(result, current, BinOp.SUB, "1"))
            self._emit_store(result, symbol)
            return None

        temp = self.visit(ctx.expr())
        self._emit_store(temp, symbol)
        return None

    def visitAssignmentNoSemi(self, ctx):
        if ctx.ID():
            name   = ctx.ID().getText()
            symbol = self._get_symbol(name, ctx.ID().getSymbol().line)
            temp   = self.visit(ctx.expr())
            self._emit_store(temp, symbol)
            return None

        if ctx.indexedAccess():
            addr = self._emit_indexed_address(ctx.indexedAccess())
            val  = self.visit(ctx.expr())
            self._emit(IRStore(addr, 0, val))

        return None

    def visitForUpdate(self, ctx):
        if ctx.assignmentNoSemi():
            return self.visit(ctx.assignmentNoSemi())

        name   = ctx.ID().getText()
        symbol = self._get_symbol(name, ctx.ID().getSymbol().line)
        current = self._new_temp()
        self._emit_load(current, symbol)
        result = self._new_temp()
        if ctx.incrementOp().getText() == "++":
            self._emit(IRBinOp(result, current, BinOp.ADD, "1"))
        else:
            self._emit(IRBinOp(result, current, BinOp.SUB, "1"))
        self._emit_store(result, symbol)
        return None

    def visitIndexedAssignment(self, ctx):
        addr = self._emit_indexed_address(ctx.indexedAccess())
        val  = self.visit(ctx.expr())
        self._emit(IRStore(addr, 0, val))
        return None

    # -----------------------------------------------------------------------

    def visitIfStmt(self, ctx):
        else_label = self._new_label("IF_ELSE")
        end_label  = self._new_label("IF_END")

        cond = self.visit(ctx.expr())
        self._emit(IRIfFalse(cond, else_label))
        self.visit(ctx.block(0))

        if ctx.SINON():
            self._emit(IRGoto(end_label))
            self._emit(IRLabel(else_label))
            self.visit(ctx.block(1))
            self._emit(IRLabel(end_label))
        else:
            self._emit(IRLabel(else_label))

        return None

    def visitWhileStmt(self, ctx):
        start = self._new_label("WHILE_START")
        end   = self._new_label("WHILE_END")

        self.loop_stack.append({"continue": start, "break": end})
        self._emit(IRLabel(start))

        cond = self.visit(ctx.expr())
        self._emit(IRIfFalse(cond, end))
        self.visit(ctx.block())
        self._emit(IRGoto(start))
        self._emit(IRLabel(end))

        self.loop_stack.pop()
        return None

    def visitForStmt(self, ctx):
        start_lbl  = self._new_label("FOR_START")
        update_lbl = self._new_label("FOR_UPDATE")
        end_lbl    = self._new_label("FOR_END")

        self.loop_stack.append({"continue": update_lbl, "break": end_lbl})

        if ctx.forInit():
            self.visit(ctx.forInit())

        self._emit(IRLabel(start_lbl))

        if ctx.expr():
            cond = self.visit(ctx.expr())
            self._emit(IRIfFalse(cond, end_lbl))

        self.visit(ctx.block())

        self._emit(IRLabel(update_lbl))
        if ctx.forUpdate():
            self.visit(ctx.forUpdate())

        self._emit(IRGoto(start_lbl))
        self._emit(IRLabel(end_lbl))

        self.loop_stack.pop()
        return None

    def visitContinueStmt(self, ctx):
        line = ctx.SUIVRE().getSymbol().line
        if not self.loop_stack:
            raise Exception(f"Error line {line}: 'suivre' used outside a loop")
        self._emit(IRGoto(self.loop_stack[-1]["continue"]))
        return None

    def visitReturnStmt(self, ctx):
        if ctx.expr():
            temp = self.visit(ctx.expr())
            self._emit(IRReturn(temp))
        else:
            self._emit(IRReturn())
        return None

    def visitExprStmt(self, ctx):
        self.visit(ctx.expr())
        return None

    # -----------------------------------------------------------------------

    def visitExpr(self, ctx):
        return self.visit(ctx.logicalOrExpr())

    def visitLogicalOrExpr(self, ctx):
        return self._binop_chain(ctx)

    def visitLogicalAndExpr(self, ctx):
        return self._binop_chain(ctx)

    def visitBitwiseOrExpr(self, ctx):
        return self._binop_chain(ctx)

    def visitBitwiseXorExpr(self, ctx):
        return self._binop_chain(ctx)

    def visitEqualityExpr(self, ctx):
        return self._binop_chain(ctx)

    def visitRelationalExpr(self, ctx):
        return self._binop_chain(ctx)

    def visitShiftExpr(self, ctx):
        return self._binop_chain(ctx)

    def visitAdditiveExpr(self, ctx):
        return self._binop_chain(ctx)

    def visitMultiplicativeExpr(self, ctx):
        return self._binop_chain(ctx)

    def _binop_chain(self, ctx) -> str:
        """Handle left-associative binary expressions: a + b + c -> t0=a+b; t1=t0+c."""
        result = self.visit(ctx.getChild(0))
        i = 1
        while i < ctx.getChildCount():
            op_str = ctx.getChild(i).getText()
            right  = self.visit(ctx.getChild(i + 1))

            if op_str not in _OP_MAP:
                raise Exception(f"Unsupported operator in IR: '{op_str}'")

            temp = self._new_temp()
            self._emit(IRBinOp(temp, result, _OP_MAP[op_str], right))
            result = temp
            i += 2
        return result

    def visitUnaryExpr(self, ctx):
        if ctx.primaryExpr():
            return self.visit(ctx.primaryExpr())

        operand = self.visit(ctx.unaryExpr())
        text    = ctx.getText()
        temp    = self._new_temp()

        if text.startswith("!"):
            self._emit(IRUnOp(temp, UnOp.NOT, operand))
            return temp
        if text.startswith("-"):
            self._emit(IRUnOp(temp, UnOp.NEG, operand))
            return temp

        return operand

    def visitPrimaryExpr(self, ctx):
        # Integer literal
        if ctx.INT_LITERAL():
            return ctx.INT_LITERAL().getText()

        # Hex literal
        if ctx.HEX_LITERAL():
            return ctx.HEX_LITERAL().getText()

        # Boolean literal: vrai=1, faux=0
        if ctx.BOOL_LITERAL():
            return "1" if ctx.BOOL_LITERAL().getText() == "vrai" else "0"

        if ctx.STRING_LITERAL():
            raise Exception("String literals are not supported in IR generation")

        if ctx.functionCall():
            return self.visit(ctx.functionCall())

        if ctx.indexedAccess():
            return self.visit(ctx.indexedAccess())

        if ctx.ID():
            name   = ctx.ID().getText()
            symbol = self._get_symbol(name, ctx.ID().getSymbol().line)

            if symbol["kind"] == "array":
                # Return array base address as a temporary
                temp = self._new_temp()
                base = name if self._is_local(symbol) else f"@{name}"
                self._emit(IRCopy(temp, base))
                return temp

            # Scalar variable: load into a temporary
            temp = self._new_temp()
            self._emit_load(temp, symbol)
            return temp

        if ctx.expr():
            return self.visit(ctx.expr())

        raise Exception(f"Unsupported primary expression: '{ctx.getText()}'")

    def visitFunctionCall(self, ctx):
        func_name = ctx.ID().getText()
        args      = ctx.args().expr() if ctx.args() else []

        # Evaluate all arguments first
        arg_temps = [self.visit(arg) for arg in args]

        # Emit one IRParam per argument
        for arg_temp in arg_temps:
            self._emit(IRParam(arg_temp))

        # Emit the IRCall and capture its result
        result = self._new_temp()
        self._emit(IRCall(result, func_name, len(arg_temps)))
        return result

    def visitIndexedAccess(self, ctx):
        addr   = self._emit_indexed_address(ctx)
        result = self._new_temp()
        self._emit(IRLoad(result, addr, 0))
        return result

    def _emit_indexed_address(self, ctx) -> str:
        """Compute address for arr@(i); return temporal holding the address.

        Formula: addr = base + index * WORD_SIZE
        """
        name   = ctx.ID().getText()
        symbol = self._get_symbol(name, ctx.ID().getSymbol().line)

        # Base address
        addr = self._new_temp()
        if symbol["kind"] == "array":
            base = name if self._is_local(symbol) else f"@{name}"
            self._emit(IRCopy(addr, base))
        else:
            # Pointer: load its value (which is the address)
            self._emit_load(addr, symbol)

        # Add each index dimension
        for expr_ctx in ctx.expr():
            idx    = self.visit(expr_ctx)
            scaled = self._new_temp()
            self._emit(IRBinOp(scaled, idx, BinOp.MUL, str(WORD_SIZE)))
            new_addr = self._new_temp()
            self._emit(IRBinOp(new_addr, addr, BinOp.ADD, scaled))
            addr = new_addr

        return addr
