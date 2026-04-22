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

endpackage


