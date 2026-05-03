# =========================
# Toolchain
# =========================
IVERILOG = iverilog
VVP = vvp
FLAGS = -g2012
PYTHON = .venv/bin/python
ANTLR_VERSION = 4.13.2
ANTLR_JAR = tools/antlr-$(ANTLR_VERSION)-complete.jar
ANTLR = java -jar $(abspath $(ANTLR_JAR))
GTK_WAVE = gtkwave

# =========================
# Folders & Files
# =========================
BUILD_DIR = build
SIM_DIR = sim
SIM_BUILD = $(BUILD_DIR)/sim
COMPILER_BUILD = $(BUILD_DIR)/programs # Programs built with compiler
BIN_DIR = $(BUILD_DIR)/bin

CPU_SRC_DIR = src/cpu
TB_DIR  = tb

FRC_SRC_DIR = programs/source
GRAMMAR_DIR = src/compiler/grammar
GENERATED_DIR = src/compiler/generated

GRAMMAR = Language.g4
FRC_COMPILER = src.compiler.main
ASM_ENCODER = src/compiler/backend/encoder.py
ASM_DIR = programs/asm
HEX_DIR = programs/hex

MEM_DIR = programs/mems

PROGRAM ?= $(HEX_DIR)/program.hex
INITIAL_MEM ?=
MAX_CYCLES ?= 200

# =========================
# CPU Modules
# =========================
ISA_DEFS = $(CPU_SRC_DIR)/isa_defs.sv
CPU_MODS = $(filter-out $(ISA_DEFS), $(wildcard $(CPU_SRC_DIR)/*.sv))
CPU_SRC = $(ISA_DEFS) $(CPU_MODS)

# =================================================
# Targets
# NOTE: When adding rules, add what it does after
# target: requisites preceeded by ## so targets
# remain automatically documented
# =================================================



.PHONY: all help

all: help

help:
	@echo "Available targets:"
	@grep -E '^[a-zA-Z0-9_%-.]+:.*?## ' $(MAKEFILE_LIST) | \
	awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

sv-cbuild-%: $(CPU_SRC) $(TB_DIR)/tb_%.sv ## Build single CPU module '%' from src/cpu with it's testbench
	@mkdir -p $(SIM_BUILD)
	$(IVERILOG) $(FLAGS) -s tb_$* -o $(SIM_BUILD)/$*.vvp $^

sv-run-%: sv-cbuild-% ## Build %.vpp if not previously built and run it
	$(VVP) $(SIM_BUILD)/$*.vvp

sv-clear: ## Clear iverilog outputs folder(s)
	@rm -rf $(SIM_BUILD)

sv-cpu-exec: $(CPU_SRC) $(TB_DIR)/tb_cpu_program.sv ## Build and run CPU with arbitrary program hex and optional RAM mem
	@mkdir -p $(SIM_BUILD)
	$(IVERILOG) $(FLAGS) \
		-s tb_cpu_program \
		-Ptb_cpu_program.PROGRAM_FILE=\"$(PROGRAM)\" \
		-Ptb_cpu_program.INITIAL_MEM=\"$(INITIAL_MEM)\" \
		-Ptb_cpu_program.MAX_CYCLES=$(MAX_CYCLES) \
		-o $(SIM_BUILD)/cpu_program.vvp \
		$^
	$(VVP) $(SIM_BUILD)/cpu_program.vvp

wave-%: $(SIM_BUILD)/%.vcd
	@$(GTK_WAVE) $^

setup: ## Create Python venv and install dependencies
	python3 -m venv .venv
	$(PYTHON) -m ensurepip --upgrade
	$(PYTHON) -m pip install --upgrade pip
	$(PYTHON) -m pip install -r requirements.txt

antlr-download: ## Download pinned ANTLR tool
	@mkdir -p tools
	curl -L -o $(ANTLR_JAR) https://www.antlr.org/download/antlr-$(ANTLR_VERSION)-complete.jar

check-env: ## Check ANTLR versions
	$(PYTHON) -c "import importlib.metadata as m; print('antlr4-python3-runtime', m.version('antlr4-python3-runtime'))"
	java -jar $(ANTLR_JAR) -version

antlr-build: $(ANTLR_JAR) ## Build ANTLR modules
	@mkdir -p $(GENERATED_DIR)
	@rm -rf $(GENERATED_DIR)/*
	cd $(GRAMMAR_DIR) && $(ANTLR) -Dlanguage=Python3 -visitor -o ../generated $(GRAMMAR)
	@touch src/__init__.py
	@touch src/compiler/__init__.py
	@touch src/compiler/generated/__init__.py

$(ANTLR_JAR):
	$(MAKE) antlr-download

antlr-clear: ## Clear ANTLR output folder(s)
	@rm -rf $(GENERATED_DIR)/*

frc-parse-%: antlr-build ## Parse .fr source file from programs/source
	PYTHONPATH=. $(PYTHON) -m $(FRC_COMPILER) $(FRC_SRC_DIR)/$*.fr

frc-build-%: antlr-build ## Compile .fr source and save both .hex and .asm
	PYTHONPATH=. $(PYTHON) -m $(FRC_COMPILER) $(FRC_SRC_DIR)/$*.fr -s

frc-debug-%: antlr-build ## Compile with verbose, AST and symbol tables
	PYTHONPATH=. $(PYTHON) -m $(FRC_COMPILER) $(FRC_SRC_DIR)/$*.fr -v -s -t -m

asm-encode-%: ## Encode programs/asm/%.s and print hexadecimal output
	$(PYTHON) $(ASM_ENCODER) $*

asm-build-%: ## Encode programs/asm/%.s and save output into programs/hex/%.hex
	@mkdir -p $(HEX_DIR)
	$(PYTHON) $(ASM_ENCODER) $* > $(HEX_DIR)/$*.hex


EXAMPLES_DIR = examples
ADDRESS ?= 0x1000
FILE ?= test1.png

encrypt-flow: ## Run end-to-end flow: load file -> simulate -> extract -> compare
	@echo "=== Encryption Flow ==="
	@echo "Input file : $(EXAMPLES_DIR)/$(FILE)"
	@echo "Output file: $(EXAMPLES_DIR)/enc_$(FILE)"
	@echo "Address    : $(ADDRESS)"
	@rm -f memory.mem build/sim/memory_dump.txt $(EXAMPLES_DIR)/enc_$(FILE)
	@SIZE=$$(wc -c < "$(EXAMPLES_DIR)/$(FILE)") ; \
	 echo "File size  : $$SIZE bytes" ; \
	 echo "" ; \
	 echo "[1/4] Switching program.hex to encrypt routine..." ; \
	 cp programs/hex/encrypt.hex programs/hex/program.hex ; \
	 echo "" ; \
	 echo "[2/4] Loading file into memory.mem..." ; \
	 ./tools/load_file.py --input "$(EXAMPLES_DIR)/$(FILE)" --output memory.mem --address $(ADDRESS) ; \
	 echo "" ; \
	 echo "[3/4] Running CPU simulation..." ; \
	 $(MAKE) sv-run-cpu ; \
	 echo "" ; \
	 echo "[4/4] Extracting result from memory_dump..." ; \
	 ./tools/extract_data.py --memory build/sim/memory_dump.txt --address $(ADDRESS) --size $$SIZE --output "$(EXAMPLES_DIR)/enc_$(FILE)" ; \
	 echo "" ; \
	 echo "=== Comparing original vs result ===" ; \
	 if cmp -s "$(EXAMPLES_DIR)/$(FILE)" "$(EXAMPLES_DIR)/enc_$(FILE)" ; then \
	     echo "[INFO] Files are IDENTICAL (no encryption applied to this region)" ; \
	 else \
	     echo "[OK] Files DIFFER (encryption modified the data)" ; \
	 fi

encrypt-clean: ## Remove temp files generated by encrypt-flow and decrypt-flow
	@rm -f memory.mem build/sim/memory_dump.txt $(EXAMPLES_DIR)/enc_* $(EXAMPLES_DIR)/dec_*
	@echo "[OK] Cleaned encryption artifacts"

decrypt-flow: ## Run decryption flow on a file from examples/
	@echo "=== Decryption Flow ==="
	@echo "Input file : $(EXAMPLES_DIR)/$(FILE)"
	@echo "Output file: $(EXAMPLES_DIR)/dec_$(FILE)"
	@echo "Address    : $(ADDRESS)"
	@rm -f memory.mem build/sim/memory_dump.txt $(EXAMPLES_DIR)/dec_$(FILE)
	@SIZE=$$(wc -c < "$(EXAMPLES_DIR)/$(FILE)") ; \
	 echo "File size  : $$SIZE bytes" ; \
	 echo "" ; \
	 echo "[1/4] Switching program.hex to decrypt routine..." ; \
	 cp programs/hex/decrypt.hex programs/hex/program.hex ; \
	 echo "" ; \
	 echo "[2/4] Loading file into memory.mem..." ; \
	 ./tools/load_file.py --input "$(EXAMPLES_DIR)/$(FILE)" --output memory.mem --address $(ADDRESS) ; \
	 echo "" ; \
	 echo "[3/4] Running CPU simulation..." ; \
	 $(MAKE) sv-run-cpu ; \
	 echo "" ; \
	 echo "[4/4] Extracting result from memory_dump..." ; \
	 ./tools/extract_data.py --memory build/sim/memory_dump.txt --address $(ADDRESS) --size $$SIZE --output "$(EXAMPLES_DIR)/dec_$(FILE)" ; \
	 echo "" ; \
	 echo "=== Result ==="

verify-roundtrip: ## Encrypt then decrypt a file and verify the result matches the original
	@echo "=== Roundtrip Verification ==="
	@$(MAKE) encrypt-flow FILE=$(FILE)
	@$(MAKE) decrypt-flow FILE=enc_$(FILE)
	@echo ""
	@echo "=== Final comparison: original vs decrypted ==="
	@if cmp -s "$(EXAMPLES_DIR)/$(FILE)" "$(EXAMPLES_DIR)/dec_enc_$(FILE)" ; then \
	    echo "[PASS] Encryption/decryption is reversible — files match." ; \
	else \
	    echo "[FAIL] Decrypted file does NOT match the original." ; \
	fi