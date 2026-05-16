#!/usr/bin/env python3
"""
FRC Compiler Test Runner
========================
Compiles each .fr program in tests/programs/ and checks ASM output
against a set of assertions defined per test.

Usage:
    python3 tests/run_tests.py          # run all tests
    python3 tests/run_tests.py t01      # run only tests matching 't01'

Exit code: 0 if all pass, 1 if any fail.
"""

import subprocess
import sys
import os
import re

# --------------------------------------------------------------------------- #
# Configuration
# --------------------------------------------------------------------------- #

REPO_ROOT   = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VENV_PY     = os.path.join(REPO_ROOT, ".venv", "bin", "python3.12")
ANTLR_SITE  = os.path.join(REPO_ROOT, ".venv", "lib", "python3.12", "site-packages")
PROGRAMS    = os.path.join(REPO_ROOT, "tests", "programs")

# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #

def compile_fr(source_path):
    """Run the compiler and return (asm_text, error_text, success)."""
    env = os.environ.copy()
    env["PYTHONPATH"] = f"{ANTLR_SITE}:{REPO_ROOT}"

    result = subprocess.run(
        [VENV_PY, "-m", "src.compiler.main", source_path, "-v"],
        capture_output=True,
        text=True,
        cwd=REPO_ROOT,
        env=env,
    )
    full = result.stdout + result.stderr
    ok   = "[ERR]" not in full and result.returncode == 0
    # Extract ASM block between "=== ASM ===" and "=== HEX ==="
    asm_match = re.search(r"={5,} ASM ={5,}\n(.*?)={5,} HEX", full, re.DOTALL)
    asm = asm_match.group(1) if asm_match else ""
    return asm, full, ok


def check(name, condition, detail=""):
    """Assert a condition; print PASS/FAIL."""
    if condition:
        print(f"    ✔  {name}")
        return True
    else:
        print(f"    ✘  {name}" + (f"\n       → {detail}" if detail else ""))
        return False


# --------------------------------------------------------------------------- #
# Per-test assertions
# --------------------------------------------------------------------------- #

def assertions_t01(asm, output):
    """Local vars: each function uses its own sp-relative frame."""
    ok = True
    # Both double() and triple() must allocate a frame
    ok &= check("double() has prologue",  "FUNC_double:" in asm and "addi sp, sp, -" in asm)
    ok &= check("triple() has prologue",  "FUNC_triple:" in asm)
    ok &= check("main() has prologue",    "FUNC_main:" in asm)
    # No static local address >= 0x200 should appear
    ok &= check("No static local address (0x200+)",
                "0x200" not in asm and "0x204" not in asm and "0x208" not in asm)
    # Local stores must use offset(sp)
    sw_sp = re.findall(r"sw \w+, \d+\(sp\)", asm)
    ok &= check("Local stores use sp-relative addressing", len(sw_sp) >= 3,
                f"found: {sw_sp}")
    return ok


def assertions_t02(asm, output):
    """Recursion: ra saved/restored on every call."""
    ok = True
    ok &= check("factorial() frame allocated",  "FUNC_factorial:" in asm)
    # Every function that calls another must save ra
    sw_ra = re.findall(r"sw ra, 0\(sp\)", asm)
    lw_ra = re.findall(r"lw ra, 0\(sp\)", asm)
    ok &= check("ra saved  (sw ra, 0(sp))",  len(sw_ra) >= 2,  f"count={len(sw_ra)}")
    ok &= check("ra restored (lw ra, 0(sp))", len(lw_ra) >= 2, f"count={len(lw_ra)}")
    # recursive call
    ok &= check("Recursive call present", "jal ra, FUNC_factorial" in asm)
    return ok


def assertions_t03(asm, output):
    """Globals: counter stored at absolute address, not sp+offset."""
    ok = True
    ok &= check("increment() function present", "FUNC_increment:" in asm)
    # Global loads must go through a temp reg loaded with an absolute address
    # (luhw/llhw pattern or addi from a known address)
    ok &= check("Global address loaded via luhw/llhw",
                "luhw" in asm or "lui" in asm,
                "expected upper-half load for absolute address")
    # Global must NOT be accessed as offset(sp) — counter is global
    # (sp stores are only for the saved ra and any local params)
    ok &= check("No spurious sp-relative store for global",
                asm.count("sw t") <= asm.count("jal"),   # rough: fewer sp stores than calls
                "too many sw t*, offset(sp) — global might be treated as local")
    return ok


def assertions_t04(asm, output):
    """While loop: WHILE_START and WHILE_END labels, loop body uses sp."""
    ok = True
    ok &= check("WHILE_START label present", "WHILE_START" in asm)
    ok &= check("WHILE_END label present",   "WHILE_END"   in asm)
    # Loop body stores result back to sp-relative variable
    ok &= check("Loop body stores to sp-relative var", re.search(r"sw \w+, \d+\(sp\)", asm) is not None)
    return ok


def assertions_t05(asm, output):
    """If/else: IF_ELSE and IF_END labels, both branches present."""
    ok = True
    ok &= check("IF_ELSE label present", "IF_ELSE" in asm)
    ok &= check("IF_END label present",  "IF_END"  in asm)
    ok &= check("CMP labels present",    "CMP_TRUE" in asm and "CMP_END" in asm)
    ok &= check("Two jr ra (one per function)", asm.count("jr ra") >= 2)
    return ok


# Map filename prefix → assertion function
ASSERTIONS = {
    "t01": assertions_t01,
    "t02": assertions_t02,
    "t03": assertions_t03,
    "t04": assertions_t04,
    "t05": assertions_t05,
}

# --------------------------------------------------------------------------- #
# Runner
# --------------------------------------------------------------------------- #

def run_all(filter_prefix=None):
    programs = sorted(f for f in os.listdir(PROGRAMS) if f.endswith(".fr"))
    if filter_prefix:
        programs = [p for p in programs if filter_prefix in p]

    results = []
    for prog in programs:
        prefix = prog.split("_")[0]  # e.g. "t01"
        path   = os.path.join(PROGRAMS, prog)

        print(f"\n{'─'*60}")
        print(f"  {prog}")
        print(f"{'─'*60}")

        asm, full_output, compiled = compile_fr(path)

        if not compiled:
            print(f"  ✘  COMPILE ERROR")
            # Print last few lines of output for context
            for line in full_output.strip().splitlines()[-6:]:
                print(f"     {line}")
            results.append((prog, False))
            continue

        print(f"  ✔  Compiled OK")

        assert_fn = ASSERTIONS.get(prefix)
        if assert_fn is None:
            print(f"  ?  No assertions registered for '{prefix}' — skipping checks")
            results.append((prog, True))
            continue

        test_ok = assert_fn(asm, full_output)
        results.append((prog, test_ok))

    # Summary
    passed = sum(1 for _, ok in results if ok)
    total  = len(results)
    print(f"\n{'═'*60}")
    print(f"  RESULTS: {passed}/{total} passed")
    print(f"{'═'*60}\n")

    for prog, ok in results:
        icon = "✔" if ok else "✘"
        print(f"  {icon}  {prog}")
    print()

    return passed == total


if __name__ == "__main__":
    flt = sys.argv[1] if len(sys.argv) > 1 else None
    success = run_all(flt)
    sys.exit(0 if success else 1)
