from src.compiler.generated.LanguageVisitor import LanguageVisitor


class ControlFlowVisitor(LanguageVisitor):
    def __init__(self, label_table, fixup_table):
        super().__init__()

        self.label_table = label_table
        self.fixup_table = fixup_table

        self.instruction_counter = 0
        self.label_counter = 0
        self.loop_stack = []

    def new_label(self, prefix):
        label_name = f"{prefix}_{self.label_counter}"
        self.label_counter += 1
        return label_name

    def emit_instruction(self):
        instruction_index = self.instruction_counter
        self.instruction_counter += 1
        return instruction_index

    def define_label(self, label_name):
        self.label_table.define_label(label_name, self.instruction_counter)

    def visitFunctionDecl(self, ctx):
        function_name = ctx.ID().getText()
        function_label = f"FUNC_{function_name}"

        self.define_label(function_label)

        self.visit(ctx.block())

        self.emit_instruction()

        return None

    def visitIfStmt(self, ctx):
        else_label = self.new_label("IF_ELSE")
        end_label = self.new_label("IF_END")

        self.visit(ctx.expr())

        jump_to_else_index = self.emit_instruction()
        self.fixup_table.add_fixup(
            instruction_index=jump_to_else_index,
            label_name=else_label,
            jump_type="JZ"
        )

        self.visit(ctx.block(0))

        if ctx.SINON():
            jump_to_end_index = self.emit_instruction()
            self.fixup_table.add_fixup(
                instruction_index=jump_to_end_index,
                label_name=end_label,
                jump_type="JMP"
            )

            self.define_label(else_label)
            self.visit(ctx.block(1))
            self.define_label(end_label)
        else:
            self.define_label(else_label)

        return None

    def visitWhileStmt(self, ctx):
        start_label = self.new_label("WHILE_START")
        end_label = self.new_label("WHILE_END")

        self.loop_stack.append({
            "start": start_label,
            "end": end_label
        })

        self.define_label(start_label)

        self.visit(ctx.expr())

        jump_to_end_index = self.emit_instruction()
        self.fixup_table.add_fixup(
            instruction_index=jump_to_end_index,
            label_name=end_label,
            jump_type="JZ"
        )

        self.visit(ctx.block())

        jump_to_start_index = self.emit_instruction()
        self.fixup_table.add_fixup(
            instruction_index=jump_to_start_index,
            label_name=start_label,
            jump_type="JMP"
        )

        self.define_label(end_label)
        self.loop_stack.pop()

        return None

    def visitForStmt(self, ctx):
        start_label = self.new_label("FOR_START")
        update_label = self.new_label("FOR_UPDATE")
        end_label = self.new_label("FOR_END")

        self.loop_stack.append({
            "start": update_label,
            "end": end_label
        })

        if ctx.forInit():
            self.visit(ctx.forInit())

        self.define_label(start_label)

        if ctx.expr():
            self.visit(ctx.expr())

            jump_to_end_index = self.emit_instruction()
            self.fixup_table.add_fixup(
                instruction_index=jump_to_end_index,
                label_name=end_label,
                jump_type="JZ"
            )

        self.visit(ctx.block())

        self.define_label(update_label)

        if ctx.forUpdate():
            self.visit(ctx.forUpdate())

        jump_to_start_index = self.emit_instruction()
        self.fixup_table.add_fixup(
            instruction_index=jump_to_start_index,
            label_name=start_label,
            jump_type="JMP"
        )

        self.define_label(end_label)
        self.loop_stack.pop()

        return None

    def visitContinueStmt(self, ctx):
        line = ctx.SUIVRE().getSymbol().line

        if not self.loop_stack:
            raise Exception(f"Error line {line}: 'suivre' used outside loop")

        continue_label = self.loop_stack[-1]["start"]

        jump_index = self.emit_instruction()
        self.fixup_table.add_fixup(
            instruction_index=jump_index,
            label_name=continue_label,
            jump_type="JMP"
        )

        return None

    def visitVarDecl(self, ctx):
        self.visitChildren(ctx)
        self.emit_instruction()
        return None

    def visitVarDeclNoSemi(self, ctx):
        self.visitChildren(ctx)
        self.emit_instruction()
        return None

    def visitArrayDecl(self, ctx):
        self.visitChildren(ctx)
        self.emit_instruction()
        return None

    def visitAssignment(self, ctx):
        self.visitChildren(ctx)
        self.emit_instruction()
        return None

    def visitAssignmentNoSemi(self, ctx):
        self.visitChildren(ctx)
        self.emit_instruction()
        return None

    def visitIndexedAssignment(self, ctx):
        self.visitChildren(ctx)
        self.emit_instruction()
        return None

    def visitReturnStmt(self, ctx):
        if ctx.expr():
            self.visit(ctx.expr())

        self.emit_instruction()
        return None

    def visitFunctionCall(self, ctx):
        if ctx.args():
            self.visit(ctx.args())

        self.emit_instruction()
        return None