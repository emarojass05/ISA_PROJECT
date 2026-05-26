from __future__ import annotations

import argparse
import csv
import re
import subprocess
import sys
from pathlib import Path

PROJECT_ROOT     = Path(__file__).resolve().parent.parent
OPTS_DIR         = PROJECT_ROOT / "programs" / "source" / "opts"
BUILD_DIR        = PROJECT_ROOT / "build"
BIN_DIR          = BUILD_DIR / "bin"
SIM_DIR          = BUILD_DIR / "sim"
CYCLE_COUNT_FILE = SIM_DIR / "cycle_count.txt"
DEFAULT_OUT      = BUILD_DIR / "metrics.csv"
DEFAULT_MAX_CYCLES = 2000

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
    "cycle_count",
]


# ---------------------------------------------------------------------------

def _parse_optimizer_block(text: str) -> dict:
    """Parse the OPTIMIZER block from compiler stdout into a metrics dict."""
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
    """Append code_bytes = instrs_after * 4 to a metrics row."""
    after = row.get("instrs_after", 0)
    row["code_bytes"] = after * 4 if isinstance(after, int) else "ERROR"
    return row


def _compile_to_hex(python_cmd: str, source: Path, flag: str | None, hex_path: Path) -> bool:
    """Compile source at the given level to a .hex file. Returns True on success."""
    cmd = [python_cmd, "-m", "src.compiler.main", str(source)]
    if flag:
        cmd.append(flag)
    cmd += ["-o", str(hex_path)]
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=str(PROJECT_ROOT))
    return result.returncode == 0 and hex_path.exists()


def _run_simulation(hex_path: Path, max_cycles: int) -> int | str:
    """Run make sv-cpu-exec and read the cycle count written by the testbench.

    Returns the cycle count as int, 'timeout' if MAX_CYCLES was reached,
    or an error string if the simulation itself failed.
    """
    CYCLE_COUNT_FILE.unlink(missing_ok=True)

    cmd = [
        "make", "sv-cpu-exec",
        f"PROGRAM={hex_path}",
        f"MAX_CYCLES={max_cycles}",
    ]
    result = subprocess.run(
        cmd, capture_output=True, text=True, cwd=str(PROJECT_ROOT)
    )

    if result.returncode != 0:
        return f"sim error: {(result.stdout + result.stderr).strip()[:120]}"

    if not CYCLE_COUNT_FILE.exists():
        return "timeout"   # MAX_CYCLES reached without PROGRAM_END detection

    try:
        return int(CYCLE_COUNT_FILE.read_text().strip())
    except ValueError:
        return "parse error"


# ---------------------------------------------------------------------------

def _get_instrs_before(python_cmd: str, source: Path) -> int | str:
    """Get IR instruction count before any optimization by running --O1."""
    cmd = [python_cmd, "-m", "src.compiler.main", str(source), "--O1"]
    result = subprocess.run(
        cmd, capture_output=True, text=True, cwd=str(PROJECT_ROOT)
    )
    output = result.stdout
    if "OPTIMIZER" not in output:
        return f"no OPTIMIZER block: {(output + result.stderr).strip()[:200]}"
    m = re.search(r"Instructions before\s*:\s*(\d+)", output)
    return int(m.group(1)) if m else 0


def _run_level(
    python_cmd: str,
    source: Path,
    flag: str | None,
    hex_path: Path | None = None,
    max_cycles: int = DEFAULT_MAX_CYCLES,
) -> dict | str:
    """Compile source at the given optimization level; return metrics dict or error string.

    If hex_path is provided the source is also compiled to that .hex file and the
    CPU simulator is run so that cycle_count can be measured.
    """
    if flag is None:
        # O0: no optimization pass; get instruction count via --O1 probe
        n_or_err = _get_instrs_before(python_cmd, source)
        if isinstance(n_or_err, str):
            return n_or_err
        n = n_or_err
        metrics = {
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
        # O1 / O2: run compiler with optimization flag
        cmd = [python_cmd, "-m", "src.compiler.main", str(source), flag]
        result = subprocess.run(
            cmd, capture_output=True, text=True, cwd=str(PROJECT_ROOT)
        )
        output = result.stdout
        if "OPTIMIZER" not in output:
            err = (result.stdout + result.stderr).strip()[:300]
            return f"no OPTIMIZER block in output: {err}"
        start = output.find("========== OPTIMIZER")
        metrics = _parse_optimizer_block(output[start:])

    # Optionally compile to hex and measure cycle count via CPU simulation
    if hex_path is not None:
        if _compile_to_hex(python_cmd, source, flag, hex_path):
            metrics["cycle_count"] = _run_simulation(hex_path, max_cycles)
        else:
            metrics["cycle_count"] = "compile error"
    else:
        metrics["cycle_count"] = ""

    return metrics


# ---------------------------------------------------------------------------

def main() -> None:
    ap = argparse.ArgumentParser(
        description="Generate CSV metrics for the optimization pipeline."
    )
    ap.add_argument(
        "--out", default=str(DEFAULT_OUT),
        help="Output CSV path (default: build/metrics.csv)"
    )
    ap.add_argument(
        "--python", default=".venv/bin/python3",
        help="Python interpreter to use (default: .venv/bin/python3)"
    )
    ap.add_argument(
        "--sim", action="store_true",
        help="Also compile to hex and run CPU simulation to measure cycle_count"
    )
    ap.add_argument(
        "--max-cycles", type=int, default=DEFAULT_MAX_CYCLES,
        help=f"MAX_CYCLES for CPU simulation (default: {DEFAULT_MAX_CYCLES})"
    )
    args = ap.parse_args()

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    if args.sim:
        BIN_DIR.mkdir(parents=True, exist_ok=True)
        SIM_DIR.mkdir(parents=True, exist_ok=True)

    programs = sorted(OPTS_DIR.glob("*.fr"))
    if not programs:
        print(f"[WARN] No .fr files found in {OPTS_DIR}", file=sys.stderr)
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

            hex_path = (
                BIN_DIR / f"metrics_{prog.stem}_{level_name}.hex"
                if args.sim else None
            )

            result = _run_level(args.python, prog, flag, hex_path, args.max_cycles)

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
                cycles_str = f"  cycles={result['cycle_count']}" if args.sim else ""
                print(
                    f"OK  "
                    f"ir-inst-before={result['instrs_before']:3d}  "
                    f"ir-inst-after={result['instrs_after']:3d}  "
                    f"ir-inst-saved={result['instrs_saved']:3d}"
                    f"{cycles_str}"
                )

    with open(out_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=CSV_FIELDS)
        writer.writeheader()
        writer.writerows(rows)

    print(f"\nCSV saved to     : {out_path}")
    print(f"Programs         : {len(programs)}")
    print(f"Rows generated   : {len(rows)}")
    if args.sim:
        print(f"Simulation       : enabled  (MAX_CYCLES={args.max_cycles})")
    if errors:
        print(f"Errors           : {errors}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
