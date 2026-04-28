# =========================
# Toolchain
# =========================

IVERILOG = iverilog
VVP = vvp
FLAGS = -g2012
GTK_WAVE = gtkwave

# =========================
# Folders
# =========================
BUILD_DIR = build
CPU_SRC_DIR = src/cpu
TB_DIR  = tb
SIM_DIR = sim
SIM_BUILD = $(BUILD_DIR)/sim
BIN_DIR = $(BUILD_DIR)/bin
PROGRAMS_DIR = programs

# =========================
# CPU Modules
# =========================
ISA_DEFS = $(CPU_SRC_DIR)/isa_defs.sv
CPU_MODS = $(filter-out $(ISA_DEFS), $(wildcard $(CPU_SRC_DIR)/*.sv))
CPU_SRC = $(ISA_DEFS) $(CPU_MODS)

# =========================
# Default
# =========================

.PHONY: all help

all: help

help:
	@echo "Available targets:"
	@grep -E '^[a-zA-Z0-9_%-.]+:.*?## ' $(MAKEFILE_LIST) | \
	awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

sv-cbuild-%: $(CPU_SRC) $(TB_DIR)/tb_%.sv ## Build single CPU module with it's testbench
	mkdir -p $(SIM_BUILD)
	$(IVERILOG) $(FLAGS) -s tb_$* -o $(SIM_BUILD)/$*.vvp $^

sv-run-%: sv-cbuild-% ## Run VPP for a specified .vvp output file
	$(VVP) $(SIM_BUILD)/$*.vvp

gtk-%: $(SIM_BUILD)/%.vcd ## Run %.vcd file from build/sim
	gtkwave $^

clear: ## Clear outputs folder(s)
	rm -rf $(SIM_BUILD)