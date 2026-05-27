import * as vscode from 'vscode';
import * as cp from 'child_process';
import * as fs from 'fs';
import * as path from 'path';

// [COMPLETION]

const KEYWORDS: vscode.CompletionItem[] = [
  'fonc', 'ret', 'si', 'sinon', 'alors', 'pour',
  'invoquer', 'depuis', 'suivre',
].map(kw => {
  const item = new vscode.CompletionItem(kw, vscode.CompletionItemKind.Keyword);
  item.detail = 'keyword';
  return item;
});

const TYPES: vscode.CompletionItem[] = [
  'int', 'bool', 'char', 'void',
].map(t => {
  const item = new vscode.CompletionItem(t, vscode.CompletionItemKind.TypeParameter);
  item.detail = 'type';
  return item;
});

const BOOLEANS: vscode.CompletionItem[] = [
  'vrai', 'faux',
].map(b => {
  const item = new vscode.CompletionItem(b, vscode.CompletionItemKind.Constant);
  item.detail = 'boolean literal';
  return item;
});

function make_snippet(
  label: string,
  snippet: string,
  detail: string,
): vscode.CompletionItem {
  const item = new vscode.CompletionItem(label, vscode.CompletionItemKind.Snippet);
  item.insertText = new vscode.SnippetString(snippet);
  item.detail = detail;
  return item;
}

const SNIPPETS: vscode.CompletionItem[] = [
  make_snippet(
    'fonc',
    'fonc [${1|int,bool,char,void|}] ${2:name}(${3}) {\n\t$0\n}',
    'function declaration',
  ),
  make_snippet(
    'si',
    'si (${1:condition}) {\n\t$0\n}',
    'if statement',
  ),
  make_snippet(
    'si/sinon',
    'si (${1:condition}) {\n\t$2\n} sinon {\n\t$0\n}',
    'if/else statement',
  ),
  make_snippet(
    'alors',
    'alors (${1:condition}) {\n\t$0\n}',
    'while loop',
  ),
  make_snippet(
    'pour',
    'pour ([int] ${1:i} = ${2:0}; ${1:i} ${3:<} ${4:n}; ${1:i}++) {\n\t$0\n}',
    'for loop',
  ),
  make_snippet(
    'invoquer',
    'invoquer "${1:module}";',
    'import module',
  ),
  make_snippet(
    'invoquer depuis',
    'invoquer ${1:symbol} depuis "${2:module}";',
    'import symbol from module',
  ),
  make_snippet(
    'ret',
    'ret ${1:value};',
    'return statement',
  ),
];

function dynamic_symbols(document: vscode.TextDocument): vscode.CompletionItem[] {
  const text = document.getText();
  const seen = new Set<string>();
  const items: vscode.CompletionItem[] = [];

  for (const m of text.matchAll(/\bfonc\s+\[\w+\]\s+([a-zA-Z_]\w*)\s*\(/g)) {
    const name = m[1];
    if (!seen.has(name)) {
      seen.add(name);
      const item = new vscode.CompletionItem(name, vscode.CompletionItemKind.Function);
      item.detail = 'defined function';
      items.push(item);
    }
  }

  for (const m of text.matchAll(/\[\w+\]\s*\*?\s*([a-zA-Z_]\w*)\s*[=(]/g)) {
    const name = m[1];
    if (!seen.has(name)) {
      seen.add(name);
      const item = new vscode.CompletionItem(name, vscode.CompletionItemKind.Variable);
      item.detail = 'defined variable';
      items.push(item);
    }
  }

  return items;
}

class FrcCompletionProvider implements vscode.CompletionItemProvider {
  provideCompletionItems(
    document: vscode.TextDocument,
    position: vscode.Position,
  ): vscode.CompletionItem[] {
    const line_text = document.lineAt(position).text;
    const prefix = line_text.slice(0, position.character);
    // (?!<) distinguishes line comment ($) from block comment opener ($<)
    if (/\$(?!<)/.test(prefix)) {
      return [];
    }

    return [
      ...KEYWORDS,
      ...TYPES,
      ...BOOLEANS,
      ...SNIPPETS,
      ...dynamic_symbols(document),
    ];
  }
}

// [DIAGNOSTICS]

let diag_counter = 0;

const SYNTAX_RE  = /\[ERR\]\(SYNTAX\) line (\d+):(\d+) (.+)/;
const SEMANTIC_RE = /\[ERR\]\(COMPILER\) Error line (\d+): (.+)/;
const GENERIC_RE  = /\[ERR\]\([A-Z_]+\) (.+)/;

function parse_diagnostics(
  output: string,
  document: vscode.TextDocument,
): vscode.Diagnostic[] {
  const diagnostics: vscode.Diagnostic[] = [];

  for (const raw_line of output.split('\n')) {
    const syntax = raw_line.match(SYNTAX_RE);
    if (syntax) {
      const ln        = Math.min(parseInt(syntax[1], 10) - 1, document.lineCount - 1);
      const col       = parseInt(syntax[2], 10);
      const line_text = document.lineAt(ln).text;
      const token     = line_text.slice(col).match(/^\S+/);
      const col_end   = col + (token ? token[0].length : 1);
      const range     = new vscode.Range(ln, col, ln, col_end);
      diagnostics.push(new vscode.Diagnostic(range, syntax[3], vscode.DiagnosticSeverity.Error));
      continue;
    }

    const semantic = raw_line.match(SEMANTIC_RE);
    if (semantic) {
      const ln  = Math.min(parseInt(semantic[1], 10) - 1, document.lineCount - 1);
      const end = document.lineAt(ln).text.length;
      const range = new vscode.Range(ln, 0, ln, end);
      diagnostics.push(new vscode.Diagnostic(range, semantic[2], vscode.DiagnosticSeverity.Error));
      continue;
    }

    const generic = raw_line.match(GENERIC_RE);
    if (generic) {
      const range = new vscode.Range(0, 0, 0, document.lineAt(0).text.length);
      diagnostics.push(new vscode.Diagnostic(range, generic[1], vscode.DiagnosticSeverity.Error));
    }
  }

  return diagnostics;
}

function resolve_compiler_path(configured: string): string {
  if (configured) {
    return configured;
  }
  for (const folder of vscode.workspace.workspaceFolders ?? []) {
    const candidate = path.join(folder.uri.fsPath, 'frc');
    if (fs.existsSync(candidate)) {
      return candidate;
    }
  }
  return '';
}

function run_diagnostics(
  document: vscode.TextDocument,
  collection: vscode.DiagnosticCollection,
): void {
  const config = vscode.workspace.getConfiguration('frc');
  const compiler_path = resolve_compiler_path(config.get('compilerPath', ''));

  if (!compiler_path || document.uri.scheme !== 'file') {
    return;
  }

  const project_root = path.dirname(compiler_path);
  const source_dir   = path.dirname(document.uri.fsPath);
  const tmp_file     = path.join(source_dir, `.frc_diag_${++diag_counter}.fr`);

  fs.writeFileSync(tmp_file, document.getText(), 'utf8');

  const tmp_hex = path.join(project_root, 'build', 'bin', path.basename(tmp_file, '.fr') + '.hex');

  cp.exec(
    `"${compiler_path}" "${tmp_file}"`,
    { cwd: project_root },
    (_error, stdout, stderr) => {
      try { fs.unlinkSync(tmp_file); } catch (_) {}
      try { fs.unlinkSync(tmp_hex); } catch (_) {}
      const diagnostics = parse_diagnostics(stdout + stderr, document);
      collection.set(document.uri, diagnostics);
    },
  );
}

// [ACTIVATE]

export function activate(context: vscode.ExtensionContext) {
  const completion_provider = vscode.languages.registerCompletionItemProvider(
    { language: 'frc', scheme: 'file' },
    new FrcCompletionProvider(),
    ...'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_["'.split(''),
  );

  const diagnostics = vscode.languages.createDiagnosticCollection('frc');
  const pending     = new Map<string, ReturnType<typeof setTimeout>>();

  function schedule(document: vscode.TextDocument): void {
    const key   = document.uri.toString();
    const timer = pending.get(key);
    if (timer !== undefined) {
      clearTimeout(timer);
    }
    const delay = vscode.workspace.getConfiguration('frc').get<number>('diagnosticsDelay', 800);
    pending.set(key, setTimeout(() => {
      pending.delete(key);
      run_diagnostics(document, diagnostics);
    }, delay));
  }

  context.subscriptions.push(
    completion_provider,
    diagnostics,
    vscode.workspace.onDidOpenTextDocument(doc => {
      if (doc.languageId === 'frc') {
        run_diagnostics(doc, diagnostics);
      }
    }),
    vscode.workspace.onDidSaveTextDocument(doc => {
      if (doc.languageId === 'frc') {
        const key   = doc.uri.toString();
        const timer = pending.get(key);
        if (timer !== undefined) {
          clearTimeout(timer);
          pending.delete(key);
        }
        run_diagnostics(doc, diagnostics);
      }
    }),
    vscode.workspace.onDidChangeTextDocument(e => {
      if (e.document.languageId === 'frc') {
        schedule(e.document);
      }
    }),
    vscode.workspace.onDidCloseTextDocument(doc => {
      diagnostics.delete(doc.uri);
      const key   = doc.uri.toString();
      const timer = pending.get(key);
      if (timer !== undefined) {
        clearTimeout(timer);
        pending.delete(key);
      }
    }),
  );
}

export function deactivate() {}
