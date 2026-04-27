#!/usr/bin/env python3
import argparse
import os

def load_file(input_file, output_file, start_address):
    if not os.path.exists(input_file):
        print(f"[ERROR] Archivo no encontrado: {input_file}")
        return

    # Leer archivo en binario
    with open(input_file, "rb") as f:
        data = f.read()

    size = len(data)

    # Crear archivo .mem
    with open(output_file, "w") as f:
        # Relleno hasta dirección base
        for _ in range(start_address):
            f.write("00\n")

        # Escribir bytes en hex
        for byte in data:
            f.write(f"{byte:02X}\n")

    print("\n===== LOAD FILE =====")
    print(f"Archivo entrada  : {input_file}")
    print(f"Tamaño           : {size} bytes")
    print(f"Dirección inicio : {hex(start_address)}")
    print(f"Dirección final  : {hex(start_address + size - 1)}")
    print(f"Archivo generado : {output_file}\n")


def main():
    parser = argparse.ArgumentParser(description="Cargar archivo a memoria (.mem)")
    parser.add_argument("--input", required=True, help="Archivo de entrada")
    parser.add_argument("--output", required=True, help="Archivo .mem de salida")
    parser.add_argument("--address", required=True, help="Dirección base (ej: 0x1000)")

    args = parser.parse_args()

    try:
        start_address = int(args.address, 16)
    except ValueError:
        print("[ERROR] Dirección inválida. Use formato hexadecimal, ej: 0x1000")
        return

    load_file(args.input, args.output, start_address)


if __name__ == "__main__":
    main()