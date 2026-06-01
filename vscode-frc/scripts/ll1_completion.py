"""
LL(1) completion script for FRC language.
Reads source from stdin, outputs JSON completion suggestions to stdout.

Usage:
    python ll1_completion.py --line L --col C --source-stdin
"""

import sys
import json
import argparse
from dataclasses import dataclass
from typing import Optional

# ——————————————————————< Lexer >——————————————————————

KEYWORDS: dict[str, str] = {
    'fonc': 'FONC', 'ret': 'RET', 'si': 'SI', 'sinon': 'SINON',
    'alors': 'ALORS', 'pour': 'POUR', 'invoquer': 'INVOQUER',
    'depuis': 'DEPUIS', 'suivre': 'SUIVRE',
    'int': 'INT', 'bool': 'BOOL', 'char': 'CHAR', 'void': 'VOID',
    'vrai': 'BOOL_LITERAL', 'faux': 'BOOL_LITERAL',
}


@dataclass
class Token:
    kind: str
    text: str
    # 1-indexed
    line: int
    # 0-indexed
    col: int


def line_col_to_offset(source: str, stop_line: int, stop_col: int) -> int:
    """Convert (1-indexed line, 0-indexed col) to a linear source offset."""
    cur_line = 1
    i = 0
    while i < len(source) and cur_line < stop_line:
        if source[i] == '\n':
            cur_line += 1
        i += 1
    return min(i + stop_col, len(source))


def find_partial(source: str, offset: int) -> tuple[int, str]:
    """Return (word_start_offset, partial_text) for the word at cursor."""
    start = offset
    while start > 0 and (source[start - 1].isalnum() or source[start - 1] == '_'):
        start -= 1
    return start, source[start:offset]


def tokenize(source: str) -> list[Token]:
    """Tokenize a complete (or prefix) source string into a token list ending with EOF."""
    tokens: list[Token] = []
    i = 0
    n = len(source)
    line = 1
    col = 0

    def peek(offset: int = 1) -> str:
        idx = i + offset
        return source[idx] if idx < n else ''

    def advance() -> str:
        nonlocal i, line, col
        ch = source[i]
        i += 1
        if ch == '\n':
            line += 1
            col = 0
        else:
            col += 1
        return ch

    while i < n:
        ch = source[i]
        ln, c = line, col

        if ch in ' \t\r\n':
            advance()
            continue

        # Block comment: $< ... >$
        if ch == '$' and peek() == '<':
            while i < n:
                if source[i:i + 2] == '>$':
                    advance()
                    advance()
                    break
                advance()
            continue

        # Line comment: $ ...
        if ch == '$':
            while i < n and source[i] != '\n':
                advance()
            continue

        if ch == '"':
            text = advance()
            while i < n and source[i] != '"':
                if source[i] == '\\':
                    text += advance()
                text += advance()
            if i < n:
                text += advance()
            tokens.append(Token('STRING_LITERAL', text, ln, c))
            continue

        # Hex literal: 0x...
        if ch == '0' and peek() in 'xX':
            text = advance() + advance()
            while i < n and source[i] in '0123456789abcdefABCDEF':
                text += advance()
            tokens.append(Token('HEX_LITERAL', text, ln, c))
            continue

        if ch.isdigit():
            text = ''
            while i < n and source[i].isdigit():
                text += advance()
            tokens.append(Token('INT_LITERAL', text, ln, c))
            continue

        if ch.isalpha() or ch == '_':
            text = ''
            while i < n and (source[i].isalnum() or source[i] == '_'):
                text += advance()
            kind = KEYWORDS.get(text, 'ID')
            tokens.append(Token(kind, text, ln, c))
            continue

        two = ch + peek()
        two_map: dict[str, str] = {
            '==': 'EQ', '!=': 'NEQ', '>=': 'GE', '<=': 'LE',
            '<<': 'SHL', '>>': 'SHR', '||': 'OR', '&&': 'AND',
            '++': 'INC', '--': 'DEC',
        }
        if two in two_map:
            advance()
            advance()
            tokens.append(Token(two_map[two], two, ln, c))
            continue

        single_map: dict[str, str] = {
            '+': 'PLUS', '-': 'MINUS', '*': 'MUL', '/': 'DIV', '%': 'MOD',
            '^': 'XOR', '=': 'ASSIGN', '>': 'GT', '<': 'LT',
            '!': 'NOT', '|': 'BIT_OR', '@': 'AT', '?': 'QUESTION',
            '(': 'LPAREN', ')': 'RPAREN', '{': 'LBRACE', '}': 'RBRACE',
            '[': 'LBRACK', ']': 'RBRACK', ':': 'COLON', ',': 'COMMA', ';': 'SEMICOLON',
        }
        if ch in single_map:
            advance()
            tokens.append(Token(single_map[ch], ch, ln, c))
            continue

        advance()

    tokens.append(Token('EOF', '', line, col))
    return tokens


# ——————————————————————< LL(1) Parse Table >——————————————————————

# Table: {(NonTerminal, Terminal) -> [symbol, ...]}
# An empty list means epsilon production.

EXPR_FIRST: set[str] = {
    'ID', 'INT_LITERAL', 'HEX_LITERAL', 'STRING_LITERAL',
    'BOOL_LITERAL', 'LPAREN', 'NOT', 'MINUS',
}
STMT_FIRST: set[str] = {
    'LBRACK', 'ID', 'SI', 'ALORS', 'POUR', 'RET', 'SUIVRE', 'LBRACE', 'QUESTION',
} | EXPR_FIRST

TABLE: dict[tuple[str, str], list[str]] = {}


def _add(nt: str, terminals: set[str], production: list[str]) -> None:
    for t in terminals:
        TABLE[(nt, t)] = production


# ——— program ———
_add('program', {'INVOQUER'}, ['importDecl', 'program'])
_add('program', {'FONC', 'LBRACK', 'QUESTION'}, ['declaration', 'program'])
TABLE[('program', 'EOF')] = []

# ——— importDecl ———
TABLE[('importDecl', 'INVOQUER')]        = ['INVOQUER', 'import_body']
TABLE[('import_body', 'STRING_LITERAL')] = ['STRING_LITERAL', 'opt_semi']
TABLE[('import_body', 'ID')]             = ['ID', 'DEPUIS', 'STRING_LITERAL', 'opt_semi']
TABLE[('opt_semi', 'SEMICOLON')]         = ['SEMICOLON']
_add('opt_semi', {'FONC', 'LBRACK', 'QUESTION', 'INVOQUER', 'EOF'}, [])

# ——— declaration ———
TABLE[('declaration', 'FONC')]     = ['functionDecl']
TABLE[('declaration', 'LBRACK')]   = ['typeSpec', 'decl_after_type']
TABLE[('declaration', 'QUESTION')] = ['annotation']

# decl_after_type: varDecl (ID ASSIGN expr ;) vs arrayDecl (MUL ID ...)
TABLE[('decl_after_type', 'ID')]  = ['ID', 'ASSIGN', 'expr', 'SEMICOLON']
TABLE[('decl_after_type', 'MUL')] = ['MUL', 'ID', 'array_body', 'SEMICOLON']
TABLE[('array_body', 'LPAREN')]   = ['LPAREN', 'expr', 'RPAREN']
TABLE[('array_body', 'ASSIGN')]   = ['ASSIGN', 'arrayLiteral']

# ——— annotation ———
TABLE[('annotation', 'QUESTION')] = ['QUESTION', 'ID']

# ——— functionDecl ———
TABLE[('functionDecl', 'FONC')] = [
    'FONC', 'typeSpec', 'ID', 'LPAREN', 'opt_params', 'RPAREN', 'block',
]

# ——— typeSpec / dType ———
TABLE[('typeSpec', 'LBRACK')] = ['LBRACK', 'dType', 'RBRACK']
for _t in ('INT', 'BOOL', 'CHAR', 'VOID'):
    TABLE[('dType', _t)] = [_t]

# ——— params ———
TABLE[('opt_params', 'RPAREN')] = []
TABLE[('opt_params', 'LBRACK')] = ['params']
TABLE[('params', 'LBRACK')]     = ['param', 'params_tail']
TABLE[('params_tail', 'COMMA')]  = ['COMMA', 'param', 'params_tail']
TABLE[('params_tail', 'RPAREN')] = []
TABLE[('param', 'LBRACK')]       = ['typeSpec', 'opt_pointer', 'ID']
TABLE[('opt_pointer', 'MUL')]    = ['MUL']
TABLE[('opt_pointer', 'ID')]     = []

# ——— block ———
TABLE[('block', 'LBRACE')] = ['LBRACE', 'stmt_list', 'RBRACE']

# ——— stmt_list ———
_add('stmt_list', STMT_FIRST, ['statement', 'stmt_list'])
TABLE[('stmt_list', 'RBRACE')] = []

# ——— statement: LBRACK branch (varDecl or arrayDecl) ———
TABLE[('statement', 'LBRACK')]    = ['typeSpec', 'stmt_lbrack_tail']
TABLE[('stmt_lbrack_tail', 'ID')]  = ['ID', 'ASSIGN', 'expr', 'SEMICOLON']
TABLE[('stmt_lbrack_tail', 'MUL')] = ['MUL', 'ID', 'array_body', 'SEMICOLON']

# ——— statement: ID branch (assignment, indexedAssignment, or exprStmt) ———
TABLE[('statement', 'ID')]            = ['ID', 'stmt_id_tail']
TABLE[('stmt_id_tail', 'ASSIGN')]     = ['ASSIGN', 'expr', 'SEMICOLON']
TABLE[('stmt_id_tail', 'INC')]        = ['INC', 'SEMICOLON']
TABLE[('stmt_id_tail', 'DEC')]        = ['DEC', 'SEMICOLON']
TABLE[('stmt_id_tail', 'AT')]         = ['indexed_access_tail', 'ASSIGN', 'expr', 'SEMICOLON']
TABLE[('stmt_id_tail', 'LPAREN')]     = ['LPAREN', 'opt_args', 'RPAREN', 'SEMICOLON']
_expr_bin_ops: set[str] = {
    'PLUS', 'MINUS', 'MUL', 'DIV', 'MOD', 'XOR', 'EQ', 'NEQ',
    'GT', 'LT', 'GE', 'LE', 'SHL', 'SHR', 'OR', 'AND', 'BIT_OR', 'SEMICOLON',
}
for _t in _expr_bin_ops:
    if ('stmt_id_tail', _t) not in TABLE:
        TABLE[('stmt_id_tail', _t)] = ['expr_tail_only', 'SEMICOLON']

# ——— indexed access ———
TABLE[('indexed_access_tail', 'AT')]      = ['AT', 'LPAREN', 'expr', 'RPAREN', 'indexed_access_extra']
TABLE[('indexed_access_extra', 'AT')]     = ['AT', 'LPAREN', 'expr', 'RPAREN', 'indexed_access_extra']
TABLE[('indexed_access_extra', 'ASSIGN')] = []

# ——— if / while / for / return / continue ———
TABLE[('statement', 'SI')]    = ['SI', 'LPAREN', 'expr', 'RPAREN', 'block', 'opt_sinon']
TABLE[('opt_sinon', 'SINON')] = ['SINON', 'block']
_add('opt_sinon', STMT_FIRST | {'RBRACE'}, [])

TABLE[('statement', 'ALORS')] = ['ALORS', 'LPAREN', 'expr', 'RPAREN', 'block']

TABLE[('statement', 'POUR')] = [
    'POUR', 'LPAREN',
    'opt_for_init', 'SEMICOLON',
    'opt_expr',     'SEMICOLON',
    'opt_for_update', 'RPAREN',
    'block',
]
TABLE[('opt_for_init', 'LBRACK')]    = ['typeSpec', 'ID', 'ASSIGN', 'expr']
TABLE[('opt_for_init', 'ID')]        = ['ID', 'ASSIGN', 'expr']
TABLE[('opt_for_init', 'SEMICOLON')] = []
TABLE[('opt_for_update', 'ID')]      = ['ID', 'for_update_tail']
TABLE[('for_update_tail', 'ASSIGN')] = ['ASSIGN', 'expr']
TABLE[('for_update_tail', 'INC')]    = ['INC']
TABLE[('for_update_tail', 'DEC')]    = ['DEC']
TABLE[('opt_for_update', 'RPAREN')]  = []

TABLE[('statement', 'RET')]      = ['RET', 'opt_expr', 'SEMICOLON']
_add('opt_expr', EXPR_FIRST, ['expr'])
TABLE[('opt_expr', 'SEMICOLON')] = []
TABLE[('opt_expr', 'RPAREN')]    = []

TABLE[('statement', 'SUIVRE')]   = ['SUIVRE', 'SEMICOLON']
TABLE[('statement', 'LBRACE')]   = ['block']
TABLE[('statement', 'QUESTION')] = ['annotation']
for _t in (EXPR_FIRST - {'ID'}):
    TABLE[('statement', _t)] = ['expr', 'SEMICOLON']

# ——— arrayLiteral ———
TABLE[('arrayLiteral', 'LBRACE')]   = ['LBRACE', 'array_lit_body', 'RBRACE']
TABLE[('array_lit_body', 'RBRACE')] = []
_add('array_lit_body', EXPR_FIRST, ['expr', 'array_lit_tail'])
TABLE[('array_lit_tail', 'COMMA')]  = ['COMMA', 'expr', 'array_lit_tail']
TABLE[('array_lit_tail', 'RBRACE')] = []

# ——— args ———
TABLE[('opt_args', 'RPAREN')] = []
_add('opt_args', EXPR_FIRST, ['args'])
for _t in EXPR_FIRST:
    TABLE[('args', _t)] = ['expr', 'args_tail']
TABLE[('args_tail', 'COMMA')]  = ['COMMA', 'expr', 'args_tail']
TABLE[('args_tail', 'RPAREN')] = []

# ——— expressions (binary levels as: child op_tail, op_tail -> op child op_tail | epsilon) ———

_FOLLOW_EXPR: set[str] = {'SEMICOLON', 'RPAREN', 'COMMA', 'RBRACK', 'RBRACE', 'EOF'}


def _binary_level(nt: str, ops: set[str], child: str) -> None:
    _add(nt, EXPR_FIRST, [child, f'{nt}_tail'])
    for op in ops:
        TABLE[(f'{nt}_tail', op)] = [op, child, f'{nt}_tail']
    for _t in _FOLLOW_EXPR:
        if (f'{nt}_tail', _t) not in TABLE:
            TABLE[(f'{nt}_tail', _t)] = []


_binary_level('expr',               set(),                     'logicalOrExpr')
_binary_level('logicalOrExpr',      {'OR'},                    'logicalAndExpr')
_binary_level('logicalAndExpr',     {'AND'},                   'bitwiseOrExpr')
_binary_level('bitwiseOrExpr',      {'BIT_OR'},                'bitwiseXorExpr')
_binary_level('bitwiseXorExpr',     {'XOR'},                   'equalityExpr')
_binary_level('equalityExpr',       {'EQ', 'NEQ'},             'relationalExpr')
_binary_level('relationalExpr',     {'GT', 'LT', 'GE', 'LE'}, 'shiftExpr')
_binary_level('shiftExpr',          {'SHL', 'SHR'},            'additiveExpr')
_binary_level('additiveExpr',       {'PLUS', 'MINUS'},         'multiplicativeExpr')
_binary_level('multiplicativeExpr', {'MUL', 'DIV', 'MOD'},    'unaryExpr')

# expr_tail_only: ID already consumed as start of exprStmt; continue with binary ops
TABLE[('expr_tail_only', 'SEMICOLON')] = []
for _op in {'OR', 'AND', 'BIT_OR', 'XOR', 'EQ', 'NEQ', 'GT', 'LT', 'GE', 'LE',
            'SHL', 'SHR', 'PLUS', 'MINUS', 'MUL', 'DIV', 'MOD'}:
    TABLE[('expr_tail_only', _op)] = [_op, 'expr']
TABLE[('expr_tail_only', 'LPAREN')] = ['LPAREN', 'opt_args', 'RPAREN']
TABLE[('expr_tail_only', 'AT')]     = ['indexed_access_tail']

# ——— unaryExpr / primaryExpr ———
TABLE[('unaryExpr', 'NOT')]   = ['NOT', 'unaryExpr']
TABLE[('unaryExpr', 'MINUS')] = ['MINUS', 'unaryExpr']
_add('unaryExpr', EXPR_FIRST - {'NOT', 'MINUS'}, ['primaryExpr'])

TABLE[('primaryExpr', 'INT_LITERAL')]    = ['INT_LITERAL']
TABLE[('primaryExpr', 'HEX_LITERAL')]    = ['HEX_LITERAL']
TABLE[('primaryExpr', 'STRING_LITERAL')] = ['STRING_LITERAL']
TABLE[('primaryExpr', 'BOOL_LITERAL')]   = ['BOOL_LITERAL']
TABLE[('primaryExpr', 'LPAREN')]         = ['LPAREN', 'expr', 'RPAREN']
TABLE[('primaryExpr', 'ID')]             = ['ID', 'primary_id_tail']

# primary_id_tail: function call, indexed access, or bare ID
TABLE[('primary_id_tail', 'LPAREN')] = ['LPAREN', 'opt_args', 'RPAREN']
TABLE[('primary_id_tail', 'AT')]     = ['indexed_access_tail']
_all_ops: set[str] = {
    'OR', 'AND', 'BIT_OR', 'XOR', 'EQ', 'NEQ', 'GT', 'LT', 'GE', 'LE',
    'SHL', 'SHR', 'PLUS', 'MINUS', 'MUL', 'DIV', 'MOD',
    'ASSIGN', 'INC', 'DEC', 'NOT',
}
for _t in _FOLLOW_EXPR | _all_ops:
    if ('primary_id_tail', _t) not in TABLE:
        TABLE[('primary_id_tail', _t)] = []


# ——————————————————————< FIRST set expansion >——————————————————————

_TERMINALS: set[str] = {
    'FONC', 'RET', 'SI', 'SINON', 'ALORS', 'POUR', 'INVOQUER', 'DEPUIS', 'SUIVRE',
    'INT', 'BOOL', 'CHAR', 'VOID', 'BOOL_LITERAL',
    'PLUS', 'MINUS', 'MUL', 'DIV', 'MOD', 'XOR', 'ASSIGN', 'EQ', 'NEQ',
    'GT', 'LT', 'GE', 'LE', 'SHL', 'SHR', 'OR', 'AND', 'NOT', 'BIT_OR', 'INC', 'DEC',
    'AT', 'QUESTION',
    'LPAREN', 'RPAREN', 'LBRACE', 'RBRACE', 'LBRACK', 'RBRACK', 'COLON', 'COMMA', 'SEMICOLON',
    'INT_LITERAL', 'HEX_LITERAL', 'STRING_LITERAL', 'ID', 'EOF',
}


def reachable_terminals(symbol: str, rest_stack: list[str], visited: set[str]) -> set[str]:
    """Return all terminals that can appear as the immediate next token from symbol."""
    if symbol in _TERMINALS:
        return {symbol}
    if symbol in visited:
        return set()
    visited.add(symbol)

    result: set[str] = set()
    for (nt, t) in TABLE:
        if nt == symbol:
            result.add(t)

    # If symbol derives epsilon, also include what follows on the stack
    can_derive_epsilon = any(TABLE.get((symbol, t)) == [] for t in _TERMINALS)
    if can_derive_epsilon and rest_stack:
        result |= reachable_terminals(rest_stack[0], rest_stack[1:], visited)

    return result


# ——————————————————————< LL(1) Simulator >——————————————————————

def simulate(tokens: list[Token]) -> set[str]:
    """Drive LL(1) stack until EOF; return the set of expected terminals at cursor."""
    # '_END' is the sentinel at the bottom; 'program' is the initial top
    stack: list[str] = ['_END', 'program']
    idx = 0
    max_steps = 10_000
    steps = 0

    def lookahead() -> str:
        return tokens[idx].kind if idx < len(tokens) else 'EOF'

    while stack and steps < max_steps:
        steps += 1
        top = stack[-1]
        la = lookahead()

        if la == 'EOF' and top != '_END':
            # Items below top, ordered nearest-first, for epsilon follow expansion
            rest = list(reversed(stack[:-1]))
            return reachable_terminals(top, rest, set())

        if top == '_END':
            break

        if top in _TERMINALS:
            stack.pop()
            if top == la:
                idx += 1
            continue

        production = TABLE.get((top, la))
        if production is not None:
            stack.pop()
            for sym in reversed(production):
                stack.append(sym)
        else:
            stack.pop()

    return set()


# ——————————————————————< Symbol extraction >——————————————————————

def extract_symbols(tokens: list[Token]) -> dict[str, list[str]]:
    """Extract defined function and variable names from the token stream."""
    functions: list[str] = []
    variables: list[str] = []
    seen: set[str] = set()
    n = len(tokens)

    for i, t in enumerate(tokens):
        # functionDecl: FONC LBRACK dType RBRACK ID
        if t.kind == 'FONC' and i + 4 < n:
            if tokens[i + 1].kind == 'LBRACK' and tokens[i + 3].kind == 'RBRACK':
                name = tokens[i + 4]
                if name.kind == 'ID' and name.text not in seen:
                    seen.add(name.text)
                    functions.append(name.text)
        # varDecl / arrayDecl: LBRACK dType RBRACK (MUL?) ID
        if t.kind == 'LBRACK' and i + 2 < n and tokens[i + 2].kind == 'RBRACK':
            j = i + 3
            if j < n and tokens[j].kind == 'MUL':
                j += 1
            if j < n and tokens[j].kind == 'ID' and tokens[j].text not in seen:
                seen.add(tokens[j].text)
                variables.append(tokens[j].text)

    return {'functions': functions, 'variables': variables}


# ——————————————————————< Terminal -> suggestion mapping >——————————————————————

# Maps terminal name -> (suggestion_kind, display_text)
_KIND_MAP: dict[str, tuple[str, str]] = {
    'FONC':      ('keyword', 'fonc'),     'RET':    ('keyword', 'ret'),
    'SI':        ('keyword', 'si'),       'SINON':  ('keyword', 'sinon'),
    'ALORS':     ('keyword', 'alors'),    'POUR':   ('keyword', 'pour'),
    'INVOQUER':  ('keyword', 'invoquer'), 'DEPUIS': ('keyword', 'depuis'),
    'SUIVRE':    ('keyword', 'suivre'),
    'INT':       ('type', 'int'),         'BOOL':   ('type', 'bool'),
    'CHAR':      ('type', 'char'),        'VOID':   ('type', 'void'),
    'BOOL_LITERAL': ('literal', 'vrai'),
    'LBRACK':    ('snippet', '['),
    'LBRACE':    ('snippet', '{'),        'RBRACE': ('snippet', '}'),
    'LPAREN':    ('snippet', '('),        'RPAREN': ('snippet', ')'),
    'SEMICOLON': ('snippet', ';'),        'ASSIGN': ('operator', '='),
    'PLUS':      ('operator', '+'),       'MINUS':  ('operator', '-'),
    'MUL':       ('operator', '*'),       'DIV':    ('operator', '/'),
    'MOD':       ('operator', '%'),       'EQ':     ('operator', '=='),
    'NEQ':       ('operator', '!='),      'GT':     ('operator', '>'),
    'LT':        ('operator', '<'),       'GE':     ('operator', '>='),
    'LE':        ('operator', '<='),      'AND':    ('operator', '&&'),
    'OR':        ('operator', '||'),      'NOT':    ('operator', '!'),
    'INC':       ('operator', '++'),      'DEC':    ('operator', '--'),
    'INT_LITERAL': ('literal', '0'),
}

_PRIORITY: list[str] = ['keyword', 'type', 'literal', 'identifier', 'snippet', 'operator']


def terminal_to_suggestion(kind: str) -> Optional[dict]:
    if kind in ('EOF', '_END', 'ID'):
        return None
    entry = _KIND_MAP.get(kind)
    if not entry:
        return None
    return {'kind': entry[0], 'text': entry[1]}


# ——————————————————————< Entry point >——————————————————————

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--line', type=int, required=True, help='cursor line (1-indexed)')
    parser.add_argument('--col',  type=int, required=True, help='cursor column (0-indexed)')
    parser.add_argument('--source-stdin', action='store_true')
    args = parser.parse_args()

    if not args.source_stdin:
        print(json.dumps({'ok': False, 'error': 'no source provided'}))
        return

    source = sys.stdin.read()

    try:
        cursor_offset = line_col_to_offset(source, args.line, args.col)
        word_start, partial = find_partial(source, cursor_offset)
        tokens = tokenize(source[:word_start])

        predicted = simulate(tokens)
        symbols   = extract_symbols(tokens)

        suggestions: list[dict] = []
        seen_texts: set[str] = set()

        for term in predicted:
            s = terminal_to_suggestion(term)
            if s and s['text'] not in seen_texts:
                seen_texts.add(s['text'])
                suggestions.append(s)

        # BOOL_LITERAL maps to 'vrai'; also expose 'faux' as a separate suggestion
        if any(s['text'] == 'vrai' for s in suggestions) and 'faux' not in seen_texts:
            suggestions.append({'kind': 'literal', 'text': 'faux'})

        suggestions.sort(key=lambda s: (
            _PRIORITY.index(s['kind']) if s['kind'] in _PRIORITY else 99,
            s['text'],
        ))

        print(json.dumps({
            'ok':          True,
            'cursor':      {'line': args.line, 'col': args.col},
            'predictions': suggestions,
            'symbols': (
                [{'kind': 'function', 'text': f} for f in symbols['functions']] +
                [{'kind': 'variable', 'text': v} for v in symbols['variables']]
            ),
            'partial': partial,
        }))

    except Exception as e:
        print(json.dumps({'ok': False, 'error': str(e)}))


if __name__ == '__main__':
    main()
