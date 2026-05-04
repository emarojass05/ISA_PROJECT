# Generated from Language.g4 by ANTLR 4.13.2
from antlr4 import *
if "." in __name__:
    from .LanguageParser import LanguageParser
else:
    from LanguageParser import LanguageParser

# This class defines a complete listener for a parse tree produced by LanguageParser.
class LanguageListener(ParseTreeListener):

    # Enter a parse tree produced by LanguageParser#program.
    def enterProgram(self, ctx:LanguageParser.ProgramContext):
        pass

    # Exit a parse tree produced by LanguageParser#program.
    def exitProgram(self, ctx:LanguageParser.ProgramContext):
        pass


    # Enter a parse tree produced by LanguageParser#declaration.
    def enterDeclaration(self, ctx:LanguageParser.DeclarationContext):
        pass

    # Exit a parse tree produced by LanguageParser#declaration.
    def exitDeclaration(self, ctx:LanguageParser.DeclarationContext):
        pass


    # Enter a parse tree produced by LanguageParser#importDecl.
    def enterImportDecl(self, ctx:LanguageParser.ImportDeclContext):
        pass

    # Exit a parse tree produced by LanguageParser#importDecl.
    def exitImportDecl(self, ctx:LanguageParser.ImportDeclContext):
        pass


    # Enter a parse tree produced by LanguageParser#annotation.
    def enterAnnotation(self, ctx:LanguageParser.AnnotationContext):
        pass

    # Exit a parse tree produced by LanguageParser#annotation.
    def exitAnnotation(self, ctx:LanguageParser.AnnotationContext):
        pass


    # Enter a parse tree produced by LanguageParser#functionDecl.
    def enterFunctionDecl(self, ctx:LanguageParser.FunctionDeclContext):
        pass

    # Exit a parse tree produced by LanguageParser#functionDecl.
    def exitFunctionDecl(self, ctx:LanguageParser.FunctionDeclContext):
        pass


    # Enter a parse tree produced by LanguageParser#params.
    def enterParams(self, ctx:LanguageParser.ParamsContext):
        pass

    # Exit a parse tree produced by LanguageParser#params.
    def exitParams(self, ctx:LanguageParser.ParamsContext):
        pass


    # Enter a parse tree produced by LanguageParser#param.
    def enterParam(self, ctx:LanguageParser.ParamContext):
        pass

    # Exit a parse tree produced by LanguageParser#param.
    def exitParam(self, ctx:LanguageParser.ParamContext):
        pass


    # Enter a parse tree produced by LanguageParser#typeSpec.
    def enterTypeSpec(self, ctx:LanguageParser.TypeSpecContext):
        pass

    # Exit a parse tree produced by LanguageParser#typeSpec.
    def exitTypeSpec(self, ctx:LanguageParser.TypeSpecContext):
        pass


    # Enter a parse tree produced by LanguageParser#dType.
    def enterDType(self, ctx:LanguageParser.DTypeContext):
        pass

    # Exit a parse tree produced by LanguageParser#dType.
    def exitDType(self, ctx:LanguageParser.DTypeContext):
        pass


    # Enter a parse tree produced by LanguageParser#pointer.
    def enterPointer(self, ctx:LanguageParser.PointerContext):
        pass

    # Exit a parse tree produced by LanguageParser#pointer.
    def exitPointer(self, ctx:LanguageParser.PointerContext):
        pass


    # Enter a parse tree produced by LanguageParser#block.
    def enterBlock(self, ctx:LanguageParser.BlockContext):
        pass

    # Exit a parse tree produced by LanguageParser#block.
    def exitBlock(self, ctx:LanguageParser.BlockContext):
        pass


    # Enter a parse tree produced by LanguageParser#statement.
    def enterStatement(self, ctx:LanguageParser.StatementContext):
        pass

    # Exit a parse tree produced by LanguageParser#statement.
    def exitStatement(self, ctx:LanguageParser.StatementContext):
        pass


    # Enter a parse tree produced by LanguageParser#varDecl.
    def enterVarDecl(self, ctx:LanguageParser.VarDeclContext):
        pass

    # Exit a parse tree produced by LanguageParser#varDecl.
    def exitVarDecl(self, ctx:LanguageParser.VarDeclContext):
        pass


    # Enter a parse tree produced by LanguageParser#arrayDecl.
    def enterArrayDecl(self, ctx:LanguageParser.ArrayDeclContext):
        pass

    # Exit a parse tree produced by LanguageParser#arrayDecl.
    def exitArrayDecl(self, ctx:LanguageParser.ArrayDeclContext):
        pass


    # Enter a parse tree produced by LanguageParser#arrayLiteral.
    def enterArrayLiteral(self, ctx:LanguageParser.ArrayLiteralContext):
        pass

    # Exit a parse tree produced by LanguageParser#arrayLiteral.
    def exitArrayLiteral(self, ctx:LanguageParser.ArrayLiteralContext):
        pass


    # Enter a parse tree produced by LanguageParser#assignment.
    def enterAssignment(self, ctx:LanguageParser.AssignmentContext):
        pass

    # Exit a parse tree produced by LanguageParser#assignment.
    def exitAssignment(self, ctx:LanguageParser.AssignmentContext):
        pass


    # Enter a parse tree produced by LanguageParser#indexedAssignment.
    def enterIndexedAssignment(self, ctx:LanguageParser.IndexedAssignmentContext):
        pass

    # Exit a parse tree produced by LanguageParser#indexedAssignment.
    def exitIndexedAssignment(self, ctx:LanguageParser.IndexedAssignmentContext):
        pass


    # Enter a parse tree produced by LanguageParser#ifStmt.
    def enterIfStmt(self, ctx:LanguageParser.IfStmtContext):
        pass

    # Exit a parse tree produced by LanguageParser#ifStmt.
    def exitIfStmt(self, ctx:LanguageParser.IfStmtContext):
        pass


    # Enter a parse tree produced by LanguageParser#whileStmt.
    def enterWhileStmt(self, ctx:LanguageParser.WhileStmtContext):
        pass

    # Exit a parse tree produced by LanguageParser#whileStmt.
    def exitWhileStmt(self, ctx:LanguageParser.WhileStmtContext):
        pass


    # Enter a parse tree produced by LanguageParser#forStmt.
    def enterForStmt(self, ctx:LanguageParser.ForStmtContext):
        pass

    # Exit a parse tree produced by LanguageParser#forStmt.
    def exitForStmt(self, ctx:LanguageParser.ForStmtContext):
        pass


    # Enter a parse tree produced by LanguageParser#forInit.
    def enterForInit(self, ctx:LanguageParser.ForInitContext):
        pass

    # Exit a parse tree produced by LanguageParser#forInit.
    def exitForInit(self, ctx:LanguageParser.ForInitContext):
        pass


    # Enter a parse tree produced by LanguageParser#forUpdate.
    def enterForUpdate(self, ctx:LanguageParser.ForUpdateContext):
        pass

    # Exit a parse tree produced by LanguageParser#forUpdate.
    def exitForUpdate(self, ctx:LanguageParser.ForUpdateContext):
        pass


    # Enter a parse tree produced by LanguageParser#varDeclNoSemi.
    def enterVarDeclNoSemi(self, ctx:LanguageParser.VarDeclNoSemiContext):
        pass

    # Exit a parse tree produced by LanguageParser#varDeclNoSemi.
    def exitVarDeclNoSemi(self, ctx:LanguageParser.VarDeclNoSemiContext):
        pass


    # Enter a parse tree produced by LanguageParser#assignmentNoSemi.
    def enterAssignmentNoSemi(self, ctx:LanguageParser.AssignmentNoSemiContext):
        pass

    # Exit a parse tree produced by LanguageParser#assignmentNoSemi.
    def exitAssignmentNoSemi(self, ctx:LanguageParser.AssignmentNoSemiContext):
        pass


    # Enter a parse tree produced by LanguageParser#returnStmt.
    def enterReturnStmt(self, ctx:LanguageParser.ReturnStmtContext):
        pass

    # Exit a parse tree produced by LanguageParser#returnStmt.
    def exitReturnStmt(self, ctx:LanguageParser.ReturnStmtContext):
        pass


    # Enter a parse tree produced by LanguageParser#continueStmt.
    def enterContinueStmt(self, ctx:LanguageParser.ContinueStmtContext):
        pass

    # Exit a parse tree produced by LanguageParser#continueStmt.
    def exitContinueStmt(self, ctx:LanguageParser.ContinueStmtContext):
        pass


    # Enter a parse tree produced by LanguageParser#exprStmt.
    def enterExprStmt(self, ctx:LanguageParser.ExprStmtContext):
        pass

    # Exit a parse tree produced by LanguageParser#exprStmt.
    def exitExprStmt(self, ctx:LanguageParser.ExprStmtContext):
        pass


    # Enter a parse tree produced by LanguageParser#expr.
    def enterExpr(self, ctx:LanguageParser.ExprContext):
        pass

    # Exit a parse tree produced by LanguageParser#expr.
    def exitExpr(self, ctx:LanguageParser.ExprContext):
        pass


    # Enter a parse tree produced by LanguageParser#logicalOrExpr.
    def enterLogicalOrExpr(self, ctx:LanguageParser.LogicalOrExprContext):
        pass

    # Exit a parse tree produced by LanguageParser#logicalOrExpr.
    def exitLogicalOrExpr(self, ctx:LanguageParser.LogicalOrExprContext):
        pass


    # Enter a parse tree produced by LanguageParser#logicalAndExpr.
    def enterLogicalAndExpr(self, ctx:LanguageParser.LogicalAndExprContext):
        pass

    # Exit a parse tree produced by LanguageParser#logicalAndExpr.
    def exitLogicalAndExpr(self, ctx:LanguageParser.LogicalAndExprContext):
        pass


    # Enter a parse tree produced by LanguageParser#bitwiseOrExpr.
    def enterBitwiseOrExpr(self, ctx:LanguageParser.BitwiseOrExprContext):
        pass

    # Exit a parse tree produced by LanguageParser#bitwiseOrExpr.
    def exitBitwiseOrExpr(self, ctx:LanguageParser.BitwiseOrExprContext):
        pass


    # Enter a parse tree produced by LanguageParser#bitwiseXorExpr.
    def enterBitwiseXorExpr(self, ctx:LanguageParser.BitwiseXorExprContext):
        pass

    # Exit a parse tree produced by LanguageParser#bitwiseXorExpr.
    def exitBitwiseXorExpr(self, ctx:LanguageParser.BitwiseXorExprContext):
        pass


    # Enter a parse tree produced by LanguageParser#equalityExpr.
    def enterEqualityExpr(self, ctx:LanguageParser.EqualityExprContext):
        pass

    # Exit a parse tree produced by LanguageParser#equalityExpr.
    def exitEqualityExpr(self, ctx:LanguageParser.EqualityExprContext):
        pass


    # Enter a parse tree produced by LanguageParser#relationalExpr.
    def enterRelationalExpr(self, ctx:LanguageParser.RelationalExprContext):
        pass

    # Exit a parse tree produced by LanguageParser#relationalExpr.
    def exitRelationalExpr(self, ctx:LanguageParser.RelationalExprContext):
        pass


    # Enter a parse tree produced by LanguageParser#shiftExpr.
    def enterShiftExpr(self, ctx:LanguageParser.ShiftExprContext):
        pass

    # Exit a parse tree produced by LanguageParser#shiftExpr.
    def exitShiftExpr(self, ctx:LanguageParser.ShiftExprContext):
        pass


    # Enter a parse tree produced by LanguageParser#additiveExpr.
    def enterAdditiveExpr(self, ctx:LanguageParser.AdditiveExprContext):
        pass

    # Exit a parse tree produced by LanguageParser#additiveExpr.
    def exitAdditiveExpr(self, ctx:LanguageParser.AdditiveExprContext):
        pass


    # Enter a parse tree produced by LanguageParser#multiplicativeExpr.
    def enterMultiplicativeExpr(self, ctx:LanguageParser.MultiplicativeExprContext):
        pass

    # Exit a parse tree produced by LanguageParser#multiplicativeExpr.
    def exitMultiplicativeExpr(self, ctx:LanguageParser.MultiplicativeExprContext):
        pass


    # Enter a parse tree produced by LanguageParser#unaryExpr.
    def enterUnaryExpr(self, ctx:LanguageParser.UnaryExprContext):
        pass

    # Exit a parse tree produced by LanguageParser#unaryExpr.
    def exitUnaryExpr(self, ctx:LanguageParser.UnaryExprContext):
        pass


    # Enter a parse tree produced by LanguageParser#primaryExpr.
    def enterPrimaryExpr(self, ctx:LanguageParser.PrimaryExprContext):
        pass

    # Exit a parse tree produced by LanguageParser#primaryExpr.
    def exitPrimaryExpr(self, ctx:LanguageParser.PrimaryExprContext):
        pass


    # Enter a parse tree produced by LanguageParser#functionCall.
    def enterFunctionCall(self, ctx:LanguageParser.FunctionCallContext):
        pass

    # Exit a parse tree produced by LanguageParser#functionCall.
    def exitFunctionCall(self, ctx:LanguageParser.FunctionCallContext):
        pass


    # Enter a parse tree produced by LanguageParser#args.
    def enterArgs(self, ctx:LanguageParser.ArgsContext):
        pass

    # Exit a parse tree produced by LanguageParser#args.
    def exitArgs(self, ctx:LanguageParser.ArgsContext):
        pass


    # Enter a parse tree produced by LanguageParser#indexedAccess.
    def enterIndexedAccess(self, ctx:LanguageParser.IndexedAccessContext):
        pass

    # Exit a parse tree produced by LanguageParser#indexedAccess.
    def exitIndexedAccess(self, ctx:LanguageParser.IndexedAccessContext):
        pass


    # Enter a parse tree produced by LanguageParser#incrementOp.
    def enterIncrementOp(self, ctx:LanguageParser.IncrementOpContext):
        pass

    # Exit a parse tree produced by LanguageParser#incrementOp.
    def exitIncrementOp(self, ctx:LanguageParser.IncrementOpContext):
        pass



del LanguageParser