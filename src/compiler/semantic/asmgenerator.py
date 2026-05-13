from src.compiler.generated.LanguageVisitor import LanguageVisitor


class AsmGenerator(LanguageVisitor):
    WORD_SIZE = 4

    TEMP_REGISTERS = [
        "t0", "t1", "t2", "t3", "t4",
        "s10", "s11", "s12", "s13"
    ]

    ARG_REGISTERS = [
        "a0", "a1", "a2", "a3", "a4", "a5"
    ]

    def __init__(self, symbol_table, label_table, fixup_table, source_file=None, visited_imports=None):
        super().__init__()

        self.symbol_table = symbol_table
        self.label_table = label_table
        self.fixup_table = fixup_table

        self.asm_lines = []
        self.instructions = []

        self.label_counter = 0
        self.loop_stack = []
        self.used_registers = set()
        self.return_label_stack = []

        self.source_file = source_file
        self.visited_imports = visited_imports if visited_imports is not None else set()
        self.imported_trees = []

    def get_asm(self):
        return "\n".join(self.asm_lines)

    def current_instruction_index(self):
        return len(self.instructions)

    def current_pc(self):
        return self.current_instruction_index() * self.WORD_SIZE

    def emit(self, instruction):
        self.instructions.append(instruction)
        self.asm_lines.append(f"    {instruction}")

    def emit_comment(self, comment):
        self.asm_lines.append(f"    # {comment}")

    def emit_label(self, label_name):
        self.label_table.define_label(label_name, self.current_pc())
        self.asm_lines.append(f"{label_name}:")

    def emit_jump_fixup(self, instruction, label_name, jump_type):
        instruction_index = self.current_instruction_index()

        self.fixup_table.add_fixup(
            instruction_index=instruction_index,
            label_name=label_name,
            jump_type=jump_type
        )

        self.emit(instruction)

    def new_label(self, prefix):
        label_name = f"{prefix}_{self.label_counter}"
        self.label_counter += 1
        return label_name

    def allocate_register(self):
        for register in self.TEMP_REGISTERS:
            if register not in self.used_registers:
                self.used_registers.add(register)
                return register

        raise Exception("No temporary registers available")

    def free_register(self, register):
        if register in self.used_registers:
            self.used_registers.remove(register)

    def get_symbol(self, name, line=None):
        _, symbol = self.symbol_table.lookup(name)

        if symbol is None:
            if line is None:
                raise Exception(f"Symbol '{name}' was not declared")

            raise Exception(f"Error line {line}: symbol '{name}' was not declared")

        return symbol

    def emit_load_immediate(self, register, value):
        value = int(value) & 0xFFFFFFFF

        upper = (value >> 16) & 0xFFFF
        lower = value & 0xFFFF

        self.emit(f"luhw {register}, 0x{upper:04X}")
        self.emit(f"llhw {register}, 0x{lower:04X}")

    def emit_move(self, destination, source):
        self.emit(f"addi {destination}, {source}, 0")

    def emit_load_symbol(self, destination, symbol):
        address_register = self.allocate_register()

        self.emit_load_immediate(address_register, symbol["address"])
        self.emit(f"lw {destination}, 0({address_register})")

        self.free_register(address_register)

    def emit_store_symbol(self, source, symbol):
        address_register = self.allocate_register()

        self.emit_load_immediate(address_register, symbol["address"])
        self.emit(f"sw {source}, 0({address_register})")

        self.free_register(address_register)

    def emit_return_jump(self):
        if not self.return_label_stack:
            self.emit("jr ra")
            return

        return_label = self.return_label_stack[-1]

        self.emit_jump_fixup(
            instruction=f"j {return_label}",
            label_name=return_label,
            jump_type="J"
        )

    def visitProgram(self, ctx):
        self.emit_label("ENTRY")

        # Procesar imports: emite sus globales ahora y acumula sus arboles
        for import_ctx in ctx.importDecl():
            self.visit(import_ctx)

        for declaration_ctx in ctx.declaration():
            if declaration_ctx.functionDecl() is None:
                self.visit(declaration_ctx)

        _, main_symbol = self.symbol_table.lookup("main")

        if main_symbol is not None:
            self.emit_jump_fixup(
                instruction="jal ra, FUNC_main",
                label_name="FUNC_main",
                jump_type="JAL"
            )

        self.emit_label("PROGRAM_END")
        self.emit_jump_fixup(
            instruction="j PROGRAM_END",
            label_name="PROGRAM_END",
            jump_type="J"
        )

        # Emitir codigo de funciones de archivos importados (recursivo)
        for imported_tree in self.imported_trees:
            for declaration_ctx in imported_tree.declaration():
                if declaration_ctx.functionDecl() is not None:
                    self.visit(declaration_ctx)

        # Emitir codigo de funciones locales
        for declaration_ctx in ctx.declaration():
            if declaration_ctx.functionDecl() is not None:
                self.visit(declaration_ctx)

        return None

    def visitImportDecl(self, ctx):
        from pathlib import Path
        from src.compiler.main import parse_file

        raw = ctx.STRING_LITERAL().getText()
        path_str = raw[1:-1]

        # Resolver path relativo al archivo actual
        if self.source_file:
            import_path = Path(self.source_file).parent / path_str
        else:
            import_path = Path(path_str)

        if not import_path.exists():
            import_path = Path(path_str)

        if not import_path.exists():
            self.emit_comment(f"import not found: {path_str!r}")
            return None

        real_path = str(import_path.resolve())

        # Evitar imports circulares/duplicados
        if real_path in self.visited_imports:
            return None

        self.visited_imports.add(real_path)

        result = parse_file(str(import_path))

        if result is None:
            raise Exception(f"Import error: failed to parse {path_str!r}")

        tree, _ = result

        # Guardar el arbol para emitir sus funciones despues de PROGRAM_END
        self.imported_trees.append(tree)

        # Emitir globales del archivo importado ahora (antes de PROGRAM_END)
        for decl_ctx in tree.declaration():
            if decl_ctx.functionDecl() is None:
                self.visit(decl_ctx)

        # Procesar imports transitivos (el importado puede importar otros)
        for import_ctx in tree.importDecl():
            self.visit(import_ctx)

        return None

    def visitAnnotation(self, ctx):
        self.emit_comment(f"annotation ignored: {ctx.getText()}")
        return None

    def visitFunctionDecl(self, ctx):
        function_name = ctx.ID().getText()
        function_label = f"FUNC_{function_name}"
        return_label = f"{function_label}_RETURN"

        self.emit_label(function_label)

        function_symbol = self.get_symbol(function_name)
        function_symbol["address"] = self.current_pc()

        self.return_label_stack.append(return_label)

        self.symbol_table.enter_scope(function_name, reset_local=False)

        self.emit("addi sp, sp, -4")
        self.emit("sw ra, 0(sp)")

        parameters = function_symbol.get("parameters", [])

        for index, parameter in enumerate(parameters):
            parameter_symbol = self.get_symbol(parameter["name"])

            if index < len(self.ARG_REGISTERS):
                self.emit_store_symbol(self.ARG_REGISTERS[index], parameter_symbol)
            else:
                stack_offset = 4 + (index - len(self.ARG_REGISTERS)) * self.WORD_SIZE
                tmp_register = self.allocate_register()
                self.emit(f"lw {tmp_register}, {stack_offset}(sp)")
                self.emit_store_symbol(tmp_register, parameter_symbol)
                self.free_register(tmp_register)

        self.visit(ctx.block())

        self.emit_label(return_label)

        self.emit("lw ra, 0(sp)")
        self.emit("addi sp, sp, 4")
        self.emit("jr ra")

        self.symbol_table.exit_scope()
        self.return_label_stack.pop()

        return None

    def visitVarDecl(self, ctx):
        name = ctx.ID().getText()
        symbol = self.get_symbol(name, ctx.ID().getSymbol().line)

        value_register = self.visit(ctx.expr())

        self.emit_store_symbol(value_register, symbol)
        self.free_register(value_register)

        return None

    def visitVarDeclNoSemi(self, ctx):
        name = ctx.ID().getText()
        symbol = self.get_symbol(name, ctx.ID().getSymbol().line)

        value_register = self.visit(ctx.expr())

        self.emit_store_symbol(value_register, symbol)
        self.free_register(value_register)

        return None

    def visitArrayDecl(self, ctx):
        name = ctx.ID().getText()
        symbol = self.get_symbol(name, ctx.ID().getSymbol().line)

        if ctx.arrayLiteral():
            expressions = ctx.arrayLiteral().expr()

            for index, expr_ctx in enumerate(expressions):
                value_register = self.visit(expr_ctx)
                address_register = self.allocate_register()

                element_address = symbol["address"] + index * self.WORD_SIZE

                self.emit_load_immediate(address_register, element_address)
                self.emit(f"sw {value_register}, 0({address_register})")

                self.free_register(address_register)
                self.free_register(value_register)

        return None

    def visitAssignment(self, ctx):
        name = ctx.ID().getText()
        symbol = self.get_symbol(name, ctx.ID().getSymbol().line)

        if ctx.incrementOp():
            value_register = self.allocate_register()

            self.emit_load_symbol(value_register, symbol)

            operation = ctx.incrementOp().getText()

            if operation == "++":
                self.emit(f"addi {value_register}, {value_register}, 1")
            elif operation == "--":
                self.emit(f"addi {value_register}, {value_register}, -1")
            else:
                raise Exception(f"Unsupported increment operator '{operation}'")

            self.emit_store_symbol(value_register, symbol)
            self.free_register(value_register)

            return None

        value_register = self.visit(ctx.expr())

        self.emit_store_symbol(value_register, symbol)
        self.free_register(value_register)

        return None

    def visitAssignmentNoSemi(self, ctx):
        if ctx.ID():
            name = ctx.ID().getText()
            symbol = self.get_symbol(name, ctx.ID().getSymbol().line)

            value_register = self.visit(ctx.expr())

            self.emit_store_symbol(value_register, symbol)
            self.free_register(value_register)

            return None

        if ctx.indexedAccess():
            address_register = self.emit_indexed_address(ctx.indexedAccess())
            value_register = self.visit(ctx.expr())

            self.emit(f"sw {value_register}, 0({address_register})")

            self.free_register(address_register)
            self.free_register(value_register)

        return None

    def visitIndexedAssignment(self, ctx):
        address_register = self.emit_indexed_address(ctx.indexedAccess())
        value_register = self.visit(ctx.expr())

        self.emit(f"sw {value_register}, 0({address_register})")

        self.free_register(address_register)
        self.free_register(value_register)

        return None

    def visitIfStmt(self, ctx):
        else_label = self.new_label("IF_ELSE")
        end_label = self.new_label("IF_END")

        condition_register = self.visit(ctx.expr())

        self.emit_jump_fixup(
            instruction=f"beq {condition_register}, zero, {else_label}",
            label_name=else_label,
            jump_type="BEQ"
        )

        self.free_register(condition_register)

        self.visit(ctx.block(0))

        if ctx.SINON():
            self.emit_jump_fixup(
                instruction=f"j {end_label}",
                label_name=end_label,
                jump_type="J"
            )

            self.emit_label(else_label)
            self.visit(ctx.block(1))
            self.emit_label(end_label)
        else:
            self.emit_label(else_label)

        return None

    def visitWhileStmt(self, ctx):
        start_label = self.new_label("WHILE_START")
        end_label = self.new_label("WHILE_END")

        self.loop_stack.append({
            "continue": start_label,
            "break": end_label
        })

        self.emit_label(start_label)

        condition_register = self.visit(ctx.expr())

        self.emit_jump_fixup(
            instruction=f"beq {condition_register}, zero, {end_label}",
            label_name=end_label,
            jump_type="BEQ"
        )

        self.free_register(condition_register)

        self.visit(ctx.block())

        self.emit_jump_fixup(
            instruction=f"j {start_label}",
            label_name=start_label,
            jump_type="J"
        )

        self.emit_label(end_label)

        self.loop_stack.pop()

        return None

    def visitForStmt(self, ctx):
        start_label = self.new_label("FOR_START")
        update_label = self.new_label("FOR_UPDATE")
        end_label = self.new_label("FOR_END")

        self.loop_stack.append({
            "continue": update_label,
            "break": end_label
        })

        if ctx.forInit():
            self.visit(ctx.forInit())

        self.emit_label(start_label)

        if ctx.expr():
            condition_register = self.visit(ctx.expr())

            self.emit_jump_fixup(
                instruction=f"beq {condition_register}, zero, {end_label}",
                label_name=end_label,
                jump_type="BEQ"
            )

            self.free_register(condition_register)

        self.visit(ctx.block())

        self.emit_label(update_label)

        if ctx.forUpdate():
            self.visit(ctx.forUpdate())

        self.emit_jump_fixup(
            instruction=f"j {start_label}",
            label_name=start_label,
            jump_type="J"
        )

        self.emit_label(end_label)

        self.loop_stack.pop()

        return None

    def visitContinueStmt(self, ctx):
        line = ctx.SUIVRE().getSymbol().line

        if not self.loop_stack:
            raise Exception(f"Error line {line}: 'suivre' used outside loop")

        continue_label = self.loop_stack[-1]["continue"]

        self.emit_jump_fixup(
            instruction=f"j {continue_label}",
            label_name=continue_label,
            jump_type="J"
        )

        return None

    def visitReturnStmt(self, ctx):
        if ctx.expr():
            value_register = self.visit(ctx.expr())

            self.emit_move("a0", value_register)
            self.free_register(value_register)

        self.emit_return_jump()

        return None

    def visitExprStmt(self, ctx):
        result_register = self.visit(ctx.expr())

        if result_register:
            self.free_register(result_register)

        return None

    def visitExpr(self, ctx):
        return self.visit(ctx.logicalOrExpr())

    def visitLogicalOrExpr(self, ctx):
        return self.emit_left_associative(ctx, {"||": "or"})

    def visitLogicalAndExpr(self, ctx):
        return self.emit_left_associative(ctx, {"&&": "and"})

    def visitBitwiseOrExpr(self, ctx):
        return self.emit_left_associative(ctx, {"|": "or"})

    def visitBitwiseXorExpr(self, ctx):
        return self.emit_left_associative(ctx, {"^": "xor"})

    def visitEqualityExpr(self, ctx):
        return self.emit_comparison_associative(ctx, {
            "==": "beq",
            "!=": "bne"
        })

    def visitRelationalExpr(self, ctx):
        return self.emit_comparison_associative(ctx, {
            ">": "bgt",
            "<": "blt",
            ">=": "bge",
            "<=": "ble"
        })

    def visitShiftExpr(self, ctx):
        return self.emit_left_associative(ctx, {
            "<<": "sll",
            ">>": "srl"
        })

    def visitAdditiveExpr(self, ctx):
        return self.emit_left_associative(ctx, {
            "+": "add",
            "-": "sub"
        })

    def visitMultiplicativeExpr(self, ctx):
        return self.emit_left_associative(ctx, {
            "*": "mul",
            "/": "div",
            "%": "rem"
        })

    def visitUnaryExpr(self, ctx):
        if ctx.primaryExpr():
            return self.visit(ctx.primaryExpr())

        value_register = self.visit(ctx.unaryExpr())
        text = ctx.getText()

        if text.startswith("!"):
            self.emit(f"xori {value_register}, {value_register}, 1")
            return value_register

        if text.startswith("-"):
            self.emit(f"sub {value_register}, zero, {value_register}")
            return value_register

        return value_register

    def visitPrimaryExpr(self, ctx):
        if ctx.INT_LITERAL():
            register = self.allocate_register()
            self.emit_load_immediate(register, int(ctx.INT_LITERAL().getText(), 10))
            return register

        if ctx.HEX_LITERAL():
            register = self.allocate_register()
            self.emit_load_immediate(register, int(ctx.HEX_LITERAL().getText(), 16))
            return register

        if ctx.BOOL_LITERAL():
            register = self.allocate_register()
            value = 1 if ctx.BOOL_LITERAL().getText() == "vrai" else 0
            self.emit_load_immediate(register, value)
            return register

        if ctx.STRING_LITERAL():
            raise Exception("String literals are not supported in ASM generation yet")

        if ctx.functionCall():
            return self.visit(ctx.functionCall())

        if ctx.indexedAccess():
            return self.visit(ctx.indexedAccess())

        if ctx.ID():
            name = ctx.ID().getText()
            symbol = self.get_symbol(name, ctx.ID().getSymbol().line)

            register = self.allocate_register()

            if symbol["kind"] == "array":
                self.emit_load_immediate(register, symbol["address"])
            else:
                self.emit_load_symbol(register, symbol)

            return register

        if ctx.expr():
            return self.visit(ctx.expr())

        raise Exception(f"Unsupported primary expression '{ctx.getText()}'")

    def visitFunctionCall(self, ctx):
        function_name = ctx.ID().getText()
        function_label = f"FUNC_{function_name}"

        arguments = ctx.args().expr() if ctx.args() else []

        num_args = len(arguments)
        num_arg_regs = len(self.ARG_REGISTERS)
        num_extras = max(0, num_args - num_arg_regs)
        extra_bytes = num_extras * self.WORD_SIZE

        if num_extras > 0:
            self.emit(f"addi sp, sp, -{extra_bytes}")

        for index, arg_ctx in enumerate(arguments):
            value_register = self.visit(arg_ctx)

            if index < num_arg_regs:
                self.emit_move(self.ARG_REGISTERS[index], value_register)
            else:
                stack_offset = (index - num_arg_regs) * self.WORD_SIZE
                self.emit(f"sw {value_register}, {stack_offset}(sp)")

            self.free_register(value_register)

        self.emit_jump_fixup(
            instruction=f"jal ra, {function_label}",
            label_name=function_label,
            jump_type="JAL"
        )

        if num_extras > 0:
            self.emit(f"addi sp, sp, {extra_bytes}")

        result_register = self.allocate_register()
        self.emit_move(result_register, "a0")

        return result_register

    def visitIndexedAccess(self, ctx):
        address_register = self.emit_indexed_address(ctx)

        result_register = self.allocate_register()
        self.emit(f"lw {result_register}, 0({address_register})")

        self.free_register(address_register)

        return result_register

    def emit_indexed_address(self, ctx):
        name = ctx.ID().getText()
        symbol = self.get_symbol(name, ctx.ID().getSymbol().line)

        address_register = self.allocate_register()

        if symbol["kind"] == "array":
            self.emit_load_immediate(address_register, symbol["address"])
        else:
            self.emit_load_symbol(address_register, symbol)

        for expr_ctx in ctx.expr():
            index_register = self.visit(expr_ctx)

            self.emit(f"slli {index_register}, {index_register}, 2")
            self.emit(f"add {address_register}, {address_register}, {index_register}")

            self.free_register(index_register)

        return address_register

    def emit_left_associative(self, ctx, operator_map):
        result_register = self.visit(ctx.getChild(0))

        index = 1

        while index < ctx.getChildCount():
            operator = ctx.getChild(index).getText()
            right_register = self.visit(ctx.getChild(index + 1))

            if operator not in operator_map:
                raise Exception(f"Unsupported operator '{operator}'")

            instruction = operator_map[operator]

            self.emit(f"{instruction} {result_register}, {result_register}, {right_register}")

            self.free_register(right_register)
            index += 2

        return result_register

    def emit_comparison_associative(self, ctx, operator_map):
        result_register = self.visit(ctx.getChild(0))

        index = 1

        while index < ctx.getChildCount():
            operator = ctx.getChild(index).getText()
            right_register = self.visit(ctx.getChild(index + 1))

            if operator not in operator_map:
                raise Exception(f"Unsupported comparison operator '{operator}'")

            result_register = self.emit_comparison(
                left_register=result_register,
                right_register=right_register,
                branch_instruction=operator_map[operator]
            )

            index += 2

        return result_register

    def emit_comparison(self, left_register, right_register, branch_instruction):
        result_register = self.allocate_register()

        true_label = self.new_label("CMP_TRUE")
        end_label = self.new_label("CMP_END")

        self.emit_load_immediate(result_register, 0)

        self.emit_jump_fixup(
            instruction=f"{branch_instruction} {left_register}, {right_register}, {true_label}",
            label_name=true_label,
            jump_type=branch_instruction.upper()
        )

        self.emit_jump_fixup(
            instruction=f"j {end_label}",
            label_name=end_label,
            jump_type="J"
        )

        self.emit_label(true_label)
        self.emit_load_immediate(result_register, 1)

        self.emit_label(end_label)

        self.free_register(left_register)
        self.free_register(right_register)

        return result_register