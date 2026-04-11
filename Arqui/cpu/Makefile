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
# Default
# =========================

all: run_register

# =========================
# REGISTER FILE
# =========================

build_register:
	mkdir -p $(SIM_DIR)
	$(IVERILOG) $(FLAGS) -o $(SIM_DIR)/register_file.vvp \
	$(SRC_DIR)/register_file.sv \
	$(TB_DIR)/tb_register_file.sv

run_register: build_register
	$(VVP) $(SIM_DIR)/register_file.vvp

# =========================
# ALU
# =========================

build_alu:
	mkdir -p $(SIM_DIR)
	$(IVERILOG) $(FLAGS) -o $(SIM_DIR)/alu.vvp \
	$(SRC_DIR)/alu.sv \
	$(TB_DIR)/tb_alu.sv

run_alu: build_alu
	$(VVP) $(SIM_DIR)/alu.vvp

# =========================
# PROGRAM COUNTER (PC)
# =========================

build_pc:
	mkdir -p $(SIM_DIR)
	$(IVERILOG) $(FLAGS) -o $(SIM_DIR)/pc.vvp \
	$(SRC_DIR)/program_counter.sv \
	$(SRC_DIR)/pc_adder.sv \
	$(TB_DIR)/tb_pc.sv

run_pc: build_pc
	$(VVP) $(SIM_DIR)/pc.vvp

# =========================
# INSTRUCTION MEMORY
# =========================

build_imem:
	mkdir -p $(SIM_DIR)
	$(IVERILOG) $(FLAGS) -o $(SIM_DIR)/imem.vvp \
	$(SRC_DIR)/instruction_memory.sv \
	$(TB_DIR)/tb_instruction_memory.sv

run_imem: build_imem
	$(VVP) $(SIM_DIR)/imem.vvp

# =========================
# DECODER
# =========================

build_decoder:
	mkdir -p $(SIM_DIR)
	$(IVERILOG) $(FLAGS) -o $(SIM_DIR)/decoder.vvp \
	$(SRC_DIR)/decoder.sv \
	$(TB_DIR)/tb_decoder.sv

run_decoder: build_decoder
	$(VVP) $(SIM_DIR)/decoder.vvp

# =========================
# LIMPIAR
# =========================

clean:
	rm -rf $(SIM_DIR)