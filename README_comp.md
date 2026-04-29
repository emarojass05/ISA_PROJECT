# Setup
## Requisitos

- Python 3
- Java 17 o más reciente
- curl
- make
- python-pip, python-venv (cambia según distro)

### Herramienta ANTLR

Este proyecto usa una version de ANTLR fija para evitar conflictos en las versiones según el SO.

Versión requerida:

- ANTLR tool: 4.13.2
- Python runtime: antlr4-python3-runtime==4.13.2

**NOTA**: No usar los paquetes antlr4 del sistema para compilación

### Instalación

Para asegurar la correcta ejecución del compilador ejecutar de primera mano

```bash
make setup
make antlr-download
make check-env
```

### Ejecución

