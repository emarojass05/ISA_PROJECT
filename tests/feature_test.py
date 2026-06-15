#!/usr/bin/env python3
"""
Feature acceptance test for the FRC compiler.

Compiles every program in programs/source/feature_check/, runs it on the
SystemVerilog CPU model (CACHE_ENABLE=0) and checks that main's return value
(register a0 == x3) matches the expected, post-fix value.

This suite is the acceptance gate for the compiler tracking issue: when every
test reports PASS, the issues P1-P6 are considered resolved.

Each entry in EXPECTED is the value a CORRECT compiler must produce, not the
value the current (buggy) compiler produces. Tests covering the known defects
(see ISSUE_REF) therefore FAIL until the corresponding issue is fixed.

Usage:
    python tests/feature_test.py            # run all
    python tests/feature_test.py array      # run tests whose name contains 'array'
    pytest tests/feature_test.py            # run under pytest

Exit code: 0 if all tests pass, 1 otherwise.
"""

import glob
import os
import re
import shutil
import subprocess
import sys

# =========================
# Configuration
# =========================

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FRC = os.path.join(REPO_ROOT, "frc")
FEATURE_DIR = os.path.join(REPO_ROOT, "programs", "source", "feature_check")

SIM_DIR = os.path.join(REPO_ROOT, "build", "sim")
HEX_DIR = os.path.join(REPO_ROOT, "build", "bin", "feature_check")
VVP_FILE = os.path.join(SIM_DIR, "cpu_program.vvp")
REGISTER_DUMP = os.path.join(SIM_DIR, "register_dump.txt")

CPU_SRC_DIR = os.path.join(REPO_ROOT, "src", "cpu")
ISA_DEFS = os.path.join(CPU_SRC_DIR, "isa_defs.sv")
TESTBENCH = os.path.join(REPO_ROOT, "tb", "tb_cpu_program.sv")

# Upper bound baked into the simulator. Terminating programs stop earlier at
# their PROGRAM_END sentinel, so a generous value only affects hang detection.
MAX_CYCLES = 50000

# Per-process wall-clock guards (seconds).
COMPILE_TIMEOUT = 60
BUILD_TIMEOUT = 300
RUN_TIMEOUT = 120

# =========================
# Expected results
# =========================

# Maps test name (file stem) to the return value (a0/x3) a correct compiler
# must produce, or the sentinel COMPILE_ERROR when compilation itself is the
# expected outcome. Values were verified against the corrected semantics, not
# copied from the (partly stale) in-file header comments.
COMPILE_ERROR = "compile_error"

EXPECTED = {
    "annotations": 7,
    "arithmetic_ops": 42,
    "array_3x3": 9,           # P3: 3x3 matrix, ret mat@(2)@(2) = 9
    "array_indexed_rw": 15,
    "array_large": 42,        # P1: large frame (> 12-bit sp adjust)
    "array_literal": 30,
    "array_multidim": 4,      # P3: row-major stride
    "array_param_2d": 50,     # N-D stride on dimensioned pointer parameters
    "array_sized": 99,
    "bitwise_ops": 42,
    "continue_stmt": 6,
    "for_loop": 14,
    "globals": 45,            # P5: premature HALT fix
    "hex_literals": 255,
    "if_else": 6,
    "imports": 60,
    "logical_ops": 3,         # P4: &&/|| normalized to 0/1
    "many_params": 36,
    "pointer_params": 40,
    "recursion": 120,
    "relational_eq": 6,
    "string_literal": 104,    # P6: 'h' = 104
    "symbol_table_address_test": 42,  # P2: stack layout display
    "types_bool": 1,
    "types_char": 65,
    "unary_ops": 5,
    "while_loop": 10,
}

# Files in feature_check/ that are not standalone tests (no main function).
HELPERS = {"fc_utils"}

# Test name -> issue identifier in the compiler tracking issue, for reporting.
ISSUE_REF = {
    "array_large": "P1",
    "array_multidim": "P3",
    "logical_ops": "P4",
    "globals": "P5",
    "string_literal": "P6",
}

# =========================
# Result type
# =========================

class FeatureResult:
    def __init__(self, name, status, expected, got, detail=""):
        self.name = name
        self.status = status      # "PASS" | "FAIL" | "ERROR"
        self.expected = expected
        self.got = got
        self.detail = detail

    @property
    def passed(self):
        return self.status == "PASS"

# =========================
# Helpers
# =========================

def to_signed32(value):
    return value - 0x100000000 if value & 0x80000000 else value


def discover_tests():
    names = {
        os.path.splitext(os.path.basename(path))[0]
        for path in glob.glob(os.path.join(FEATURE_DIR, "*.fr"))
    }
    return names - HELPERS


def validate_manifest():
    """Ensure EXPECTED and the files on disk are in sync, so new tests cannot
    be silently skipped and stale entries cannot mask a deleted test."""
    testable = discover_tests()
    missing_expected = sorted(testable - set(EXPECTED))
    missing_files = sorted(set(EXPECTED) - testable)

    problems = []
    if missing_expected:
        problems.append(f"tests without an EXPECTED entry: {missing_expected}")
    if missing_files:
        problems.append(f"EXPECTED entries without a .fr file: {missing_files}")
    if problems:
        raise RuntimeError("feature_test manifest out of sync: " + "; ".join(problems))


def build_simulator():
    """Compile the CPU model + testbench into a reusable vvp once."""
    if not shutil.which("iverilog") or not shutil.which("vvp"):
        raise RuntimeError("iverilog/vvp not found on PATH; install Icarus Verilog")

    os.makedirs(SIM_DIR, exist_ok=True)

    cpu_modules = sorted(
        path for path in glob.glob(os.path.join(CPU_SRC_DIR, "*.sv"))
        if os.path.abspath(path) != os.path.abspath(ISA_DEFS)
    )
    sources = [ISA_DEFS] + cpu_modules + [TESTBENCH]

    command = [
        "iverilog", "-g2012",
        "-s", "tb_cpu_program",
        f"-Ptb_cpu_program.MAX_CYCLES={MAX_CYCLES}",
        "-Ptb_cpu_program.CACHE_ENABLE=0",
        "-o", VVP_FILE,
    ] + sources

    result = subprocess.run(
        command, cwd=REPO_ROOT, capture_output=True, text=True, timeout=BUILD_TIMEOUT
    )
    if result.returncode != 0:
        raise RuntimeError("simulator build failed:\n" + result.stdout + result.stderr)


def compile_program(name):
    """Compile a feature_check program. Returns (hex_path|None, output)."""
    os.makedirs(HEX_DIR, exist_ok=True)
    source = os.path.join(FEATURE_DIR, f"{name}.fr")
    hex_path = os.path.join(HEX_DIR, f"{name}.hex")

    if os.path.exists(hex_path):
        os.remove(hex_path)

    result = subprocess.run(
        [FRC, source, "-o", hex_path],
        cwd=REPO_ROOT, capture_output=True, text=True, timeout=COMPILE_TIMEOUT,
    )
    output = result.stdout + result.stderr
    ok = result.returncode == 0 and "[ERR]" not in output and os.path.exists(hex_path)
    return (hex_path if ok else None), output


def read_return_value():
    with open(REGISTER_DUMP, "r", encoding="utf-8") as dump:
        for line in dump:
            match = re.match(r"\s*x3\s*=\s*([0-9a-fA-F]+)", line)
            if match:
                return to_signed32(int(match.group(1), 16))
    raise RuntimeError(f"register x3 not found in {REGISTER_DUMP}")


def run_program(hex_path):
    """Run a compiled program and return main's value (a0/x3)."""
    if os.path.exists(REGISTER_DUMP):
        os.remove(REGISTER_DUMP)

    result = subprocess.run(
        ["vvp", VVP_FILE, f"+PROGRAM_FILE={hex_path}", "+INITIAL_MEM="],
        cwd=REPO_ROOT, capture_output=True, text=True, timeout=RUN_TIMEOUT,
    )
    if not os.path.exists(REGISTER_DUMP):
        raise RuntimeError("simulation produced no register dump:\n" + result.stdout + result.stderr)
    return read_return_value()


def run_single(name):
    expected = EXPECTED[name]
    hex_path, output = compile_program(name)

    if expected == COMPILE_ERROR:
        if hex_path is None:
            return FeatureResult(name, "PASS", expected, "compile_error")
        return FeatureResult(name, "FAIL", expected, "compiled",
                          "expected a compile error but compilation succeeded")

    if hex_path is None:
        last = output.strip().splitlines()[-1] if output.strip() else "(no output)"
        return FeatureResult(name, "FAIL", expected, "compile_error", last)

    try:
        got = run_program(hex_path)
    except Exception as error:
        return FeatureResult(name, "ERROR", expected, None, str(error))

    status = "PASS" if got == expected else "FAIL"
    return FeatureResult(name, status, expected, got)

# =========================
# Standalone runner
# =========================

def main(argv):
    validate_manifest()

    name_filter = argv[1] if len(argv) > 1 else None
    names = sorted(EXPECTED)
    if name_filter:
        names = [n for n in names if name_filter in n]
        if not names:
            print(f"[ERR] no tests match '{name_filter}'")
            return 1

    print("[INFO] Building CPU simulator...")
    build_simulator()

    results = []
    for name in names:
        result = run_single(name)
        results.append(result)
        ref = f" ({ISSUE_REF[name]})" if name in ISSUE_REF else ""
        got = "-" if result.got is None else result.got
        line = f"  [{result.status:4}] {name:18} expected={result.expected!s:<14} got={got}{ref}"
        if result.detail:
            line += f"\n         -> {result.detail}"
        print(line)

    passed = sum(1 for r in results if r.passed)
    total = len(results)
    print("\n" + "=" * 60)
    print(f"  RESULTS: {passed}/{total} passed")
    print("=" * 60)

    failures = [r for r in results if not r.passed]
    if failures:
        print("  Failing features (see the compiler tracking issue):")
        for r in failures:
            ref = ISSUE_REF.get(r.name, "-")
            print(f"    {r.name} [{ref}]")

    return 0 if not failures else 1


# =========================
# pytest integration
# =========================

try:
    import pytest

    @pytest.fixture(scope="session")
    def _simulator():
        validate_manifest()
        build_simulator()

    @pytest.mark.parametrize("name", sorted(EXPECTED))
    def test_feature(name, _simulator):
        result = run_single(name)
        assert result.passed, (
            f"{name}: expected {result.expected}, got {result.got}"
            + (f" ({result.detail})" if result.detail else "")
        )

except ImportError:
    pass


if __name__ == "__main__":
    sys.exit(main(sys.argv))
