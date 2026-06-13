#!/usr/bin/env python3
import argparse
import sys

def main():
    parser = argparse.ArgumentParser(description="Extract binary data from verilog memory dump")
    parser.add_argument("--memory", required=True)
    parser.add_argument("--address", required=True)
    parser.add_argument("--size", type=int, required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    start_addr = int(args.address, 16)
    word_index = start_addr // 4
    words_to_read = (args.size + 3) // 4
    memory_dict = {}
    current_idx = 0

    try:
        with open(args.memory, "r") as f_in:
            for line in f_in:
                line = line.split('//')[0].strip()
                if not line:
                    continue

                if line.startswith('@'):
                    current_idx = int(line[1:], 16)
                else:
                    for word in line.split():
                        # x/z are Verilog undefined values; treat as 0
                        clean_word = word.translate(str.maketrans('xXzZ', '0000'))
                        memory_dict[current_idx] = int(clean_word, 16)
                        current_idx += 1

        extracted_bytes = bytearray()
        for i in range(words_to_read):
            target_idx = word_index + i
            if target_idx in memory_dict:
                extracted_bytes.extend(memory_dict[target_idx].to_bytes(4, byteorder='little'))
            else:
                extracted_bytes.extend(b'\x00\x00\x00\x00')

        final_binary_data = extracted_bytes[:args.size]

        with open(args.output, "wb") as f_out:
            f_out.write(final_binary_data)

        print("status: extraction_complete")
        print(f"output: {args.output}")
        print(f"bytes: {len(final_binary_data)}")

    except Exception as e:
        print(f"error: {e}")

if __name__ == "__main__":
    main()