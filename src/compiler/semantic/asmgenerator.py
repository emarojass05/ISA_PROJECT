from src.compiler.generated.LanguageVisitor import LanguageVisitor


class AsmGenerator(LanguageVisitor):
    WORD_SIZE = 4
    IMMED12_MAX = 2047

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
        self.sp_delta = 0

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

    def emit_sp_adjust(self, delta):
        # Signed 12-bit immediate limit prevents direct addi for large frames.
        # Use luhw/llhw + sub/add to handle arbitrary frame sizes.
        if -2048 <= delta <= self.IMMED12_MAX:
            self.emit(f"addi sp, sp, {delta}")
        else:
            tmp = self.allocate_register()
            self.emit_load_immediate(tmp, abs(delta))
            if delta < 0:
                self.emit(f"sub sp, sp, {tmp}")
            else:
                self.emit(f"add sp, sp, {tmp}")
            self.free_register(tmp)

    def emit_sp_load(self, dest_reg, offset):
        # Use dest_reg itself as scratch; lw overwrites it anyway.
        if -2048 <= offset <= self.IMMED12_MAX:
            self.emit(f"lw {dest_reg}, {offset}(sp)")
        else:
            self.emit_load_immediate(dest_reg, offset)
            self.emit(f"add {dest_reg}, sp, {dest_reg}")
            self.emit(f"lw {dest_reg}, 0({dest_reg})")

    def emit_sp_store(self, src_reg, offset):
        if -2048 <= offset <= self.IMMED12_MAX:
            self.emit(f"sw {src_reg}, {offset}(sp)")
        else:
            tmp = self.allocate_register()
            self.emit_load_immediate(tmp, offset)
            self.emit(f"add {tmp}, sp, {tmp}")
            self.emit(f"sw {src_reg}, 0({tmp})")
            self.free_register(tmp)

    def emit_sp_addr(self, dest_reg, offset):
        # Use dest_reg itself as scratch for large offsets.
        if -2048 <= offset <= self.IMMED12_MAX:
            self.emit(f"addi {dest_reg}, sp, {offset}")
        else:
            self.emit_load_immediate(dest_reg, offset)
            self.emit(f"add {dest_reg}, sp, {dest_reg}")

    def emit_move(self, destination, source):
        self.emit(f"addi {destination}, {source}, 0")

    def emit_load_symbol(self, destination, symbol):
        if symbol.get("is_local"):
            # Local variable: sp-relative frame access (no temp register needed)
            offset = symbol["address"] + self.sp_delta
            self.emit_sp_load(destination, offset)
        else:
            # Global variable: load absolute address into temp register, then load
            address_register = self.allocate_register()
            self.emit_load_immediate(address_register, symbol["address"])
            self.emit(f"lw {destination}, 0({address_register})")
            self.free_register(address_register)

    def emit_store_symbol(self, source, symbol):
        if symbol.get("is_local"):
            # Local variable: sp-relative frame store (no temp register needed)
            offset = symbol["address"] + self.sp_delta
            self.emit_sp_store(source, offset)
        else:
            # Global variable: load absolute address into temp register, then store
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

        # Initialize stack pointer to top of data memory (DEPTH=65536 words -> 0x3FFFC)
        # Data memory is separate from instruction memory (Harvard architecture).
        # sp must be set before any function call that uses the stack.
        self.emit("luhw sp, 0x0003")
        self.emit("llhw sp, 0xFFFC")

        # Emit import globals now; accumulate their trees for later function emission
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

        # Emit function bodies from imported files (recursive imports resolved earlier)
        for imported_tree in self.imported_trees:
            for declaration_ctx in imported_tree.declaration():
                if declaration_ctx.functionDecl() is not None:
                    self.visit(declaration_ctx)

        # Emit local function bodies
        for declaration_ctx in ctx.declaration():
            if declaration_ctx.functionDecl() is not None:
                self.visit(declaration_ctx)

        return None

    def visitImportDecl(self, ctx):
        from pathlib import Path
        from src.compiler.main import parse_file

        raw = ctx.STRING_LITERAL().getText()
        path_str = raw[1:-1]

        # Resolve path relative to the current source file
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

        # Guard against circular/duplicate imports
        if real_path in self.visited_imports:
            return None

        self.visited_imports.add(real_path)

        result = parse_file(str(import_path))

        if result is None:
            raise Exception(f"Import error: failed to parse {path_str!r}")

        tree, _ = result

        # Queue tree so its functions are emitted after PROGRAM_END
        self.imported_trees.append(tree)

        # Emit globals of the imported file now (before PROGRAM_END)
        for decl_ctx in tree.declaration():
            if decl_ctx.functionDecl() is None:
                self.visit(decl_ctx)

        # Recurse into transitive imports
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

        # frame_size was calculated by SemanticTableBuilder and stored in the
        # function symbol. It covers: sp+0 (saved ra) + all params + all locals.
        # Minimum frame size is 4 (just the saved ra slot).
        frame_size = function_symbol.get("frame_size", 4)

        self.return_label_stack.append(return_label)

        # Enter scope without resetting: addresses already assigned by semantic pass
        self.symbol_table.enter_scope(function_name, reset_local=False)

        # --- Prologue ---
        # Allocate full frame and save return address at sp+0
        self.emit_sp_adjust(-frame_size)
        self.emit(f"sw ra, 0(sp)")

        # Store incoming arguments into their frame slots.
        # Params 0..5 arrive in a0..a5; extras arrive on the caller's stack above
        # our frame (at sp+frame_size, sp+frame_size+4, ...).
        parameters = function_symbol.get("parameters", [])
        num_arg_regs = len(self.ARG_REGISTERS)

        for index, parameter in enumerate(parameters):
            parameter_symbol = self.get_symbol(parameter["name"])

            if index < num_arg_regs:
                self.emit_store_symbol(self.ARG_REGISTERS[index], parameter_symbol)
            else:
                # Extra arg was pushed by caller before the call; it now lives at
                # sp + frame_size + (index - num_arg_regs) * WORD_SIZE
                extra_offset = frame_size + (index - num_arg_regs) * self.WORD_SIZE
                tmp_register = self.allocate_register()
                self.emit_sp_load(tmp_register, extra_offset)
                self.emit_store_symbol(tmp_register, parameter_symbol)
                self.free_register(tmp_register)

        self.visit(ctx.block())

        # --- Epilogue ---
        self.emit_label(return_label)
        self.emit(f"lw ra, 0(sp)")
        self.emit_sp_adjust(frame_size)
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

                if symbol.get("is_local"):
                    # Local array: store directly via sp-relative offset
                    element_offset = symbol["address"] + index * self.WORD_SIZE
                    self.emit_sp_store(value_register, element_offset)
                else:
                    # Global array: compute absolute address then store
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

    def visitForUpdate(self, ctx):
        # forUpdate : assignmentNoSemi | ID incrementOp
        if ctx.assignmentNoSemi():
            return self.visit(ctx.assignmentNoSemi())

        # ID incrementOp case (e.g. i++, i--)
        name = ctx.ID().getText()
        symbol = self.get_symbol(name, ctx.ID().getSymbol().line)
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
                if symbol.get("is_local"):
                    # Local array: base address = sp + frame_offset
                    self.emit_sp_addr(register, symbol['address'] + self.sp_delta)
                else:
                    # Global array: load absolute address
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
        num_reg_args = min(num_args, num_arg_regs)
        num_extras = max(0, num_args - num_arg_regs)
        extra_bytes = num_extras * self.WORD_SIZE

        # Evaluate register-bound args (first min(num_args, 6)) into temp registers.
        # Peak usage: min(num_args, 6) temp regs - well within the limit.
        reg_arg_regs = []
        for i in range(num_reg_args):
            reg_arg_regs.append(self.visit(arguments[i]))

        # Move register args into calling-convention registers and free the temp regs
        # before evaluating extras. This keeps the temp register pool available for
        # complex extra-arg expressions (indexed accesses, etc.).
        for i, value_register in enumerate(reg_arg_regs):
            self.emit_move(self.ARG_REGISTERS[i], value_register)
            self.free_register(value_register)

        # Allocate stack space for extra args, then evaluate each extra immediately
        # storing it (1 temp reg at a time). sp_delta compensates all sp-relative local
        # variable accesses emitted during these evaluations.
        if num_extras > 0:
            self.emit(f"addi sp, sp, -{extra_bytes}")
            self.sp_delta += extra_bytes
            for i in range(num_extras):
                extra_reg = self.visit(arguments[num_arg_regs + i])
                self.emit(f"sw {extra_reg}, {i * self.WORD_SIZE}(sp)")
                self.free_register(extra_reg)
            self.sp_delta -= extra_bytes

        # Caller-save: snapshot live outer-context regs AFTER args freed.
        # These are temps from the surrounding expression that the callee will clobber.
        caller_saved = sorted(self.used_registers)
        save_bytes = len(caller_saved) * self.WORD_SIZE
        if caller_saved:
            self.emit(f"addi sp, sp, -{save_bytes}")
            for i, reg in enumerate(caller_saved):
                self.emit(f"sw {reg}, {i * self.WORD_SIZE}(sp)")

        self.emit_jump_fixup(
            instruction=f"jal ra, {function_label}",
            label_name=function_label,
            jump_type="JAL"
        )

        if caller_saved:
            for i, reg in enumerate(caller_saved):
                self.emit(f"lw {reg}, {i * self.WORD_SIZE}(sp)")
            self.emit(f"addi sp, sp, {save_bytes}")

        # Clean up extra-arg stack space pushed before the call
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
            if symbol.get("is_local"):
                # Local array: base = sp + frame_offset
                self.emit_sp_addr(address_register, symbol['address'] + self.sp_delta)
            else:
                # Global array: absolute address
                self.emit_load_immediate(address_register, symbol["address"])
        else:
            # Pointer variable: load its value (the address it points to)
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
            jump_type="BRANCH"
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
