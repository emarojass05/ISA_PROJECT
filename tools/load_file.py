#!/usr/bin/env python3
import argparse
import os

def main():
    # argument_configuration
    parser = argparse.ArgumentParser(description="Convert binary file to verilog memory format")
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--address", required=True)
    args = parser.parse_args()

    # memory_offset_calculation
    start_addr = int(args.address, 16)
    word_index = start_addr // 4

    try:
        # binary_to_hex_conversion
        with open(args.input, "rb") as f_in, open(args.output, "w") as f_out:
            # write_address_pointer
            f_out.write(f"@{word_index:X}\n")
            
            while True:
                # read_32bit_chunk
                chunk = f_in.read(4)
                if not chunk:
                    break
                
                # apply_padding_if_needed
                if len(chunk) < 4:
                    chunk += b'\x00' * (4 - len(chunk))

                # convert_to_little_endian_hex
                word_value = int.from_bytes(chunk, byteorder='little')
                f_out.write(f"{word_value:08X}\n")

        # completion_status
        print("process_status: conversion_complete")
        print(f"input_path: {args.input}")
        print(f"output_path: {args.output}")

    except Exception as e:
        print(f"execution_error: {e}")

if __name__ == "__main__":
    main()