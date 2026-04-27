from pathlib import Path
import re
import sys

BASE_DIR = Path(__file__).resolve().parents[3]
ASM_DIR = BASE_DIR / "programs" / "asm"
DEFAULT_ASM_FILE = ASM_DIR / "program.s"

OPCODES = {
    "add":  0x00,
    "sub":  0x00,
    "mul":  0x00,
    "div":  0x00,
    "rem":  0x00,
    "and":  0x00,
    "or":   0x00,
    "xor":  0x00,
    "sll":  0x00,
    "srl":  0x00,

    "addi": 0x01,
    "xori": 0x01,
    "slli": 0x01,
    "srli": 0x01,

    "sw":   0x02,
    "lw":   0x03,

    "beq":  0x04,
    "bne":  0x04,
    "bgt":  0x04,
    "blt":  0x04,
    "bge":  0x04,
    "ble":  0x04,

    "luhw": 0x05,
    "llhw": 0x05,

    "j":    0x07,
    "jal":  0x07,
    "jr":   0x07,
}

R_INFO = {
    "add": (0b000, 0b0000000),
    "sub": (0b001, 0b0000000),
    "mul": (0b000, 0b0000001),
    "div": (0b001, 0b0000001),
    "rem": (0b010, 0b0000001),
    "and": (0b010, 0b0000000),
    "or":  (0b011, 0b0000000),
    "xor": (0b100, 0b0000000),
    "sll": (0b101, 0b0000000),
    "srl": (0b110, 0b0000000),
}

I_INFO = {
    "addi": 0b000,
    "xori": 0b001,
    "slli": 0b010,
    "srli": 0b011,
    "lw":   0b100,
}

S_INFO = {
    "sw": 0b000,
}

B_INFO = {
    "beq": 0b000,
    "bne": 0b001,
    "bgt": 0b010,
    "blt": 0b011,
    "bge": 0b100,
    "ble": 0b101,
}

J_INFO = {
    "j":   0b000,
    "jal": 0b001,
    "jr":  0b010,
}

U_INFO = {
    "luhw": 0b000,
    "llhw": 0b001,
}

SEC_INSTRUCTIONS = {
    "auth",
    "ldk",
    "enc",
    "dec",
}

REG_ALIASES = {
    "zero": 0,
    "ra": 1,
    "sp": 2,
    "sr": 20,
    "delta": 30,
    "vp": 31,
}

for i in range(7):
    REG_ALIASES[f"a{i}"] = i + 3

for i in range(10):
    REG_ALIASES[f"s{i}"] = i + 10

for i in range(4):
    REG_ALIASES[f"s{i + 10}"] = i + 26

for i in range(5):
    REG_ALIASES[f"t{i}"] = i + 21


def parse_reg(reg):
    reg = reg.strip().lower()

    if reg in REG_ALIASES:
        return REG_ALIASES[reg]

    if not re.fullmatch(r"x\d+", reg):
        raise ValueError(f"Registro inválido: {reg}")

    num = int(reg[1:])

    if not 0 <= num <= 31:
        raise ValueError(f"Registro fuera de rango: {reg}")

    return num


def parse_imm(value):
    value = value.strip()
    return int(value, 0)


def check_range(value, bits, signed=False):
    if signed:
        min_val = -(1 << (bits - 1))
        max_val = (1 << (bits - 1)) - 1

        if not min_val <= value <= max_val:
            raise ValueError(f"Inmediato {value} fuera de rango signed {bits}-bit")

        return value & ((1 << bits) - 1)

    max_val = (1 << bits) - 1

    if not 0 <= value <= max_val:
        raise ValueError(f"Inmediato {value} fuera de rango unsigned {bits}-bit")

    return value


def clean_line(line):
    line = line.split("#", 1)[0]
    line = line.split("//", 1)[0]
    return line.strip()


def split_args(args):
    if not args.strip():
        return []

    return [arg.strip() for arg in args.split(",")]


def expect_args(op, args, expected):
    if len(args) != expected:
        raise ValueError(
            f"{op} espera {expected} argumento(s), recibió {len(args)}"
        )


def remove_labels(line, labels=None, pc=None):
    line = clean_line(line)

    while True:
        match = re.match(r"^([A-Za-z_]\w*)\s*:", line)

        if not match:
            break

        label = match.group(1)

        if labels is not None:
            if label in labels:
                raise ValueError(f"Etiqueta duplicada: {label}")

            labels[label] = pc

        line = line[match.end():].strip()

    return line


def instruction_count(line):
    line = clean_line(line)

    if not line:
        return 0

    op = line.split(maxsplit=1)[0].lower()

    if op == "li":
        return 2

    return 1


def build_labels(source):
    labels = {}
    instructions = []
    pc = 0

    for line_number, original_line in enumerate(source.splitlines(), start=1):
        try:
            line = remove_labels(original_line, labels, pc)

            if not line:
                continue

            instructions.append((line_number, line, pc))
            pc += instruction_count(line) * 4

        except Exception as e:
            raise ValueError(f"Error en línea {line_number}: {original_line}\n{e}")

    return labels, instructions


def resolve_offset(token, labels, pc):
    token = token.strip()

    try:
        return parse_imm(token)
    except ValueError:
        pass

    if token not in labels:
        raise ValueError(f"Etiqueta no encontrada: {token}")

    return labels[token] - pc


def parse_mem_operand(mem):
    compact = mem.replace(" ", "")
    match = re.fullmatch(r"(.+)\(([^()]+)\)", compact)

    if not match:
        raise ValueError(f"Formato de memoria inválido: {mem}")

    imm = parse_imm(match.group(1))
    rs1 = parse_reg(match.group(2))

    return imm, rs1


def encode_r_type(op, rd, rs1, rs2):
    opcode = OPCODES[op]
    funct3, funct7 = R_INFO[op]

    return (
        (funct7 << 25)
        | (rs2 << 20)
        | (rs1 << 15)
        | (funct3 << 12)
        | (rd << 7)
        | opcode
    )


def encode_i_type(op, rd, rs1, imm):
    opcode = OPCODES[op]
    funct3 = I_INFO[op]
    imm = check_range(imm, 12, signed=True)

    return (
        (imm << 20)
        | (rs1 << 15)
        | (funct3 << 12)
        | (rd << 7)
        | opcode
    )


def encode_s_like_type(opcode, funct3, rs2, rs1, imm):
    imm = check_range(imm, 12, signed=True)

    imm_low = imm & 0b11111
    imm_high = (imm >> 5) & 0b1111111

    return (
        (imm_high << 25)
        | (rs2 << 20)
        | (rs1 << 15)
        | (funct3 << 12)
        | (imm_low << 7)
        | opcode
    )


def encode_s_type(op, rs2, rs1, imm):
    opcode = OPCODES[op]
    funct3 = S_INFO[op]

    return encode_s_like_type(opcode, funct3, rs2, rs1, imm)


def encode_b_type(op, rs1, rs2, imm):
    opcode = OPCODES[op]
    funct3 = B_INFO[op]

    return encode_s_like_type(opcode, funct3, rs2, rs1, imm)


def encode_j_type(op, rs1, rs2, imm):
    opcode = OPCODES[op]
    funct3 = J_INFO[op]

    return encode_s_like_type(opcode, funct3, rs2, rs1, imm)


def encode_u_type(op, rd, imm):
    opcode = OPCODES[op]
    funct3 = U_INFO[op]
    imm = check_range(imm, 16, signed=False)

    return (
        (imm << 16)
        | (funct3 << 12)
        | (rd << 7)
        | opcode
    )


def encode_line(line, pc, labels):
    line = remove_labels(line)

    if not line:
        return []

    parts = line.split(maxsplit=1)
    op = parts[0].lower()
    args_text = parts[1] if len(parts) > 1 else ""
    args = split_args(args_text)

    if op == "nop":
        expect_args(op, args, 0)
        return [encode_i_type("addi", 0, 0, 0)]

    if op == "mv":
        expect_args(op, args, 2)
        rd = parse_reg(args[0])
        rs = parse_reg(args[1])
        return [encode_i_type("addi", rd, rs, 0)]

    if op == "li":
        expect_args(op, args, 2)

        rd = parse_reg(args[0])
        imm = parse_imm(args[1])

        if not -(1 << 31) <= imm <= (1 << 32) - 1:
            raise ValueError(f"Inmediato {imm} fuera de rango de 32 bits")

        imm32 = imm & 0xFFFFFFFF
        upper = (imm32 >> 16) & 0xFFFF
        lower = imm32 & 0xFFFF

        return [
            encode_u_type("luhw", rd, upper),
            encode_u_type("llhw", rd, lower),
        ]

    if op == "call":
        expect_args(op, args, 1)
        offset = resolve_offset(args[0], labels, pc)
        return [encode_j_type("jal", 0, parse_reg("x1"), offset)]

    if op == "ret":
        expect_args(op, args, 0)
        return [encode_j_type("jr", parse_reg("x1"), 0, 0)]

    if op in R_INFO:
        expect_args(op, args, 3)

        rd = parse_reg(args[0])
        rs1 = parse_reg(args[1])
        rs2 = parse_reg(args[2])

        return [encode_r_type(op, rd, rs1, rs2)]

    if op in I_INFO and op != "lw":
        expect_args(op, args, 3)

        rd = parse_reg(args[0])
        rs1 = parse_reg(args[1])
        imm = parse_imm(args[2])

        return [encode_i_type(op, rd, rs1, imm)]

    if op == "lw":
        expect_args(op, args, 2)

        rd = parse_reg(args[0])
        imm, rs1 = parse_mem_operand(args[1])

        return [encode_i_type(op, rd, rs1, imm)]

    if op == "sw":
        expect_args(op, args, 2)

        rs2 = parse_reg(args[0])
        imm, rs1 = parse_mem_operand(args[1])

        return [encode_s_type(op, rs2, rs1, imm)]

    if op in B_INFO:
        expect_args(op, args, 3)

        rs1 = parse_reg(args[0])
        rs2 = parse_reg(args[1])
        offset = resolve_offset(args[2], labels, pc)

        return [encode_b_type(op, rs1, rs2, offset)]

    if op == "j":
        expect_args(op, args, 1)

        offset = resolve_offset(args[0], labels, pc)

        return [encode_j_type(op, 0, 0, offset)]

    if op == "jal":
        expect_args(op, args, 2)

        rs2 = parse_reg(args[0])
        offset = resolve_offset(args[1], labels, pc)

        return [encode_j_type(op, 0, rs2, offset)]

    if op == "jr":
        expect_args(op, args, 1)

        rs1 = parse_reg(args[0])

        return [encode_j_type(op, rs1, 0, 0)]

    if op in U_INFO:
        expect_args(op, args, 2)

        rd = parse_reg(args[0])
        imm = parse_imm(args[1])

        return [encode_u_type(op, rd, imm)]

    if op in SEC_INSTRUCTIONS:
        raise ValueError(
            f"La instrucción SEC '{op}' no tiene formato definido todavía en la ISA"
        )

    raise ValueError(f"Instrucción no soportada: {op}")


def assemble(source):
    labels, instructions = build_labels(source)
    machine_code = []

    for line_number, line, pc in instructions:
        try:
            encoded_list = encode_line(line, pc, labels)

            for encoded in encoded_list:
                machine_code.append(f"{encoded & 0xFFFFFFFF:08x}")

        except Exception as e:
            raise ValueError(f"Error en línea {line_number}: {line}\n{e}")

    return machine_code


def resolve_asm_file(program_name):
    if program_name is None:
        return DEFAULT_ASM_FILE

    path = Path(program_name)
    candidates = []

    if path.is_absolute():
        candidates.append(path)
    else:
        candidates.append(Path.cwd() / path)
        candidates.append(ASM_DIR / path)

        if path.suffix == "":
            candidates.append(Path.cwd() / f"{program_name}.s")
            candidates.append(Path.cwd() / f"{program_name}.asm")
            candidates.append(ASM_DIR / f"{program_name}.s")
            candidates.append(ASM_DIR / f"{program_name}.asm")

    for candidate in candidates:
        if candidate.exists():
            return candidate

    raise FileNotFoundError(
        "No se encontró el archivo ASM. Rutas probadas:\n"
        + "\n".join(str(c) for c in candidates)
    )


def main():
    program_name = sys.argv[1] if len(sys.argv) >= 2 else None
    filename = resolve_asm_file(program_name)

    with open(filename, "r", encoding="utf-8") as f:
        source = f.read()

    machine_code = assemble(source)

    for code in machine_code:
        print(code)


if __name__ == "__main__":
    main()