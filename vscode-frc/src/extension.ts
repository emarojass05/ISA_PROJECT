import * as vscode from 'vscode';
import * as cp from 'child_process';
import * as fs from 'fs';
import * as path from 'path';

// ——————————————————————< LL(1) Completion >——————————————————————

interface Ll1Prediction {
  kind: string;
  text: string;
}

interface Ll1Result {
  ok: boolean;
  cursor: { line: number; col: number };
  predictions: Ll1Prediction[];
  symbols: Ll1Prediction[];
  partial: string;
  error?: string;
}

function run_ll1_completion(
  document: vscode.TextDocument,
  position: vscode.Position,
  python_path: string,
  script_path: string,
  timeout_ms = 2000,
): Promise<Ll1Result> {
  return new Promise((resolve, reject) => {
    const proc = cp.spawn(python_path, [
      script_path,
      '--line', String(position.line + 1),
      '--col',  String(position.character),
      '--source-stdin',
    ]);

    let stdout = '';
    let stderr = '';
    let done = false;

    const timer = setTimeout(() => {
      if (!done) {
        proc.kill();
        reject(new Error('ll1_completion timeout'));
      }
    }, timeout_ms);

    proc.stdout.on('data', (chunk: Buffer) => { stdout += chunk.toString(); });
    proc.stderr.on('data', (chunk: Buffer) => { stderr += chunk.toString(); });

    proc.on('close', () => {
      done = true;
      clearTimeout(timer);
      try {
        resolve(JSON.parse(stdout) as Ll1Result);
      } catch (_) {
        reject(new Error(`ll1 parse error: ${stderr}`));
      }
    });

    proc.stdin.write(document.getText());
    proc.stdin.end();
  });
}

function resolve_ll1_script(context: vscode.ExtensionContext): string {
  return path.join(context.extensionPath, 'scripts', 'll1_completion.py');
}

// ——————————————————————< Auto-fix >——————————————————————

interface FixSuggestion {
  diagnostic: vscode.Diagnostic;
  fix_kind: 'insert_semicolon' | 'insert_rbrace' | 'insert_rparen';
  edit: { line: number; col: number; text: string };
  label: string;
}

function compute_fixes(
  diagnostics: readonly vscode.Diagnostic[],
  document: vscode.TextDocument,
): FixSuggestion[] {
  const fixes: FixSuggestion[] = [];

  for (const diag of diagnostics) {
    const msg = diag.message;
    const ln  = diag.range.start.line;

    if (/missing ';'|expecting ';'/.test(msg)) {
      const target = Math.max(0, ln - 1);
      const col = document.lineAt(target).text.trimEnd().length;
      fixes.push({
        diagnostic: diag,
        fix_kind:   'insert_semicolon',
        edit:       { line: target, col, text: ';' },
        label:      `Insert ';' at line ${target + 1}`,
      });
    }

    if (/missing '}'/.test(msg)) {
      const target = Math.min(ln, document.lineCount - 1);
      const col    = document.lineAt(target).text.length;
      fixes.push({
        diagnostic: diag,
        fix_kind:   'insert_rbrace',
        edit:       { line: target, col, text: '\n}' },
        label:      `Insert '}' after line ${target + 1}`,
      });
    }

    if (/missing '\)'/.test(msg)) {
      const col = diag.range.start.character;
      fixes.push({
        diagnostic: diag,
        fix_kind:   'insert_rparen',
        edit:       { line: ln, col, text: ')' },
        label:      `Insert ')' at line ${ln + 1}`,
      });
    }
  }

  return fixes;
}

async function apply_fixes(
  fixes: FixSuggestion[],
  document: vscode.TextDocument,
): Promise<void> {
  const we = new vscode.WorkspaceEdit();
  for (const fix of fixes) {
    const pos = new vscode.Position(fix.edit.line, fix.edit.col);
    we.insert(document.uri, pos, fix.edit.text);
  }
  await vscode.workspace.applyEdit(we);
}

// ——————————————————————< Diagnostics >——————————————————————

let diag_counter = 0;

const SYNTAX_RE   = /\[ERR\]\(SYNTAX\) line (\d+):(\d+) (.+)/;
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

// ——————————————————————< Activate >——————————————————————

export function activate(context: vscode.ExtensionContext) {
  const diagnostics = vscode.languages.createDiagnosticCollection('frc');
  const pending     = new Map<string, ReturnType<typeof setTimeout>>();

  // Stores the latest diagnostics per document for CodeActionsProvider and auto-fix
  const last_diagnostics = new Map<string, vscode.Diagnostic[]>();

  function run_diagnostics(document: vscode.TextDocument): void {
    const config        = vscode.workspace.getConfiguration('frc');
    const compiler_path = resolve_compiler_path(config.get('compilerPath', ''));

    if (!compiler_path || document.uri.scheme !== 'file') {
      return;
    }

    const project_root = path.dirname(compiler_path);
    const source_dir   = path.dirname(document.uri.fsPath);
    const tmp_file     = path.join(source_dir, `.frc_diag_${++diag_counter}.fr`);

    fs.writeFileSync(tmp_file, document.getText(), 'utf8');

    const tmp_hex = path.join(
      project_root, 'build', 'bin',
      path.basename(tmp_file, '.fr') + '.hex',
    );

    cp.exec(
      `"${compiler_path}" "${tmp_file}"`,
      { cwd: project_root },
      async (_error, stdout, stderr) => {
        try { fs.unlinkSync(tmp_file); } catch (_) {}
        try { fs.unlinkSync(tmp_hex); } catch (_) {}

        const diags = parse_diagnostics(stdout + stderr, document);
        diagnostics.set(document.uri, diags);
        last_diagnostics.set(document.uri.toString(), diags);

        const auto_fix = vscode.workspace.getConfiguration('frc').get<boolean>('autoFix', false);
        if (auto_fix && diags.length === 1) {
          const fixes = compute_fixes(diags, document);
          if (fixes.length === 1) {
            await apply_fixes(fixes, document);
          }
        }
      },
    );
  }

  function schedule(document: vscode.TextDocument): void {
    const key   = document.uri.toString();
    const timer = pending.get(key);
    if (timer !== undefined) {
      clearTimeout(timer);
    }
    const delay = vscode.workspace.getConfiguration('frc').get<number>('diagnosticsDelay', 800);
    pending.set(key, setTimeout(() => {
      pending.delete(key);
      run_diagnostics(document);
    }, delay));
  }

  // ——— Inline completion provider (ghost text) ———
  const inline_provider = vscode.languages.registerInlineCompletionItemProvider(
    { language: 'frc', scheme: 'file' },
    {
      async provideInlineCompletionItems(document, position, _ctx, _token) {
        const config      = vscode.workspace.getConfiguration('frc');
        const enabled     = config.get<boolean>('completionEnabled', true);
        const python_path = config.get<string>('pythonPath', 'python');

        if (!enabled) {
          return [];
        }

        const script_path = resolve_ll1_script(context);
        let result: Ll1Result;
        try {
          result = await run_ll1_completion(document, position, python_path, script_path);
        } catch (_) {
          return [];
        }

        if (!result.ok) {
          return [];
        }

        const partial   = result.partial ?? '';
        const all_items = [...result.predictions, ...result.symbols];
        const filtered  = all_items.filter(p =>
          p.text.startsWith(partial) && p.text.length > partial.length,
        );

        if (filtered.length === 0) {
          return [];
        }

        const top            = filtered[0];
        const insert_text    = top.text.slice(partial.length);
        const replace_range  = new vscode.Range(position, position);
        return [new vscode.InlineCompletionItem(insert_text, replace_range)];
      },
    },
  );

  // ——— Manual completion command (QuickPick list) ———
  const trigger_completion_cmd = vscode.commands.registerCommand(
    'frc.triggerCompletion',
    async () => {
      const editor = vscode.window.activeTextEditor;
      if (!editor || editor.document.languageId !== 'frc') {
        return;
      }

      const document    = editor.document;
      const position    = editor.selection.active;
      const config      = vscode.workspace.getConfiguration('frc');
      const python_path = config.get<string>('pythonPath', 'python');
      const script_path = resolve_ll1_script(context);

      let result: Ll1Result;
      try {
        result = await run_ll1_completion(document, position, python_path, script_path);
      } catch (_) {
        return;
      }

      if (!result.ok) {
        return;
      }

      const partial   = result.partial ?? '';
      const all_items = [...result.predictions, ...result.symbols];
      const filtered  = all_items.filter(p =>
        p.text.startsWith(partial) && p.text.length > partial.length,
      );

      if (filtered.length === 0) {
        return;
      }

      const picks = filtered.map(p => ({
        label:       p.text,
        description: p.kind,
        insert_text: p.text.slice(partial.length),
      }));

      const chosen = await vscode.window.showQuickPick(picks, {
        placeHolder: 'FRC: select completion',
      });

      if (!chosen) {
        return;
      }

      await editor.edit(builder => {
        builder.insert(position, chosen.insert_text);
      });
    },
  );

  // ——— Code actions provider (quick-fix for syntax errors) ———
  const code_action_provider = vscode.languages.registerCodeActionsProvider(
    { language: 'frc', scheme: 'file' },
    {
      provideCodeActions(document, _range, action_context, _token) {
        const fixes = compute_fixes(action_context.diagnostics, document);
        return fixes.map(fix => {
          const action   = new vscode.CodeAction(fix.label, vscode.CodeActionKind.QuickFix);
          const we       = new vscode.WorkspaceEdit();
          we.insert(document.uri, new vscode.Position(fix.edit.line, fix.edit.col), fix.edit.text);
          action.edit        = we;
          action.diagnostics = [fix.diagnostic];
          action.isPreferred = fix.fix_kind === 'insert_semicolon';
          return action;
        });
      },
    },
    { providedCodeActionKinds: [vscode.CodeActionKind.QuickFix] },
  );

  // ——— Apply all fixes command ———
  const apply_fixes_cmd = vscode.commands.registerCommand(
    'frc.applyFixes',
    async () => {
      const editor = vscode.window.activeTextEditor;
      if (!editor || editor.document.languageId !== 'frc') {
        return;
      }

      const document = editor.document;
      const diags    = last_diagnostics.get(document.uri.toString()) ?? [];
      const fixes    = compute_fixes(diags, document);

      if (fixes.length === 0) {
        vscode.window.showInformationMessage('FRC: no auto-fixable errors found.');
        return;
      }

      await apply_fixes(fixes, document);
    },
  );

  context.subscriptions.push(
    diagnostics,
    inline_provider,
    trigger_completion_cmd,
    code_action_provider,
    apply_fixes_cmd,
    vscode.workspace.onDidOpenTextDocument(doc => {
      if (doc.languageId === 'frc') {
        run_diagnostics(doc);
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
        run_diagnostics(doc);
      }
    }),
    vscode.workspace.onDidChangeTextDocument(e => {
      if (e.document.languageId === 'frc') {
        schedule(e.document);
      }
    }),
    vscode.workspace.onDidCloseTextDocument(doc => {
      diagnostics.delete(doc.uri);
      last_diagnostics.delete(doc.uri.toString());
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
