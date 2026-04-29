# Proyecto Grupal I CE4301

Arquitectura del Set de Instrucciones (ISA) Específica tipo RISC para Aplicaciones de Seguridad Informática

# Estructura del Proyecto

```
.
├── build
│   ├── compiler # Salidas compilador
│   └── sim # Simulaciones iverilog
├── docs
├── LICENSE
├── Makefile
├── programs
│   ├── asm # Programas en ensamblador
│   ├── hex # Programas .hex ejecutables
│   └── source # Código fuente en lenguaje propio (CE1108)
├── README.md
├── src
│   ├── compiler # Compilador (CE1108)
│   └── cpu # Implementación microarquitectura
├── tb # Testbenches de la microarquitectura
└── tools # Herramientas y paquetes (antlr)
```

# Setup
## Requisitos

- make
- iverilog
- python3
- gtkwave

## Compilación y Ejecución

### Compilación de módulos

Se puede usar el comando `make` en la raíz del repositorio para ver todos los targets disponibles. Los principales para la ejecución de lo relacionado al ISA y la microarquitectura son

```
make sv-run-<module>
```

Compilación de un módulo y ejecución de su testbench asociado.

```
make wave-<wavefile>
```

Abrir archivo .vcd con GTKWave