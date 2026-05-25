"""
metrics.py - Generador de metricas CSV para el pipeline de optimizacion.

Uso (desde la raiz del proyecto, con el venv activado):
    python3 tools/metrics.py [--out build/metrics.csv] [--python python3]

Estrategia
----------
Llama al compilador via subprocess para cada combinacion (programa x nivel),
parsea la seccion "OPTIMIZER" del stdout y construye el CSV.
No importa nada del compilador directamente, por lo que funciona con
cualquier Python que tenga el proyecto en el PYTHONPATH.

Columnas del CSV
----------------
program, level, instrs_before, instrs_after, instrs_saved,
rename_vars, dce_removed, unroll_loops, unroll_added,
sched_moved, sched_blocks, elapsed_ms, code_bytes
"""

from __future__ import annotations

import argparse
import csv
import re
import subprocess
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
OPTS_DIR     = PROJECT_ROOT / "programs" / "source" / "opts"
BUILD_DIR    = PROJECT_ROOT / "build"
DEFAULT_OUT  = BUILD_DIR / "metrics.csv"

CSV_FIELDS = [
    "program",
    "level",
    "instrs_before",
    "instrs_after",
    "instrs_saved",
    "code_bytes",
    "rename_vars",
    "dce_removed",
    "unroll_loops",
    "unroll_added",
    "sched_moved",
    "sched_blocks",
    "elapsed_ms",
]


# ---------------------------------------------------------------------------
# Parser del bloque OPTIMIZER en la salida del compilador
# ---------------------------------------------------------------------------

def _parse_optimizer_block(text: str) -> dict:
    """
    Extrae las metricas del bloque:
        ========== OPTIMIZER (Ox) ==========
        Optimization level : O1
        Instructions before: 45
        ...
    Retorna un dict con las claves del CSV (sin program/level).
    """
    def _int(pattern: str, default: int = 0) -> int:
        m = re.search(pattern, text)
        return int(m.group(1)) if m else default

    def _float(pattern: str, default: float = 0.0) -> float:
        m = re.search(pattern, text)
        return float(m.group(1)) if m else default

    return {
        "instrs_before": _int(r"Instructions before\s*:\s*(\d+)"),
        "instrs_after":  _int(r"Instructions after\s*:\s*(\d+)"),
        "instrs_saved":  _int(r"Instructions saved\s*:\s*(-?\d+)"),
        "rename_vars":   _int(r"\[rename\] vars created\s*:\s*(\d+)"),
        "dce_removed":   _int(r"\[dce\]\s+instrs removed\s*:\s*(\d+)"),
        "unroll_loops":  _int(r"\[unroll\] loops expanded\s*:\s*(\d+)"),
        "unroll_added":  _int(r"\[unroll\] instrs added\s*:\s*(\d+)"),
        "sched_moved":   _int(r"\[sched\]\s+instrs moved\s*:\s*(\d+)"),
        "sched_blocks":  _int(r"\[sched\]\s+blocks changed\s*:\s*(\d+)"),
        "elapsed_ms":    round(_float(r"Pipeline time\s*:\s*([\d.]+)\s*ms"), 3),
    }


def _add_code_bytes(row: dict) -> dict:
    """Agrega code_bytes = instrs_after * 4 (cada instruccion ocupa 4 bytes)."""
    after = row.get("instrs_after", 0)
    row["code_bytes"] = after * 4 if isinstance(after, int) else "ERROR"
    return row


# ---------------------------------------------------------------------------
# Ejecucion del compilador para un programa y nivel
# ---------------------------------------------------------------------------

def _get_instrs_before(python_cmd: str, source: Path) -> int | str:
    """
    Obtiene el numero de instrucciones IR antes de cualquier optimizacion.
    Lo hace corriendo --O1 y leyendo 'Instructions before' del bloque OPTIMIZER.
    Esto garantiza que el baseline de O0 usa el mismo contador que O1/O2.
    """
    cmd = [python_cmd, "-m", "src.compiler.main", str(source), "--O1"]
    result = subprocess.run(
        cmd, capture_output=True, text=True, cwd=str(PROJECT_ROOT)
    )
    output = result.stdout
    if "OPTIMIZER" not in output:
        return f"no OPTIMIZER block: {(output + result.stderr).strip()[:200]}"
    m = re.search(r"Instructions before\s*:\s*(\d+)", output)
    return int(m.group(1)) if m else 0


def _run_level(python_cmd: str, source: Path, flag: str | None) -> dict | str:
    """
    Llama a python3 -m src.compiler.main <source> [--O1|--O2]
    y retorna el dict de metricas, o un mensaje de error.

    Para O0 el baseline se obtiene del 'instrs_before' reportado por --O1,
    que usa el mismo contador interno que O1/O2 (len(func.body)).
    """
    if flag is None:
        # O0: sin optimizacion -> instrs_before == instrs_after, demas metricas = 0
        n_or_err = _get_instrs_before(python_cmd, source)
        if isinstance(n_or_err, str):
            return n_or_err
        n = n_or_err
        return {
            "instrs_before": n,
            "instrs_after":  n,
            "instrs_saved":  0,
            "rename_vars":   0,
            "dce_removed":   0,
            "unroll_loops":  0,
            "unroll_added":  0,
            "sched_moved":   0,
            "sched_blocks":  0,
            "elapsed_ms":    0.0,
        }
    else:
        # O1 / O2
        cmd = [python_cmd, "-m", "src.compiler.main", str(source), flag]
        result = subprocess.run(
            cmd, capture_output=True, text=True, cwd=str(PROJECT_ROOT)
        )
        output = result.stdout
        if "OPTIMIZER" not in output:
            err = (result.stdout + result.stderr).strip()[:300]
            return f"no OPTIMIZER block in output: {err}"
        # Extraer solo la seccion OPTIMIZER
        start = output.find("========== OPTIMIZER")
        opt_block = output[start:]
        return _parse_optimizer_block(opt_block)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    ap = argparse.ArgumentParser(
        description="Genera metricas CSV del pipeline de optimizacion."
    )
    ap.add_argument(
        "--out", default=str(DEFAULT_OUT),
        help="Ruta del CSV de salida (default: build/metrics.csv)"
    )
    ap.add_argument(
        "--python", default="python3",
        help="Interprete Python a usar (default: python3)"
    )
    args = ap.parse_args()

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    programs = sorted(OPTS_DIR.glob("*.fr"))
    if not programs:
        print(f"[WARN] No se encontraron .fr en {OPTS_DIR}", file=sys.stderr)
        sys.exit(1)

    levels = [
        ("O0", None),
        ("O1", "--O1"),
        ("O2", "--O2"),
    ]

    rows   = []
    errors = 0
    total  = len(programs) * len(levels)
    done   = 0

    for prog in programs:
        for (level_name, flag) in levels:
            done += 1
            label = f"{prog.name:30s}  {level_name}"
            print(f"[{done:>3}/{total}] {label} ... ", end="", flush=True)

            result = _run_level(args.python, prog, flag)

            if isinstance(result, str):
                errors += 1
                print(f"ERROR: {result}")
                rows.append({f: "ERROR" for f in CSV_FIELDS} | {
                    "program": prog.name, "level": level_name,
                })
            else:
                row = {"program": prog.name, "level": level_name} | result
                _add_code_bytes(row)
                rows.append(row)
                print(
                    f"OK  "
                    f"before={result['instrs_before']:3d}  "
                    f"after={result['instrs_after']:3d}  "
                    f"saved={result['instrs_saved']:3d}"
                )

    # Escribir CSV
    with open(out_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=CSV_FIELDS)
        writer.writeheader()
        writer.writerows(rows)

    print(f"\nCSV guardado en : {out_path}")
    print(f"Programas        : {len(programs)}")
    print(f"Filas generadas  : {len(rows)}")
    if errors:
        print(f"Errores          : {errors}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
