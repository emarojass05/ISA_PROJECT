#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import time
from pathlib import Path

# ---------------------------------------------------------------------------

PROJECT_ROOT = Path(__file__).resolve().parent.parent
OPTS_DIR     = PROJECT_ROOT / "programs" / "source" / "opts"
BIN_DIR      = PROJECT_ROOT / "build" / "bin"
SIM_DIR      = PROJECT_ROOT / "build" / "sim"
REG_DUMP     = SIM_DIR / "register_dump.txt"
def _find_venv_python() -> Path:
    """Return the best available Python interpreter inside the venv."""
    for name in ("python3.12", "python3.11", "python3.10", "python3", "python"):
        p = PROJECT_ROOT / ".venv" / "bin" / name
        if p.exists():
            return p
    return Path(sys.executable)

VENV_PY = _find_venv_python()

# Return register: a0 = x3 (index 3 in the register file)
RETURN_REG = 3

# Default simulation cycle limit
DEFAULT_MAX_CYCLES = 2000

# ---------------------------------------------------------------------------
# Expected return values by program
#   Key   : .fr filename without extension
#   Value : expected a0 value when main() returns
# ---------------------------------------------------------------------------

EXPECTED: dict[str, int] = {
    # Loop unrolling
    "opt01_unroll_sum":     100,  # 1^3+2^3+3^3+4^3 = 1+8+27+64 = 100
    "opt02_unroll_product": 5,    # fibonacci 4 iters: a=0,b=1 -> b=5
    "opt03_unroll_nested":  32,   # inner fila=8, outer n=4: 4*8=32

    # WAW/WAR renaming
    "opt04_waw_simple":     17,   # x=2->x=6->y=x+1=7->x=x+4=10; x+y=10+7=17
    "opt05_war_simple":     48,   # c=24,d=10,a=14,b=34; a+b=48
    "opt06_waw_war_mixed":  34,   # p=3,q=5,r=15,p=17,q=2,r=34

    # Dead Code Elimination
    "opt07_dce_unused_var": 7,    # live=base+step=4+3=7; dead1/2/3 eliminados
    "opt08_dce_chain":      10,   # result=m+n=4+6=10; waste1..4 eliminados
    "opt09_dce_with_call":  4,    # vivo=4; call helper se mantiene, muerto1/2/3 eliminados

    # Scheduling (conditionals / function chains)
    "opt10_cond_simple":    7,    # suma=8,prod=15; suma>prod? No -> prod-suma=7
    "opt11_cond_nested":    24,   # a=3,b=4,c=5; s=12,p=12; s>10 y p>10 -> s+p=24
    "opt12_func_chain":     32,   # cuadrado(3)=9,cuadrado(4)=16; sc=25; 25+3+4=32
}

LEVELS = [
    ("O0", None),
    ("O1", "--O1"),
    ("O2", "--O2"),
]

# ---------------------------------------------------------------------------

def _py() -> str:
    """Return the Python interpreter to use."""
    if VENV_PY.exists():
        return str(VENV_PY)
    return sys.executable


def compile_fr(source: Path, flag: str | None, out_hex: Path) -> tuple[bool, str]:
    """Compile source.fr with the given flag; write out_hex. Returns (ok, error)."""
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
    """Run 'make sv-cpu-exec PROGRAM=<hex_path> MAX_CYCLES=<n>'. Returns (ok, stderr)."""
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
    """Read x<RETURN_REG> from register_dump.txt; returns signed 32-bit int or None."""
    if not REG_DUMP.exists():
        return None
    text = REG_DUMP.read_text(encoding="utf-8")
    m = re.search(rf"x{RETURN_REG}\s*=\s*([0-9a-fA-F]{{8}})", text)
    if not m:
        return None
    raw = int(m.group(1), 16)
    # Interpret as signed 32-bit integer
    if raw >= 0x8000_0000:
        raw -= 0x1_0000_0000
    return raw


def _bar(pct: float, width: int = 12) -> str:
    filled = int(round(pct * width))
    return "█" * filled + "░" * (width - filled)


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
            print(f"[WARN] Not found: {source}")
            continue

        expected = EXPECTED.get(prog_name)

        for (level_name, flag) in levels:
            done += 1
            label = f"{prog_name}  {level_name}"
            print(f"[{done:>3}/{total}]  {label:<45} ", end="", flush=True)

            t0 = time.perf_counter()

            # --- 1. Compile ---
            out_hex = BIN_DIR / f"{prog_name}_{level_name}.hex"
            ok_compile, err_compile = compile_fr(source, flag, out_hex)
            if not ok_compile:
                elapsed = round((time.perf_counter() - t0) * 1000)
                print(f"COMPILE ERROR ({elapsed}ms)")
                results.append((prog_name, level_name, "COMPILE_ERR", None, expected, False, err_compile[:120]))
                continue

            # --- 2. Simulate ---
            ok_sim, err_sim = run_simulation(out_hex)
            if not ok_sim:
                elapsed = round((time.perf_counter() - t0) * 1000)
                print(f"SIM ERROR ({elapsed}ms)")
                results.append((prog_name, level_name, "SIM_ERR", None, expected, False, err_sim[:120]))
                continue

            # --- 3. Read result ---
            got = read_return_value()
            elapsed = round((time.perf_counter() - t0) * 1000)

            if got is None:
                print(f"NO RESULT ({elapsed}ms)")
                results.append((prog_name, level_name, "NO_RESULT", None, expected, False, "x3 not found in register_dump"))
                continue

            if expected is None:
                print(f"a0={got}  (no expected)  {elapsed}ms")
                results.append((prog_name, level_name, "NO_EXPECTED", got, None, True, ""))
                continue

            ok = (got == expected)
            icon = "OK  " if ok else "FAIL"
            print(f"{icon}  a0={got:>6}  expected={expected:>6}  {elapsed}ms")
            results.append((prog_name, level_name, "OK" if ok else "FAIL", got, expected, ok, ""))

    # ---------------------------------------------------------------------------
    # Summary
    # ---------------------------------------------------------------------------
    passed = sum(1 for *_, ok, _ in results if ok)
    total_r = len(results)
    errors  = total_r - passed

    w = 70
    print()
    print("=" * w)
    print(f"  RESULTS  {passed}/{total_r} passed  ({errors} failures)")
    print("=" * w)

    print(f"  {'Program':<32}  {'Lvl':<3}  {'Status':<12}  {'got':>8}  {'exp':>8}")
    print(f"  {'-'*32}  {'-'*3}  {'-'*12}  {'-'*8}  {'-'*8}")

    for (prog_name, level_name, status, got, exp, ok, note) in results:
        got_s = str(got) if got is not None else "—"
        exp_s = str(exp) if exp is not None else "—"
        icon  = "✔" if ok else "✘"
        print(f"  {icon} {prog_name:<31}  {level_name:<3}  {status:<12}  {got_s:>8}  {exp_s:>8}")
        if note:
            print(f"    └─ {note}")

    print()

    pct = passed / total_r if total_r else 0
    print(f"  [{_bar(pct)}]  {round(pct*100)}% passed")
    print()

    return errors == 0


# ---------------------------------------------------------------------------

def main() -> None:
    ap = argparse.ArgumentParser(
        description="End-to-end verification: compiler + CPU simulator."
    )
    ap.add_argument(
        "filter", nargs="?", default=None,
        help="Program name filter (e.g. opt01, dce, unroll)"
    )
    ap.add_argument("--O0", action="store_true", help="Run O0 level only")
    ap.add_argument("--O1", action="store_true", help="Run O1 level only")
    ap.add_argument("--O2", action="store_true", help="Run O2 level only")
    ap.add_argument(
        "--max-cycles", type=int, default=DEFAULT_MAX_CYCLES,
        help=f"Maximum simulation cycles (default: {DEFAULT_MAX_CYCLES})"
    )
    args = ap.parse_args()

    selected_levels = []
    if args.O0: selected_levels.append(("O0", None))
    if args.O1: selected_levels.append(("O1", "--O1"))
    if args.O2: selected_levels.append(("O2", "--O2"))
    if not selected_levels:
        selected_levels = list(LEVELS)

    all_programs = sorted(EXPECTED.keys())
    if args.filter:
        all_programs = [p for p in all_programs if args.filter in p]
        if not all_programs:
            print(f"[WARN] No programs match filter '{args.filter}'")
            sys.exit(1)

    check = subprocess.run(["which", "iverilog"], capture_output=True)
    if check.returncode != 0:
        print("[ERR] iverilog not found in PATH.")
        print("      Install iverilog (e.g. sudo apt install iverilog)")
        print("      or run this script from an environment where it is available.")
        sys.exit(2)

    print()
    print("=" * 70)
    print("  verify_opts.py — end-to-end verification")
    print(f"  Programs  : {len(all_programs)}")
    print(f"  Levels    : {[l for l,_ in selected_levels]}")
    print(f"  Max cycles: {args.max_cycles}")
    print("=" * 70)
    print()

    ok = run_verification(all_programs, selected_levels)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
    print("=" * 70)
    print()

    ok = run_verification(all_programs, selected_levels)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
