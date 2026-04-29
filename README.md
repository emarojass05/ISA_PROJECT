# Proyecto Grupal I CE4301 - Arquitectura del Set de Instrucciones (ISA) Específica tipo RISC para Aplicacines de Seguridad Informática


## Estructura del Proyecto
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
└── tb # Testbenches de la microarquitectura
```

## Setup

### Requisitos

- Python 3
- Java 17 o más reciente
- curl
- make

#### Herramienta ANTLR

Este proyecto usa una version de ANTLR fija para evitar conflictos en las versiones según el SO.

Versión requerida:

- ANTLR tool: 4.13.2
- Python runtime: antlr4-python3-runtime==4.13.2

**NOTA**: No usar los paquetes antlr4 del sistema.

## Instalación

```bash
make setup
make antlr-download
make check-env
```

## Compilación y Ejecución

