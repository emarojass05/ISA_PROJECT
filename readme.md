Para correr la herramienta de carga de archivos:
    python tools/extract_data.py \
    --memory <mem_file> \
    --address <hex_address> \
    --size <num_bytes> \
    --output <output_file>

    Ejemplo:

    python3 tools/load_file.py \
    --input programs/test.txt \
    --output programs/mems/memory.mem \
    --address 0x0
