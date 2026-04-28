import argparse
import os

def load_file(input_file, output_file, start_address):
    if not os.path.exists(input_file):
        print(f"[ERROR] File not found: {input_file}")
        return

    # Read file in binary mode
    with open(input_file, "rb") as f:
        data = f.read()

    size = len(data)

    # Create .mem file
    with open(output_file, "w") as f:
        # Padding up to base address
        for _ in range(start_address):
            f.write("00\n")

        # Write bytes in hex format
        for byte in data:
            f.write(f"{byte:02X}\n")

    print("\n===== LOAD FILE =====")
    print(f"Input file      : {input_file}")
    print(f"Size            : {size} bytes")
    print(f"Start address   : {hex(start_address)}")
    print(f"End address     : {hex(start_address + size - 1)}")
    print(f"Generated file  : {output_file}\n")


def main():
    parser = argparse.ArgumentParser(description="Load file into memory (.mem)")
    parser.add_argument("--input", required=True, help="Input file")
    parser.add_argument("--output", required=True, help="Output .mem file")
    parser.add_argument("--address", required=True, help="Base address (e.g., 0x1000)")

    args = parser.parse_args()

    try:
        start_address = int(args.address, 16)
    except ValueError:
        print("[ERROR] Invalid address. Use hexadecimal format, e.g., 0x1000")
        return

    load_file(args.input, args.output, start_address)


if __name__ == "__main__":
    main()