import argparse
import os

def extract_data(mem_file, output_file, start_address, size):
    if not os.path.exists(mem_file):
        print(f"[ERROR] File not found: {mem_file}")
        return

    # Read memory file
    with open(mem_file, "r") as f:
        lines = f.readlines()

    if start_address + size > len(lines):
        print("[ERROR] Requested range exceeds memory size")
        return

    data = []

    for i in range(start_address, start_address + size):
        try:
            byte = int(lines[i].strip(), 16)
            data.append(byte)
        except ValueError:
            print(f"[ERROR] Invalid line in memory: {lines[i]}")
            return

    # Write binary output file
    with open(output_file, "wb") as f:
        f.write(bytearray(data))

    print("\n===== EXTRACT DATA =====")
    print(f"Memory file     : {mem_file}")
    print(f"Start address   : {hex(start_address)}")
    print(f"Size            : {size} bytes")
    print(f"Output file     : {output_file}\n")


def main():
    parser = argparse.ArgumentParser(description="Extract data from memory (.mem)")
    parser.add_argument("--memory", required=True, help="Input .mem file")
    parser.add_argument("--output", required=True, help="Output binary file")
    parser.add_argument("--address", required=True, help="Base address (e.g., 0x1000)")
    parser.add_argument("--size", required=True, help="Number of bytes to extract")

    args = parser.parse_args()

    try:
        start_address = int(args.address, 16)
        size = int(args.size)
    except ValueError:
        print("[ERROR] Invalid address or size")
        return

    extract_data(args.memory, args.output, start_address, size)


if __name__ == "__main__":
    main()