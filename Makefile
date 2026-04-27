# =========================
# Toolchain
# =========================

IVERILOG = iverilog
VVP = vvp
FLAGS = -g2012
ANTLR=antlr4

# =========================
# Folders
# =========================
BUILD_DIR = build
SIM_DIR = sim
SIM_BUILD = $(BUILD_DIR)/sim
COMPILER_BUILD = $(BUILD_DIR)/programs # Programs built with compiler
BIN_DIR = $(BUILD_DIR)/bin

CPU_SRC_DIR = src/cpu
TB_DIR  = tb

GRAMMAR_DIR =src/compiler/grammar
FRC_SRC_DIR = programs/source
GENERATED_DIR =src/compiler/generated

# =========================
# Compiler Files
# =========================
GRAMMAR =Language.g4
FRC_COMPILER = src.compiler.main
PYTHON = python3
ASM_ENCODER = src/compiler/backend/encoder.py
ASM_DIR = programs/asm
HEX_DIR = programs/hex

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

antlr-build: ## Build ANTLR modules
	cd $(GRAMMAR_DIR) && $(ANTLR) -Dlanguage=Python3 -visitor -o ../generated $(GRAMMAR)

antlr-clear: ## Clear ANTLR output folder(s)
	@rm -rf $(GENERATED_DIR)

frc-parse-%: antlr-build ## Parse .fr source file from programs/source
	@mkdir -p $(GENERATED_DIR)
	@touch src/__init__.py
	@touch src/compiler/__init__.py
	@touch src/compiler/generated/__init__.py
	python -m  $(FRC_COMPILER) $(FRC_SRC_DIR)/$*.fr


asm-encode-%: ## Encode programs/asm/%.s and print hexadecimal output
	$(PYTHON) $(ASM_ENCODER) $*

asm-build-%: ## Encode programs/asm/%.s and save output into programs/hex/%.hex
	@mkdir -p $(HEX_DIR)
	$(PYTHON) $(ASM_ENCODER) $* > $(HEX_DIR)/$*.hex