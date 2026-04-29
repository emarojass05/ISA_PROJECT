grammar Language;

/*
 * Language.g4
 */

/*
 * =========================
 * Parser Rules
 * =========================
 */

program
    : importDecl* declaration* EOF
    ;

declaration
    : functionDecl
    | varDecl
    | arrayDecl
    | annotation
    ;

importDecl
    : INVOQUER STRING_LITERAL SEMICOLON?
    | INVOQUER ID DEPUIS STRING_LITERAL SEMICOLON?
    ;

annotation
    : QUESTION ID
    ;

functionDecl
    : FONC typeSpec ID LPAREN params? RPAREN block
    ;

params
    : param (COMMA param)*
    ;

param
    : typeSpec pointer? ID
    ;

typeSpec
    : LBRACK dType RBRACK
    ;

dType
    : INT
    | BOOL
    | CHAR
    | VOID
    ;

pointer
    : MUL
    ;

block
    : LBRACE statement* RBRACE
    ;

statement
    : varDecl
    | arrayDecl
    | assignment
    | indexedAssignment
    | ifStmt
    | whileStmt
    | forStmt
    | returnStmt
    | continueStmt
    | exprStmt
    | block
    | annotation
    ;

varDecl
    : typeSpec ID ASSIGN expr SEMICOLON
    ;

arrayDecl
    : typeSpec MUL ID LPAREN expr RPAREN SEMICOLON
    | typeSpec MUL ID ASSIGN arrayLiteral SEMICOLON
    ;

arrayLiteral
    : LBRACE (expr (COMMA expr)*)? RBRACE
    ;

assignment
    : ID ASSIGN expr SEMICOLON
    | ID incrementOp SEMICOLON
    ;

indexedAssignment
    : indexedAccess ASSIGN expr SEMICOLON
    ;

ifStmt
    : SI LPAREN expr RPAREN block (SINON block)?
    ;

whileStmt
    : ALORS LPAREN expr RPAREN block
    ;

forStmt
    : POUR LPAREN forInit? SEMICOLON expr? SEMICOLON forUpdate? RPAREN block
    ;

forInit
    : varDeclNoSemi
    | assignmentNoSemi
    ;

forUpdate
    : assignmentNoSemi
    | ID incrementOp
    ;

varDeclNoSemi
    : typeSpec ID ASSIGN expr
    ;

assignmentNoSemi
    : ID ASSIGN expr
    | indexedAccess ASSIGN expr
    ;

returnStmt
    : RET expr? SEMICOLON
    ;

continueStmt
    : SUIVRE SEMICOLON
    ;

exprStmt
    : expr SEMICOLON
    ;

/*
 * Precedent expresions.
 */

expr
    : logicalOrExpr
    ;

logicalOrExpr
    : logicalAndExpr (OR logicalAndExpr)*
    ;

logicalAndExpr
    : bitwiseOrExpr (AND bitwiseOrExpr)*
    ;

bitwiseOrExpr
    : bitwiseXorExpr (BIT_OR bitwiseXorExpr)*
    ;

bitwiseXorExpr
    : equalityExpr (XOR equalityExpr)*
    ;

equalityExpr
    : relationalExpr ((EQ | NEQ) relationalExpr)*
    ;

relationalExpr
    : shiftExpr ((GT | LT | GE | LE) shiftExpr)*
    ;

shiftExpr
    : additiveExpr ((SHL | SHR) additiveExpr)*
    ;

additiveExpr
    : multiplicativeExpr ((PLUS | MINUS) multiplicativeExpr)*
    ;

multiplicativeExpr
    : unaryExpr ((MUL | DIV | MOD) unaryExpr)*
    ;

unaryExpr
    : NOT unaryExpr
    | MINUS unaryExpr
    | primaryExpr
    ;

primaryExpr
    : INT_LITERAL
    | HEX_LITERAL
    | STRING_LITERAL
    | BOOL_LITERAL
    | functionCall
    | indexedAccess
    | ID
    | LPAREN expr RPAREN
    ;

functionCall
    : ID LPAREN args? RPAREN
    ;

args
    : expr (COMMA expr)*
    ;

indexedAccess
    : ID (AT LPAREN expr RPAREN)+
    ;

incrementOp
    : INC
    | DEC
    ;

/*
 * =========================
 * Lexer Rules
 * =========================
 */

/* Keywords */
FONC     : 'fonc';
RET      : 'ret';
SI       : 'si';
SINON    : 'sinon';
ALORS    : 'alors';
POUR     : 'pour';
INVOQUER : 'invoquer';
DEPUIS   : 'depuis';
SUIVRE   : 'suivre';

/* Types */
INT      : 'int';
BOOL     : 'bool';
CHAR      : 'char';
VOID     : 'void';

/* Boolean literals */
BOOL_LITERAL
    : 'vrai'
    | 'faux'
    ;

/* Operators */
PLUS     : '+';
MINUS    : '-';
MUL      : '*';
DIV      : '/';
MOD      : '%';
XOR      : '^';

ASSIGN   : '=';
EQ       : '==';
NEQ      : '!=';

GT       : '>';
LT       : '<';
GE       : '>=';
LE       : '<=';

SHL      : '<<';
SHR      : '>>';

OR       : '||';
AND      : '&&';
NOT      : '!';

BIT_OR   : '|';

INC      : '++';
DEC      : '--';

AT       : '@';
QUESTION : '?';

/* Delimiters */
LPAREN    : '(';
RPAREN    : ')';
LBRACE    : '{';
RBRACE    : '}';
LBRACK    : '[';
RBRACK    : ']';
COLON     : ':';
COMMA     : ',';
SEMICOLON : ';';

/* Literals */
HEX_LITERAL
    : '0x'[0-9a-fA-F]+
    ;

INT_LITERAL
    : [0-9]+
    ;

STRING_LITERAL
    : '"' (~["\\\r\n] | ESCAPE_SEQUENCE)* '"'
    ;

fragment ESCAPE_SEQUENCE
    : '\\' [btnr"\\]
    ;

/* Identifiers */
ID
    : [a-zA-Z_][a-zA-Z0-9_]*
    ;

/* Comments */
BLOCK_COMMENT
    : '$<' .*? '>$' -> skip
    ;

LINE_COMMENT
    : '$' ~[\r\n]* -> skip
    ;

/* Whitespace */
WS
    : [ \t\r\n]+ -> skip
    ;
