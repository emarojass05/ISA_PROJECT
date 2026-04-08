# =========================
# Makefile CPU
# =========================

# Archivos
SRC = src/register_file.sv
TB  = testbenches/tb_register_file.sv

# Output
OUT = sim/register_file.vvp
VCD = sim/register_file.vcd

# Compilador
IVERILOG = iverilog
VVP = vvp

# -------------------------
# Default
# -------------------------
all: run

# -------------------------
# Compilar
# -------------------------
build:
	mkdir -p sim
	$(IVERILOG) -g2012 -o $(OUT) $(SRC) $(TB)
# -------------------------
# Ejecutar
# -------------------------
run: build
	$(VVP) $(OUT)

# -------------------------
# Limpiar
# -------------------------
clean:
	rm -rf sim