# SecuRISC-32 Testing & Validation Guide

## Quick Start: Validate the Architecture

The simplest way to verify that everything works correctly:

\`\`\`bash
cd /home/not_pepegrillo/Documents/Arqui/Proyecto2/ISA_PROJECT
python3 tools/validate_architecture.py --verbose
\`\`\`

This runs:
- 7 compiler tests (.fr → HEX)
- 3 assembler tests (.s → HEX)
- 9 hardware testbenches (ALU, PC, RegFile, Decoder, etc.)
- 1 integration test (CPU execution)

**Expected output:** All tests PASS (19 total)

---

## Understanding the Test Results

### Compiler Tests (7)
Tests that the source language compiler works:
- **t01_local_vars**: Local variable scoping
- **t02_recursion**: Recursive function calls
- **t03_globals**: Global variable access
- **t04_while_loop**: Loop control flow
- **t05_if_else**: Conditional branching
- **t06_multi_args**: Function arguments
- **t09_fibonacci**: Arithmetic operations

### Assembler Tests (3)
Tests that direct assembly programs work:
- **test**: Basic operations
- **test2**: Extended operations
- **test3**: Additional tests

### Hardware Tests (9)
Tests individual ISA modules:
- **ALU**: Add, Sub, Mul, Div, Rem, And, Or, Xor, Shl, Shr
- **PC**: Program Counter increment and jumps
- **RegisterFile**: Read/write operations on 32 registers
- **Decoder**: Instruction field extraction
- **ControlUnit**: Control signal generation
- **DMEM**: Data memory read/write
- **IMEM**: Instruction memory load
- **SecALU**: TEA primitive, ADDK, XORK
- **KeyVault**: Secure key storage

### Integration Test (1)
- **CPU Execution**: Full 5-stage pipeline with all modules

---

## Running Individual Tests

### Test a single compiler program

\`\`\`bash
# Compile
make frc-build-t01_local_vars

# View generated Assembly
make frc-asm-t01_local_vars

# Simulate with CPU
make sv-cpu-exec PROGRAM=programs/hex/t01_local_vars.hex MAX_CYCLES=1000
\`\`\`

### Test a single hardware module

\`\`\`bash
# Run ALU testbench
make sv-run-alu

# Run CPU testbench
make sv-run-cpu_top
\`\`\`

### View waveforms

\`\`\`bash
# After running a simulation
gtkwave sim/tb_top.vcd
\`\`\`

---

## Debugging Failed Tests

### If compiler test fails:

\`\`\`bash
# Get detailed output
.venv/bin/python -m src.compiler.frc programs/source/tests/t01_local_vars.fr --debug

# Check generated assembly
cat build/asm/t01_local_vars.s

# Check generated hex
cat programs/hex/t01_local_vars.hex
\`\`\`

### If testbench fails:

1. **Run with verbose output:**
   \`\`\`bash
   make sv-run-alu 2>&1 | head -50
   \`\`\`

2. **Check testbench source:**
   \`\`\`bash
   cat tb/tb_alu.sv
   \`\`\`

3. **Look for error patterns** in simulation output

---

## ISA Instruction Coverage

The architecture implements the full ISA specification:

### R-type (Register-Register)
- ADD, SUB, MUL, DIV, REM
- AND, OR, XOR
- SLL, SRL

### I-type (Register-Immediate)
- ADDI, XORI
- SLLI, SRLI
- LW (Load Word)

### S-type (Store)
- SW (Store Word)

### B-type (Branch)
- BEQ (Equal), BNE (Not Equal)
- BLT (Less Than), BGE (Greater/Equal)
- BGT (Greater), BLE (Less/Equal)

### J-type (Jump)
- J (Jump)
- JAL (Jump And Link)
- JR (Jump Register)

### U-type (Upper/Lower)
- LUHW (Load Upper Half Word)
- LLHW (Load Lower Half Word)

### SEC-type (Security)
- AUTH (Authenticate)
- LDK (Load Key)
- ADDK (Add with Key)
- XORK (XOR with Key)
- TEA (TEA Primitive)

---

## Architecture Details

### Pipeline Stages
1. **IF**: Instruction Fetch (IMEM)
2. **ID**: Instruction Decode + Register Read
3. **EX**: Execute (ALU operations)
4. **MEM**: Memory Access (DMEM for load/store)
5. **WB**: Write Back (Register File)

### Data Path
- 32-bit instructions
- 32 general-purpose registers
- 32KB instruction memory (configurable)
- 32KB data memory (configurable)
- 16-word key vault (security extension)

### Hazard Control
- **Stalling**: Detects RAW (Read-After-Write) dependencies
- **Forwarding**: Bypasses results between pipeline stages
- **Flushing**: Clears pipeline on branches/jumps

---

## Common Issues & Solutions

### "iverilog not found"
```bash
# Install Icarus Verilog
sudo apt install iverilog  # Linux
brew install icarus-verilog  # macOS