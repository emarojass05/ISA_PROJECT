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
OUT_DIR = $(BUILD_DIR)/out

CPU_SRC_DIR = src/cpu
TB_DIR  = tb

FRC_SRC_DIR = programs/source
GRAMMAR_DIR = src/compiler/grammar
GENERATED_DIR = src/compiler/generated

GRAMMAR = Language.g4
HEX_DIR = programs/hex

MEM_DIR = programs/mems

PROGRAM ?= $(HEX_DIR)/program.hex
INITIAL_MEM ?=
MAX_CYCLES ?= 2000

EXAMPLES_DIR = examples
ADDRESS ?= 0x1000
FILE ?= test2.png
ENC_MEM = build/memory.mem

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

sv-cbuild-%: $(CPU_SRC) $(TB_DIR)/tb_%.sv ## Build CPU module '%' with its tb_%.sv testbench; usage: make sv-cbuild-NAME.
	@mkdir -p $(SIM_BUILD)
	$(IVERILOG) $(FLAGS) -s tb_$* -o $(SIM_BUILD)/$*.vvp $^

sv-run-%: sv-cbuild-%
	$(VVP) $(SIM_BUILD)/$*.vvp

sv-cpu-exec: $(CPU_SRC) $(TB_DIR)/tb_cpu_program.sv ## Build and run the CPU with PROGRAM=<hex>, optional INITIAL_MEM=<mem>, and MAX_CYCLES=<cycles>; usage: make sv-cpu-exec PROGRAM=... INITIAL_MEM=... MAX_CYCLES=....
	@mkdir -p $(SIM_BUILD)
	$(IVERILOG) $(FLAGS) \
		-s tb_cpu_program \
		-Ptb_cpu_program.PROGRAM_FILE=\"$(PROGRAM)\" \
		-Ptb_cpu_program.INITIAL_MEM=\"$(INITIAL_MEM)\" \
		-Ptb_cpu_program.MAX_CYCLES=$(MAX_CYCLES) \
		-o $(SIM_BUILD)/cpu_program.vvp \
		$^
	$(VVP) $(SIM_BUILD)/cpu_program.vvp

setup: ## Create the Python .venv, upgrade pip, and install dependencies from requirements.txt.
	python3 -m venv .venv
	$(PYTHON) -m ensurepip --upgrade
	$(PYTHON) -m pip install --upgrade pip
	$(PYTHON) -m pip install -r requirements.txt

antlr-download: ## Download the pinned ANTLR JAR into tools/ using ANTLR_VERSION; usage: make antlr-download.
	@mkdir -p tools
	curl -L -o $(ANTLR_JAR) https://www.antlr.org/download/antlr-$(ANTLR_VERSION)-complete.jar

check-env: ## Print the installed ANTLR Python runtime version and ANTLR JAR version; usage: make check-env.
	$(PYTHON) -c "import importlib.metadata as m; print('antlr4-python3-runtime', m.version('antlr4-python3-runtime'))"
	java -jar $(ANTLR_JAR) -version

antlr-build: $(ANTLR_JAR) ## Generate Python ANTLR modules from Language.g4 into src/compiler/generated; usage: make antlr-build.
	@mkdir -p $(GENERATED_DIR)
	@rm -rf $(GENERATED_DIR)/*
	cd $(GRAMMAR_DIR) && $(ANTLR) -Dlanguage=Python3 -visitor -o ../generated $(GRAMMAR)
	@touch src/__init__.py
	@touch src/compiler/__init__.py
	@touch src/compiler/generated/__init__.py

$(ANTLR_JAR):
	$(MAKE) antlr-download

antlr-clear: ## Remove all ANTLR-generated files from src/compiler/generated; usage: make antlr-clear.
	@rm -rf $(GENERATED_DIR)/*

encrypt-flow: ## Run the full encryption flow for FILE=<file> from examples/ at ADDRESS=<addr>, producing build/out/enc_FILE.
	@mkdir -p $(OUT_DIR)
	@echo "=== Encryption Flow ==="
	@echo "Input file : $(EXAMPLES_DIR)/$(FILE)"
	@echo "Output file: $(OUT_DIR)/enc_$(FILE)"
	@echo "Address    : $(ADDRESS)"
	@rm -f $(ENC_MEM) build/sim/memory_dump.txt $(EXAMPLES_DIR)/enc_$(FILE)
	@SIZE=$$(wc -c < "$(EXAMPLES_DIR)/$(FILE)") ; \
	 echo "File size  : $$SIZE bytes" ; \
	 echo "" ; \
	 echo "[1/4] Switching program.hex to encrypt routine..." ; \
	 cp programs/hex/encrypt.hex programs/hex/program.hex ; \
	 echo "" ; \
	 echo "[2/4] Loading file into $(ENC_MEM)..." ; \
	 ./tools/load_file.py --input "$(EXAMPLES_DIR)/$(FILE)" --output $(ENC_MEM) --address $(ADDRESS) ; \
	 echo "" ; \
	 echo "[3/4] Running CPU simulation..." ; \
	 "$(MAKE)" sv-run-cpu ; \
	 echo "" ; \
	 echo "[4/4] Extracting result from memory_dump..." ; \
	 ./tools/extract_data.py --memory build/sim/memory_dump.txt --address $(ADDRESS) --size $$SIZE --output "$(OUT_DIR)/enc_$(FILE)" ; \
	 echo "" ; \
	 echo "=== Comparing original vs result ===" ; \
	 if cmp -s "$(EXAMPLES_DIR)/$(FILE)" "$(OUT_DIR)/enc_$(FILE)" ; then \
	     echo "[INFO] Files are IDENTICAL (no encryption applied to this region)" ; \
	 else \
	     echo "[OK] Files DIFFER (encryption modified the data)" ; \
	 fi

decrypt-flow: ## Run the full decryption flow for FILE=<file> from build/out at ADDRESS=<addr>, producing build/out/dec_FILE.
	@mkdir -p $(OUT_DIR)
	@echo "=== Decryption Flow ==="
	@echo "Input file : $(OUT_DIR)/$(FILE)"
	@echo "Output file: $(OUT_DIR)/dec_$(FILE)"
	@echo "Address    : $(ADDRESS)"
	@rm -f $(ENC_MEM) build/sim/memory_dump.txt $(OUT_DIR)/dec_$(FILE)
	@SIZE=$$(wc -c < "$(OUT_DIR)/$(FILE)") ; \
	 echo "File size  : $$SIZE bytes" ; \
	 echo "" ; \
	 echo "[1/4] Switching program.hex to decrypt routine..." ; \
	 cp programs/hex/decrypt.hex programs/hex/program.hex ; \
	 echo "" ; \
	 echo "[2/4] Loading file into $(ENC_MEM)..." ; \
	 ./tools/load_file.py --input "$(OUT_DIR)/$(FILE)" --output $(ENC_MEM) --address $(ADDRESS) ; \
	 echo "" ; \
	 echo "[3/4] Running CPU simulation..." ; \
	 "$(MAKE)" sv-run-cpu ; \
	 echo "" ; \
	 echo "[4/4] Extracting result from memory_dump..." ; \
	 ./tools/extract_data.py --memory build/sim/memory_dump.txt --address $(ADDRESS) --size $$SIZE --output "$(OUT_DIR)/dec_$(FILE)" ; \
	 echo "" ; \
	 echo "=== Result ==="

verify-roundtrip: ## Encrypt and then decrypt FILE=<file> from examples/, then compare the final output with the original; usage: make verify-roundtrip FILE=file.
	@mkdir -p $(OUT_DIR)
	@echo "=== Roundtrip Verification ==="
	@$(MAKE) encrypt-flow FILE=$(FILE)
	@$(MAKE) decrypt-flow FILE=enc_$(FILE)
	@echo ""
	@echo "=== Final comparison: original vs decrypted ==="
	@if cmp -s "$(EXAMPLES_DIR)/$(FILE)" "$(OUT_DIR)/dec_enc_$(FILE)" ; then \
	    echo "[PASS] Encryption/decryption is reversible — files match." ; \
	else \
	    echo "[FAIL] Decrypted file does NOT match the original." ; \
	fi

verify-roundtrip-tea: ## Build TEA encryption/decryption routines, activate them, and run roundtrip verification for FILE=<file>.
	@mkdir -p $(OUT_DIR)
	@echo "=== TEA Roundtrip Verification ==="
	@echo "[1/3] Building TEA assembly programs..."
	@$(MAKE) asm-build-tea_encrypt
	@$(MAKE) asm-build-tea_decrypt

	@echo ""
	@echo "[2/3] Switching to TEA hex files..."
	@cp programs/hex/tea_encrypt.hex programs/hex/encrypt.hex
	@cp programs/hex/tea_decrypt.hex programs/hex/decrypt.hex

	@echo ""
	@echo "[3/3] Running standard roundtrip..."
	@$(MAKE) verify-roundtrip FILE=$(FILE)

clear: ## Delete the entire build/ directory and all generated artifacts; usage: make clear.
	@echo "Cleaning build/ folder..."
	@rm -rf $(BUILD_DIR)
	@echo "build/ folder cleared."