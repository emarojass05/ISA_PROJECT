# =========================
# Configuración
# =========================

IVERILOG = iverilog
VVP = vvp
FLAGS = -g2012

SRC_DIR = src
TB_DIR  = testbenches
SIM_DIR = sim

# =========================
# Targets disponibles
# =========================

# Default
all: run_register

# -------------------------
# REGISTER FILE
# -------------------------
build_register:
	mkdir -p $(SIM_DIR)
	$(IVERILOG) $(FLAGS) -o $(SIM_DIR)/register_file.vvp \
	$(SRC_DIR)/register_file.sv \
	$(TB_DIR)/tb_register_file.sv

run_register: build_register
	$(VVP) $(SIM_DIR)/register_file.vvp

# -------------------------
# ALU
# -------------------------
build_alu:
	mkdir -p $(SIM_DIR)
	$(IVERILOG) $(FLAGS) -o $(SIM_DIR)/alu.vvp \
	$(SRC_DIR)/alu.sv \
	$(TB_DIR)/tb_alu.sv

run_alu: build_alu
	$(VVP) $(SIM_DIR)/alu.vvp

# -------------------------
# Limpiar
# -------------------------
clean:
	rm -rf $(SIM_DIR)