#!/usr/bin/env python3
import argparse
import os

def main():
    parser = argparse.ArgumentParser(description="Convert binary file to verilog memory format")
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--address", required=True)
    args = parser.parse_args()

    start_addr = int(args.address, 16)
    word_index = start_addr // 4

    try:
        with open(args.input, "rb") as f_in, open(args.output, "w") as f_out:
            f_out.write(f"@{word_index:X}\n")

            while True:
                chunk = f_in.read(4)
                if not chunk:
                    break

                if len(chunk) < 4:
                    chunk += b'\x00' * (4 - len(chunk))

                word_value = int.from_bytes(chunk, byteorder='little')
                f_out.write(f"{word_value:08X}\n")

        print("status: conversion_complete")
        print(f"input: {args.input}")
        print(f"output: {args.output}")

    except Exception as e:
        print(f"error: {e}")

if __name__ == "__main__":
    main()