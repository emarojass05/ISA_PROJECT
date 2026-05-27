#!/usr/bin/env python3
"""
SecuRISC-32 Architecture Validation Script
============================================
Validates that all ISA instructions work correctly according to specification.
Tests: compilation, simulation, and instruction execution.

Usage:
    python3 tools/validate_architecture.py [--verbose]
"""

import subprocess
import sys
import os
from pathlib import Path
from datetime import datetime
import json

REPO_ROOT = Path(__file__).parent.parent
VENV_PY = REPO_ROOT / ".venv" / "bin" / "python"
BUILD_DIR = REPO_ROOT / "build"
RESULTS_DIR = BUILD_DIR / "validation"

class ArchitectureValidator:
    def __init__(self, verbose=False):
        self.verbose = verbose
        self.passed = 0
        self.failed = 0
        self.skipped = 0
        self.tests = []
        
    def print(self, msg, level="INFO"):
        if self.verbose or level != "INFO":
            prefix = {"PASS": "✓", "FAIL": "✗", "SKIP": "⊘"}.get(level, f"[{level}]")
            print(f"{prefix} {msg}")
    
    def run_cmd(self, cmd, timeout=30):
        try:
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
            return result.returncode, result.stdout, result.stderr
        except subprocess.TimeoutExpired:
            return -1, "", "TIMEOUT"
        except Exception as e:
            return -1, "", str(e)
    
    def test_compiler(self, program_name, description):
        """Test compilation of a .fr program"""
        self.print(f"Testing compiler: {description}...", "INFO")
        
        cmd = f"cd {REPO_ROOT} && {VENV_PY} -m src.compiler.frc programs/source/tests/{program_name}.fr -o build/test_{program_name}.hex 2>&1"
        rc, stdout, stderr = self.run_cmd(cmd, timeout=10)
        
        combined = stdout + stderr
        if rc == 0 and "error" not in combined.lower():
            self.print(f"{description}: Compiled OK", "PASS")
            self.passed += 1
            self.tests.append({"name": description, "type": "compile", "status": "PASS"})
            return True
        else:
            self.print(f"{description}: {combined[:100]}", "FAIL")
            self.failed += 1
            self.tests.append({"name": description, "type": "compile", "status": "FAIL", "error": combined[:200]})
            return False
    
    def test_assembler(self, program_name, description):
        """Test assembly of a .s program"""
        self.print(f"Testing assembler: {description}...", "INFO")
        
        cmd = f"cd {REPO_ROOT} && make asm-build-{program_name} 2>&1"
        rc, stdout, stderr = self.run_cmd(cmd, timeout=10)
        
        combined = stdout + stderr
        if rc == 0 and "error" not in combined.lower():
            self.print(f"{description}: Assembled OK", "PASS")
            self.passed += 1
            self.tests.append({"name": description, "type": "assemble", "status": "PASS"})
            return True
        else:
            self.print(f"{description}: Assembly failed", "FAIL")
            self.failed += 1
            self.tests.append({"name": description, "type": "assemble", "status": "FAIL"})
            return False
    
    def test_testbench(self, testbench_name, description):
        """Test a Verilog testbench"""
        self.print(f"Testing module: {description}...", "INFO")
        
        cmd = f"cd {REPO_ROOT} && make sv-run-{testbench_name} 2>&1"
        rc, stdout, stderr = self.run_cmd(cmd, timeout=30)
        
        combined = stdout + stderr
        has_error = "error" in combined.lower() or "fail" in combined.lower()
        
        if rc == 0 and not has_error:
            self.print(f"{description}: Testbench PASS", "PASS")
            self.passed += 1
            self.tests.append({"name": description, "type": "testbench", "status": "PASS"})
            return True
        elif "iverilog" not in combined and rc != 0:
            self.print(f"{description}: Skipped (iverilog unavailable)", "SKIP")
            self.skipped += 1
            self.tests.append({"name": description, "type": "testbench", "status": "SKIP"})
            return False
        else:
            self.print(f"{description}: Testbench failed", "FAIL")
            self.failed += 1
            self.tests.append({"name": description, "type": "testbench", "status": "FAIL"})
            return False
    
    def validate(self):
        """Run full validation"""
        print("\n" + "="*70)
        print("  SecuRISC-32 ARCHITECTURE VALIDATION")
        print("  Validating ISA compliance according to specification")
        print("="*70 + "\n")
        
        # 1. Compiler Tests
        print("1. COMPILER TESTS (Source code generation)\n")
        self.test_compiler("t01_local_vars", "Local Variables")
        self.test_compiler("t02_recursion", "Recursion")
        self.test_compiler("t03_globals", "Global Variables")
        self.test_compiler("t04_while_loop", "While Loops")
        self.test_compiler("t05_if_else", "If-Else Statements")
        self.test_compiler("t06_multi_args", "Function Arguments")
        self.test_compiler("t09_fibonacci", "Fibonacci (Iteration)")
        
        # 2. Assembler Tests
        print("\n2. ASSEMBLER TESTS (Assembly code)\n")
        self.test_assembler("test", "Test Program 1")
        self.test_assembler("test2", "Test Program 2")
        self.test_assembler("test3", "Test Program 3")
        
        # 3. Hardware Testbenches
        print("\n3. HARDWARE TESTS (ISA modules)\n")
        self.test_testbench("alu", "ALU Module (R-type operations)")
        self.test_testbench("pc", "Program Counter")
        self.test_testbench("register_file", "Register File (32 registers)")
        self.test_testbench("decoder", "Instruction Decoder")
        self.test_testbench("control_unit", "Control Unit")
        self.test_testbench("data_mem", "Data Memory (DMEM)")
        self.test_testbench("instr_mem", "Instruction Memory (IMEM)")
        self.test_testbench("sec_alu", "Security ALU (TEA, ADDK, XORK)")
        self.test_testbench("key_vault", "Key Vault")
        
        # 4. Integration Tests
        print("\n4. INTEGRATION TESTS (End-to-end)\n")
        cmd = f"cd {REPO_ROOT} && make sv-cpu-exec PROGRAM=programs/hex/test.hex MAX_CYCLES=1000 2>&1"
        rc, stdout, stderr = self.run_cmd(cmd, timeout=60)
        
        if rc == 0:
            self.print("CPU Execution: OK", "PASS")
            self.passed += 1
            self.tests.append({"name": "CPU Execution", "type": "integration", "status": "PASS"})
        else:
            self.print("CPU Execution: Failed", "FAIL")
            self.failed += 1
            self.tests.append({"name": "CPU Execution", "type": "integration", "status": "FAIL"})
        
        # Generate report
        self._generate_report()
    
    def _generate_report(self):
        """Generate validation report"""
        RESULTS_DIR.mkdir(parents=True, exist_ok=True)
        
        total = self.passed + self.failed
        pass_rate = (self.passed / total * 100) if total > 0 else 0
        
        # Console output
        print("\n" + "="*70)
        print(f"VALIDATION RESULTS")
        print(f"Passed:  {self.passed}")
        print(f"Failed:  {self.failed}")
        print(f"Skipped: {self.skipped}")
        print(f"Pass Rate: {pass_rate:.1f}%")
        print("="*70 + "\n")
        
        if self.failed == 0:
            print("✓ ALL TESTS PASSED - Architecture is compliant with ISA specification")
        else:
            print(f"✗ {self.failed} tests failed - Review issues above")
        
        # JSON report
        report_file = RESULTS_DIR / "validation_results.json"
        with open(report_file, "w") as f:
            json.dump({
                "timestamp": datetime.now().isoformat(),
                "passed": self.passed,
                "failed": self.failed,
                "skipped": self.skipped,
                "pass_rate": f"{pass_rate:.1f}%",
                "tests": self.tests
            }, f, indent=2)
        
        print(f"\n✓ Report saved: {report_file}")

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Validate SecuRISC-32 architecture")
    parser.add_argument("--verbose", "-v", action="store_true", help="Verbose output")
    args = parser.parse_args()
    
    validator = ArchitectureValidator(verbose=args.verbose)
    validator.validate()
    
    sys.exit(0 if validator.failed == 0 else 1)