
---

## **ARCHIVO 3: tests/run_all_tests.sh (Script para ejecutar todo)**

```bash
#!/bin/bash

# SecuRISC-32 Full Test Runner
# ============================
# Runs all tests and generates report

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VENV_PY="$REPO_ROOT/.venv/bin/python"
BUILD_DIR="$REPO_ROOT/build"

echo "=========================================="
echo "  SecuRISC-32 Full Test Suite"
echo "=========================================="
echo ""

# Step 1: Setup
echo "[1/3] Checking environment..."
if [ ! -d "$REPO_ROOT/.venv" ]; then
    echo "ERROR: Virtual environment not found. Run: make setup"
    exit 1
fi

# Step 2: Validate architecture
echo ""
echo "[2/3] Running architecture validation..."
echo "========================================"
"$VENV_PY" tools/validate_architecture.py --verbose
ARCH_RESULT=$?

# Step 3: Run compiler tests
echo ""
echo "[3/3] Running compiler unit tests..."
echo "======================================"
"$VENV_PY" tests/run_tests.py
COMPILER_RESULT=$?

# Summary
echo ""
echo "=========================================="
echo "  TEST SUMMARY"
echo "=========================================="

if [ $ARCH_RESULT -eq 0 ]; then
    echo "✓ Architecture validation: PASS"
else
    echo "✗ Architecture validation: FAIL"
fi

if [ $COMPILER_RESULT -eq 0 ]; then
    echo "✓ Compiler tests: PASS"
else
    echo "✗ Compiler tests: FAIL"
fi

echo ""
if [ $ARCH_RESULT -eq 0 ] && [ $COMPILER_RESULT -eq 0 ]; then
    echo "✓ ALL TESTS PASSED"
    exit 0
else
    echo "✗ SOME TESTS FAILED"
    exit 1
fi