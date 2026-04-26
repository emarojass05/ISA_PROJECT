#!/usr/bin/env python3
import argparse
import os

def extract_data(mem_file, output_file, start_address, size):
    if not os.path.exists(mem_file):
        print(f"[ERROR] Archivo no encontrado: {mem_file}")
        return

    # Leer memoria
    with open(mem_file, "r") as f:
        lines = f.readlines()

    if start_address + size > len(lines):
        print("[ERROR] El rango solicitado excede el tamaño de la memoria")
        return

    data = []

    for i in range(start_address, start_address + size):
        try:
            byte = int(lines[i].strip(), 16)
            data.append(byte)
        except ValueError:
            print(f"[ERROR] Línea inválida en memoria: {lines[i]}")
            return

    # Escribir archivo binario
    with open(output_file, "wb") as f:
        f.write(bytearray(data))

    print("\n===== EXTRACT DATA =====")
    print(f"Archivo memoria  : {mem_file}")
    print(f"Dirección inicio : {hex(start_address)}")
    print(f"Tamaño           : {size} bytes")
    print(f"Archivo salida   : {output_file}\n")


def main():
    parser = argparse.ArgumentParser(description="Extraer datos desde memoria (.mem)")
    parser.add_argument("--memory", required=True, help="Archivo .mem de entrada")
    parser.add_argument("--output", required=True, help="Archivo binario de salida")
    parser.add_argument("--address", required=True, help="Dirección base (ej: 0x1000)")
    parser.add_argument("--size", required=True, help="Cantidad de bytes a extraer")

    args = parser.parse_args()

    try:
        start_address = int(args.address, 16)
        size = int(args.size)
    except ValueError:
        print("[ERROR] Dirección o tamaño inválido")
        return

    extract_data(args.memory, args.output, start_address, size)


if __name__ == "__main__":
    main()