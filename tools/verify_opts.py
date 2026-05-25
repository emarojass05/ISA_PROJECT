#!/usr/bin/env python3
"""
verify_opts.py - Verificacion end-to-end del pipeline compilador + CPU.

Para cada programa opt*.fr:
  1. Compila con O0 / O1 / O2 → .hex  (via src.compiler.main)
  2. Corre la simulacion del CPU       (via `make sv-cpu-exec`)
  3. Lee x3 (a0) de build/sim/register_dump.txt
  4. Compara contra el resultado esperado declarado en este script

Uso:
    python3 tools/verify_opts.py              # todos los programas, todos los niveles
    python3 tools/verify_opts.py opt01        # solo opt01, todos los niveles
    python3 tools/verify_opts.py opt07 --O1  # opt07 solo con O1

Requisitos:
    - iverilog y vvp en el PATH
    - .venv/bin/python3.12 con antlr4 instalado
    - Makefile en la raiz del proyecto con el target sv-cpu-exec

Salida:
    Tabla pass/fail en terminal.
    Codigo de salida 0 si todo pasa, 1 si hay fallos.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import time
from pathlib import Path

# ---------------------------------------------------------------------------
# Configuracion
# ---------------------------------------------------------------------------

PROJECT_ROOT = Path(__file__).resolve().parent.parent
OPTS_DIR     = PROJECT_ROOT / "programs" / "source" / "opts"
BIN_DIR      = PROJECT_ROOT / "build" / "bin"
SIM_DIR      = PROJECT_ROOT / "build" / "sim"
REG_DUMP     = SIM_DIR / "register_dump.txt"
VENV_PY      = PROJECT_ROOT / ".venv" / "bin" / "python3.12"

# Registro de retorno de main() segun la ISA:
#   a0 = x3 (indice 3 en el register file)
RETURN_REG = 3

# MAX_CYCLES por defecto para la simulacion.
# Programas con loops sin desenrollar pueden necesitar mas ciclos.
DEFAULT_MAX_CYCLES = 2000

# ---------------------------------------------------------------------------
# Resultados esperados por programa
#   Clave  : nombre del archivo .fr (sin extension)
#   Valor  : resultado esperado en a0 al terminar main()
# ---------------------------------------------------------------------------

EXPECTED: dict[str, int] = {
    # Loop unrolling
    "opt01_unroll_sum":     10,   # 1+2+3+4 = 10
    "opt02_unroll_product": 24,   # 1*2*3*4 = 24
    "opt03_unroll_nested":  18,   # 6*3 = 18  (loop interno desenrollado)

    # Renombramiento WAW/WAR
    "opt04_waw_simple":     30,   # x = 30; ret x + y - y
    "opt05_war_simple":     15,   # b = a + 5 = 15; ret b
    "opt06_waw_war_mixed":  42,   # resultado final = 42

    # Dead Code Elimination
    "opt07_dce_unused_var": 7,    # util = 3+4 = 7; muerto eliminado
    "opt08_dce_chain":      5,    # resultado = 5; cadena a,b,c eliminada
    "opt09_dce_with_call":  1,    # ret 1; llamada a efecto() ocurre

    # Reordenamiento (condicionales)
    "opt10_cond_simple":    8,    # max(8, 3) = 8
    "opt11_cond_nested":    1,    # clasifica(75) -> aprobado -> ret 1
    "opt12_func_chain":     10,   # f3(2) = 10
}

LEVELS = [
    ("O0", None),
    ("O1", "--O1"),
    ("O2", "--O2"),
]

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _py() -> str:
    """Devuelve el interprete Python a usar."""
    if VENV_PY.exists():
        return str(VENV_PY)
    return sys.executable


def compile_fr(source: Path, flag: str | None, out_hex: Path) -> tuple[bool, str]:
    """
    Compila source.fr con el flag dado y escribe out_hex.
    Retorna (ok, mensaje_de_error).
    """
    cmd = [_py(), "-m", "src.compiler.main", str(source)]
    if flag:
        cmd.append(flag)
    cmd += ["-o", str(out_hex)]

    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        cwd=str(PROJECT_ROOT),
    )
    if result.returncode != 0 or "[ERR]" in result.stdout + result.stderr:
        err = (result.stdout + result.stderr).strip()[-300:]
        return False, err
    return True, ""


def run_simulation(hex_path: Path, max_cycles: int = DEFAULT_MAX_CYCLES) -> tuple[bool, str]:
    """
    Ejecuta `make sv-cpu-exec PROGRAM=<hex_path> MAX_CYCLES=<n>`.
    Retorna (ok, stderr_snippet).
    """
    SIM_DIR.mkdir(parents=True, exist_ok=True)
    cmd = [
        "make", "sv-cpu-exec",
        f"PROGRAM={hex_path}",
        f"MAX_CYCLES={max_cycles}",
    ]
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        cwd=str(PROJECT_ROOT),
    )
    combined = result.stdout + result.stderr
    if result.returncode != 0:
        return False, combined.strip()[-400:]
    if "Register dump written" not in combined and "FINISHED" not in combined:
        return False, combined.strip()[-400:]
    return True, ""


def read_return_value() -> int | None:
    """
    Lee build/sim/register_dump.txt y extrae el valor de x<RETURN_REG>.
    Retorna el entero (con signo, 32 bits) o None si no lo encuentra.
    """
    if not REG_DUMP.exists():
        return None
    text = REG_DUMP.read_text(encoding="utf-8")
    m = re.search(rf"x{RETURN_REG}\s*=\s*([0-9a-fA-F]{{8}})", text)
    if not m:
        return None
    raw = int(m.group(1), 16)
    # Interpretar como entero con signo de 32 bits
    if raw >= 0x8000_0000:
        raw -= 0x1_0000_0000
    return raw


def _bar(pct: float, width: int = 12) -> str:
    filled = int(round(pct * width))
    return "█" * filled + "░" * (width - filled)


# ---------------------------------------------------------------------------
# Runner principal
# ---------------------------------------------------------------------------

def run_verification(
    programs: list[str],
    levels: list[tuple[str, str | None]],
) -> bool:
    BIN_DIR.mkdir(parents=True, exist_ok=True)

    results: list[tuple[str, str, str, int | None, int | None, bool, str]] = []
    # (prog_name, level, status, got, expected, ok, note)

    total = len(programs) * len(levels)
    done  = 0

    for prog_name in programs:
        source = OPTS_DIR / f"{prog_name}.fr"
        if not source.exists():
            print(f"[WARN] No encontrado: {source}")
            continue

        expected = EXPECTED.get(prog_name)

        for (level_name, flag) in levels:
            done += 1
            label = f"{prog_name}  {level_name}"
            print(f"[{done:>3}/{total}]  {label:<45} ", end="", flush=True)

            t0 = time.perf_counter()

            # --- 1. Compilar ---
            out_hex = BIN_DIR / f"{prog_name}_{level_name}.hex"
            ok_compile, err_compile = compile_fr(source, flag, out_hex)
            if not ok_compile:
                elapsed = round((time.perf_counter() - t0) * 1000)
                print(f"COMPILE ERROR ({elapsed}ms)")
                results.append((prog_name, level_name, "COMPILE_ERR", None, expected, False, err_compile[:120]))
                continue

            # --- 2. Simular ---
            ok_sim, err_sim = run_simulation(out_hex)
            if not ok_sim:
                elapsed = round((time.perf_counter() - t0) * 1000)
                print(f"SIM ERROR ({elapsed}ms)")
                results.append((prog_name, level_name, "SIM_ERR", None, expected, False, err_sim[:120]))
                continue

            # --- 3. Leer resultado ---
            got = read_return_value()
            elapsed = round((time.perf_counter() - t0) * 1000)

            if got is None:
                print(f"NO RESULT ({elapsed}ms)")
                results.append((prog_name, level_name, "NO_RESULT", None, expected, False, "x3 no encontrado en register_dump"))
                continue

            if expected is None:
                print(f"a0={got}  (sin expected)  {elapsed}ms")
                results.append((prog_name, level_name, "NO_EXPECTED", got, None, True, ""))
                continue

            ok = (got == expected)
            icon = "OK  " if ok else "FAIL"
            print(f"{icon}  a0={got:>6}  expected={expected:>6}  {elapsed}ms")
            results.append((prog_name, level_name, "OK" if ok else "FAIL", got, expected, ok, ""))

    # ---------------------------------------------------------------------------
    # Resumen
    # ---------------------------------------------------------------------------
    passed = sum(1 for *_, ok, _ in results if ok)
    total_r = len(results)
    errors  = total_r - passed

    w = 70
    print()
    print("=" * w)
    print(f"  RESULTADOS  {passed}/{total_r} pasaron  ({errors} fallos)")
    print("=" * w)

    # Encabezado de tabla
    print(f"  {'Programa':<32}  {'Niv':<3}  {'Estado':<12}  {'got':>8}  {'exp':>8}")
    print(f"  {'-'*32}  {'-'*3}  {'-'*12}  {'-'*8}  {'-'*8}")

    for (prog_name, level_name, status, got, exp, ok, note) in results:
        got_s = str(got) if got is not None else "—"
        exp_s = str(exp) if exp is not None else "—"
        icon  = "✔" if ok else "✘"
        print(f"  {icon} {prog_name:<31}  {level_name:<3}  {status:<12}  {got_s:>8}  {exp_s:>8}")
        if note:
            print(f"    └─ {note}")

    print()

    # Barra de progreso visual
    pct = passed / total_r if total_r else 0
    print(f"  [{_bar(pct)}]  {round(pct*100)}% exitoso")
    print()

    return errors == 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    ap = argparse.ArgumentParser(
        description="Verificacion end-to-end: compilador + simulador CPU."
    )
    ap.add_argument(
        "filter", nargs="?", default=None,
        help="Filtro de nombre de programa (ej: opt01, dce, unroll)"
    )
    ap.add_argument("--O0", action="store_true", help="Solo nivel O0")
    ap.add_argument("--O1", action="store_true", help="Solo nivel O1")
    ap.add_argument("--O2", action="store_true", help="Solo nivel O2")
    ap.add_argument(
        "--max-cycles", type=int, default=DEFAULT_MAX_CYCLES,
        help=f"Ciclos maximos de simulacion (default: {DEFAULT_MAX_CYCLES})"
    )
    args = ap.parse_args()

    # Niveles a correr
    selected_levels = []
    if args.O0: selected_levels.append(("O0", None))
    if args.O1: selected_levels.append(("O1", "--O1"))
    if args.O2: selected_levels.append(("O2", "--O2"))
    if not selected_levels:
        selected_levels = list(LEVELS)

    # Programas a correr
    all_programs = sorted(EXPECTED.keys())
    if args.filter:
        all_programs = [p for p in all_programs if args.filter in p]
        if not all_programs:
            print(f"[WARN] Ningun programa coincide con el filtro '{args.filter}'")
            sys.exit(1)

    # Verificar que iverilog este disponible
    check = subprocess.run(["which", "iverilog"], capture_output=True)
    if check.returncode != 0:
        print("[ERR] iverilog no encontrado en PATH.")
        print("      Instala iverilog (ej: sudo apt install iverilog)")
        print("      o ejecuta este script desde el entorno donde este disponible.")
        sys.exit(2)

    print()
    print("=" * 70)
    print("  verify_opts.py — verificacion end-to-end")
    print(f"  Programas : {len(all_programs)}")
    print(f"  Niveles   : {[l for l,_ in selected_levels]}")
    print(f"  Max ciclos: {args.max_cycles}")
    print("=" * 70)
    print()

    ok = run_verification(all_programs, selected_levels)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
