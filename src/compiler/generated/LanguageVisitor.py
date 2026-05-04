# Generated from Language.g4 by ANTLR 4.13.2
from antlr4 import *
if "." in __name__:
    from .LanguageParser import LanguageParser
else:
    from LanguageParser import LanguageParser

# This class defines a complete generic visitor for a parse tree produced by LanguageParser.

class LanguageVisitor(ParseTreeVisitor):

    # Visit a parse tree produced by LanguageParser#program.
    def visitProgram(self, ctx:LanguageParser.ProgramContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#declaration.
    def visitDeclaration(self, ctx:LanguageParser.DeclarationContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#importDecl.
    def visitImportDecl(self, ctx:LanguageParser.ImportDeclContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#annotation.
    def visitAnnotation(self, ctx:LanguageParser.AnnotationContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#functionDecl.
    def visitFunctionDecl(self, ctx:LanguageParser.FunctionDeclContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#params.
    def visitParams(self, ctx:LanguageParser.ParamsContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#param.
    def visitParam(self, ctx:LanguageParser.ParamContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#typeSpec.
    def visitTypeSpec(self, ctx:LanguageParser.TypeSpecContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#dType.
    def visitDType(self, ctx:LanguageParser.DTypeContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#pointer.
    def visitPointer(self, ctx:LanguageParser.PointerContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#block.
    def visitBlock(self, ctx:LanguageParser.BlockContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#statement.
    def visitStatement(self, ctx:LanguageParser.StatementContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#varDecl.
    def visitVarDecl(self, ctx:LanguageParser.VarDeclContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#arrayDecl.
    def visitArrayDecl(self, ctx:LanguageParser.ArrayDeclContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#arrayLiteral.
    def visitArrayLiteral(self, ctx:LanguageParser.ArrayLiteralContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#assignment.
    def visitAssignment(self, ctx:LanguageParser.AssignmentContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#indexedAssignment.
    def visitIndexedAssignment(self, ctx:LanguageParser.IndexedAssignmentContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#ifStmt.
    def visitIfStmt(self, ctx:LanguageParser.IfStmtContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#whileStmt.
    def visitWhileStmt(self, ctx:LanguageParser.WhileStmtContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#forStmt.
    def visitForStmt(self, ctx:LanguageParser.ForStmtContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#forInit.
    def visitForInit(self, ctx:LanguageParser.ForInitContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#forUpdate.
    def visitForUpdate(self, ctx:LanguageParser.ForUpdateContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#varDeclNoSemi.
    def visitVarDeclNoSemi(self, ctx:LanguageParser.VarDeclNoSemiContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#assignmentNoSemi.
    def visitAssignmentNoSemi(self, ctx:LanguageParser.AssignmentNoSemiContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#returnStmt.
    def visitReturnStmt(self, ctx:LanguageParser.ReturnStmtContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#continueStmt.
    def visitContinueStmt(self, ctx:LanguageParser.ContinueStmtContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#exprStmt.
    def visitExprStmt(self, ctx:LanguageParser.ExprStmtContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#expr.
    def visitExpr(self, ctx:LanguageParser.ExprContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#logicalOrExpr.
    def visitLogicalOrExpr(self, ctx:LanguageParser.LogicalOrExprContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#logicalAndExpr.
    def visitLogicalAndExpr(self, ctx:LanguageParser.LogicalAndExprContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#bitwiseOrExpr.
    def visitBitwiseOrExpr(self, ctx:LanguageParser.BitwiseOrExprContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#bitwiseXorExpr.
    def visitBitwiseXorExpr(self, ctx:LanguageParser.BitwiseXorExprContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#equalityExpr.
    def visitEqualityExpr(self, ctx:LanguageParser.EqualityExprContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#relationalExpr.
    def visitRelationalExpr(self, ctx:LanguageParser.RelationalExprContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#shiftExpr.
    def visitShiftExpr(self, ctx:LanguageParser.ShiftExprContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#additiveExpr.
    def visitAdditiveExpr(self, ctx:LanguageParser.AdditiveExprContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#multiplicativeExpr.
    def visitMultiplicativeExpr(self, ctx:LanguageParser.MultiplicativeExprContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#unaryExpr.
    def visitUnaryExpr(self, ctx:LanguageParser.UnaryExprContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#primaryExpr.
    def visitPrimaryExpr(self, ctx:LanguageParser.PrimaryExprContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#functionCall.
    def visitFunctionCall(self, ctx:LanguageParser.FunctionCallContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#args.
    def visitArgs(self, ctx:LanguageParser.ArgsContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#indexedAccess.
    def visitIndexedAccess(self, ctx:LanguageParser.IndexedAccessContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by LanguageParser#incrementOp.
    def visitIncrementOp(self, ctx:LanguageParser.IncrementOpContext):
        return self.visitChildren(ctx)



del LanguageParser