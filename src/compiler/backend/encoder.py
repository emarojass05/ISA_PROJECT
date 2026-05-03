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

    # Security extension (OP_SEC = 0x06)
    "auth": 0x06,
    "ldk":  0x06,
    "addk": 0x06,
    "xork": 0x06,
    "tea":  0x06
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

SEC_INFO = {
    "auth": 0b000,
    "ldk":  0b001,
    "addk": 0b010,
    "xork": 0b011,
    "tea":  0b100,
}

REGISTER_ALIASES = {
    "zero": 0,
    "ra": 1,
    "sp": 2,
    "sr": 20,
    "delta": 30,
    "vp": 31,
}

for i in range(7):
    REGISTER_ALIASES[f"a{i}"] = i + 3

for i in range(10):
    REGISTER_ALIASES[f"s{i}"] = i + 10

for i in range(4):
    REGISTER_ALIASES[f"s{i + 10}"] = i + 26

for i in range(5):
    REGISTER_ALIASES[f"t{i}"] = i + 21


def parse_register(register):
    register = register.strip().lower()

    if register in REGISTER_ALIASES:
        return REGISTER_ALIASES[register]

    if not re.fullmatch(r"x\d+", register):
        raise ValueError(f"Invalid register: {register}")

    register_number = int(register[1:])

    if not 0 <= register_number <= 31:
        raise ValueError(f"Register out of range: {register}")

    return register_number


def parse_immediate(value):
    value = value.strip()
    return int(value, 0)


def check_range(value, bits, signed=False):
    if signed:
        min_value = -(1 << (bits - 1))
        max_value = (1 << (bits - 1)) - 1

        if not min_value <= value <= max_value:
            raise ValueError(f"Immediate {value} is out of signed {bits}-bit range")

        return value & ((1 << bits) - 1)

    max_value = (1 << bits) - 1

    if not 0 <= value <= max_value:
        raise ValueError(f"Immediate {value} is out of unsigned {bits}-bit range")

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
            f"{op} expects {expected} argument(s), got {len(args)}"
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
                raise ValueError(f"Duplicate label: {label}")

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

        except Exception as error:
            raise ValueError(f"Error on line {line_number}: {original_line}\n{error}")

    return labels, instructions


def resolve_offset(token, labels, pc):
    token = token.strip()

    try:
        return parse_immediate(token)
    except ValueError:
        pass

    if token not in labels:
        raise ValueError(f"Label not found: {token}")

    return labels[token] - pc


def parse_memory_operand(memory_operand):
    compact_operand = memory_operand.replace(" ", "")
    match = re.fullmatch(r"(.+)\(([^()]+)\)", compact_operand)

    if not match:
        raise ValueError(f"Invalid memory format: {memory_operand}")

    immediate = parse_immediate(match.group(1))
    rs1 = parse_register(match.group(2))

    return immediate, rs1


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


def encode_i_type(op, rd, rs1, immediate):
    opcode = OPCODES[op]
    funct3 = I_INFO[op]
    immediate = check_range(immediate, 12, signed=True)

    return (
        (immediate << 20)
        | (rs1 << 15)
        | (funct3 << 12)
        | (rd << 7)
        | opcode
    )


def encode_s_like_type(opcode, funct3, rs2, rs1, immediate):
    immediate = check_range(immediate, 12, signed=True)

    immediate_low = immediate & 0b11111
    immediate_high = (immediate >> 5) & 0b1111111

    return (
        (immediate_high << 25)
        | (rs2 << 20)
        | (rs1 << 15)
        | (funct3 << 12)
        | (immediate_low << 7)
        | opcode
    )


def encode_s_type(op, rs2, rs1, immediate):
    opcode = OPCODES[op]
    funct3 = S_INFO[op]

    return encode_s_like_type(opcode, funct3, rs2, rs1, immediate)


def encode_b_type(op, rs1, rs2, immediate):
    opcode = OPCODES[op]
    funct3 = B_INFO[op]

    return encode_s_like_type(opcode, funct3, rs2, rs1, immediate)


def encode_j_type(op, rs1, rs2, immediate):
    opcode = OPCODES[op]
    funct3 = J_INFO[op]

    return encode_s_like_type(opcode, funct3, rs2, rs1, immediate)


def encode_u_type(op, rd, immediate):
    opcode = OPCODES[op]
    funct3 = U_INFO[op]
    immediate = check_range(immediate, 16, signed=False)

    return (
        (immediate << 16)
        | (funct3 << 12)
        | (rd << 7)
        | opcode
    )

def encode_sec_type(op, rd, rs1, rs2):
    # SEC instructions follow R-type layout: funct7=0 | rs2 | rs1 | funct3 | rd | opcode
    opcode = OPCODES[op]
    funct3 = SEC_INFO[op]

    return (
        (rs2 << 20)
        | (rs1 << 15)
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
        rd = parse_register(args[0])
        rs = parse_register(args[1])
        return [encode_i_type("addi", rd, rs, 0)]

    if op == "li":
        expect_args(op, args, 2)

        rd = parse_register(args[0])
        immediate = parse_immediate(args[1])

        if not -(1 << 31) <= immediate <= (1 << 32) - 1:
            raise ValueError(f"Immediate {immediate} is out of 32-bit range")

        immediate_32 = immediate & 0xFFFFFFFF
        upper = (immediate_32 >> 16) & 0xFFFF
        lower = immediate_32 & 0xFFFF

        return [
            encode_u_type("luhw", rd, upper),
            encode_u_type("llhw", rd, lower),
        ]

    if op == "call":
        expect_args(op, args, 1)
        offset = resolve_offset(args[0], labels, pc)
        return [encode_j_type("jal", 0, parse_register("x1"), offset)]

    if op == "ret":
        expect_args(op, args, 0)
        return [encode_j_type("jr", parse_register("x1"), 0, 0)]

    if op in R_INFO:
        expect_args(op, args, 3)

        rd = parse_register(args[0])
        rs1 = parse_register(args[1])
        rs2 = parse_register(args[2])

        return [encode_r_type(op, rd, rs1, rs2)]

    if op in I_INFO and op != "lw":
        expect_args(op, args, 3)

        rd = parse_register(args[0])
        rs1 = parse_register(args[1])
        immediate = parse_immediate(args[2])

        return [encode_i_type(op, rd, rs1, immediate)]

    if op == "lw":
        expect_args(op, args, 2)

        rd = parse_register(args[0])
        immediate, rs1 = parse_memory_operand(args[1])

        return [encode_i_type(op, rd, rs1, immediate)]

    if op == "sw":
        expect_args(op, args, 2)

        rs2 = parse_register(args[0])
        immediate, rs1 = parse_memory_operand(args[1])

        return [encode_s_type(op, rs2, rs1, immediate)]

    if op in B_INFO:
        expect_args(op, args, 3)

        rs1 = parse_register(args[0])
        rs2 = parse_register(args[1])
        offset = resolve_offset(args[2], labels, pc)

        return [encode_b_type(op, rs1, rs2, offset)]

    if op == "j":
        expect_args(op, args, 1)

        offset = resolve_offset(args[0], labels, pc)

        return [encode_j_type(op, 0, 0, offset)]

    if op == "jal":
        expect_args(op, args, 2)

        rs2 = parse_register(args[0])
        offset = resolve_offset(args[1], labels, pc)

        return [encode_j_type(op, 0, rs2, offset)]

    if op == "jr":
        expect_args(op, args, 1)

        rs1 = parse_register(args[0])

        return [encode_j_type(op, rs1, 0, 0)]

    if op in U_INFO:
        expect_args(op, args, 2)

        rd = parse_register(args[0])
        immediate = parse_immediate(args[1])

        return [encode_u_type(op, rd, immediate)]

    if op in SEC_INFO:
            if op == "auth":
                # auth rs1: a single register holding the password (0xDEADBEEF)
                expect_args(op, args, 1)
                rs1 = parse_register(args[0])
                return [encode_sec_type(op, 0, rs1, 0)]

            if op == "ldk":
                # ldk rs1, rs2: store rs1 into key vault at index rs2[3:0]
                expect_args(op, args, 2)
                rs1 = parse_register(args[0])
                rs2 = parse_register(args[1])
                return [encode_sec_type(op, 0, rs1, rs2)]

            # addk, xork, tea: rd = f(rs1, vault[rs2[3:0]])
            expect_args(op, args, 3)
            rd = parse_register(args[0])
            rs1 = parse_register(args[1])
            rs2 = parse_register(args[2])
            return [encode_sec_type(op, rd, rs1, rs2)]

    raise ValueError(f"Unsupported instruction: {op}")


def assemble(source):
    labels, instructions = build_labels(source)
    machine_code = []

    for line_number, line, pc in instructions:
        try:
            encoded_list = encode_line(line, pc, labels)

            for encoded in encoded_list:
                machine_code.append(f"{encoded & 0xFFFFFFFF:08x}")

        except Exception as error:
            raise ValueError(f"Error on line {line_number}: {line}\n{error}")

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
        "ASM file was not found. Tried paths:\n"
        + "\n".join(str(candidate) for candidate in candidates)
    )


def main():
    program_name = sys.argv[1] if len(sys.argv) >= 2 else None
    filename = resolve_asm_file(program_name)

    with open(filename, "r", encoding="utf-8") as file:
        source = file.read()

    machine_code = assemble(source)

    for code in machine_code:
        print(code)


if __name__ == "__main__":
    main()