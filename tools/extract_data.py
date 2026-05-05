#!/usr/bin/env python3
import argparse
import sys

def main():
    # command_line_arguments
    parser = argparse.ArgumentParser(description="Extract binary data from verilog memory dump")
    parser.add_argument("--memory", required=True)
    parser.add_argument("--address", required=True)
    parser.add_argument("--size", type=int, required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    # memory_mapping_parameters
    start_addr = int(args.address, 16)
    word_index = start_addr // 4
    words_to_read = (args.size + 3) // 4
    memory_dict = {}
    current_idx = 0

    try:
        # parse_verilog_memory_dump
        with open(args.memory, "r") as f_in:
            for line in f_in:
                # remove_comments_and_whitespace
                line = line.split('//')[0].strip()
                if not line:
                    continue
                
                # update_current_address_pointer
                if line.startswith('@'):
                    current_idx = int(line[1:], 16)
                else:
                    # store_data_words_in_map
                    for word in line.split():
                        # sanitize_undefined_values
                        clean_word = word.translate(str.maketrans('xXzZ', '0000'))
                        memory_dict[current_idx] = int(clean_word, 16)
                        current_idx += 1

        # sequential_byte_reconstruction
        extracted_bytes = bytearray()
        for i in range(words_to_read):
            target_idx = word_index + i
            if target_idx in memory_dict:
                # convert_hex_word_to_bytes
                extracted_bytes.extend(memory_dict[target_idx].to_bytes(4, byteorder='little'))
            else:
                # fill_missing_addresses_with_null
                extracted_bytes.extend(b'\x00\x00\x00\x00')

        # truncate_to_exact_size
        final_binary_data = extracted_bytes[:args.size]
        
        # write_result_to_file
        with open(args.output, "wb") as f_out:
            f_out.write(final_binary_data)

        # completion_status
        print("process_status: extraction_complete")
        print(f"output_path: {args.output}")
        print(f"total_bytes: {len(final_binary_data)}")

    except Exception as e:
        print(f"execution_error: {e}")

if __name__ == "__main__":
    main()