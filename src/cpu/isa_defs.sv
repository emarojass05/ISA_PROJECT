package isa_defs
    typedef enum logic [6:0] { 
    OP_ALU    = 7'b0000000,
    OP_ALUI   = 7'b0000001,
    OP_STORE  = 7'b0000010,
    OP_LOAD   = 7'b0000011,
    OP_BRANCH = 7'b0000100,
    OP_U      = 7'b0000101,
    OP_SEC    = 7'b0000110,
    OP_JUMP   = 7'b0000111
    } opcode_t;

    typedef enum logic [3:0] { 
        ALU_ADD,
        ALU_SUB,
        ALU_AND,
        ALU_OR ,
        ALU_XOR,
        ALU_SLL,
        ALU_SRL,
        ALU_MUL,
        ALU_DIV,
        ALU_REM,
        ALU_NONE
    } alu_op_t;

    typedef enum logic [1:0] {
        WB_ALU = 2'b00,
        WB_MEM = 2'b01,
        WB_PC4 = 2'b10
    } wb_src_t;

    typedef enum logic [2:0] { 
        // R
        F3_ADD = 3'b000,
        F3_SUB = 3'b001,
        F3_MUL = 3'b000,
        F3_DIV = 3'b001,
        F3_REM = 3'b010,
        F3_AND = 3'b010,
        F3_OR  = 3'b011,
        F3_XOR = 3'b100,
        F3_SLL = 3'b101,
        F3_SRL = 3'b110,
        
        // I
        F3_ADDI = 3'b000,
        F3_XORI = 3'b001,
        F3_SLLI = 3'b010,
        F3_SRLI = 3'b011,
        F3_LW   = 3'b100,

        // S
        F3_SW = 3'b000,

        // B
        F3_BEQ = 3'b000,
        F3_BNE = 3'b001,
        F3_BGT = 3'b010,
        F3_BLT = 3'b011,
        F3_BGE = 3'b100,
        F3_BLE = 3'b101,

        // J
        F3_J   = 3'b000,
        F3_JAL = 3'b001,
        F3_JR  = 3'b010,

        // U
        F3_LUHW = 3'b000,
        F3_LLHW = 3'b001
    } funct3_t;

    typedef enum logic [1:0] {
        PC_PLUS4 = 2'b00,
        PC_IMM   = 2'b10,
        PC_JR    = 2'b01
    } pc_src_t;
endpackage