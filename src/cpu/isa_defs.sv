package isa_defs;
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
        ALU_LUHW,
        ALU_LLHW,
        ALU_NONE
    } alu_op_t;

    // Security coprocessor operations
    typedef enum logic [2:0] {
        SEC_NONE,
        SEC_AUTH,
        SEC_LDK,
        SEC_ADDK,
        SEC_XORK,
        SEC_TEA
    } sec_op_t;

    typedef enum logic [1:0] {
        WB_ALU = 2'b00,
        WB_MEM = 2'b01,
        WB_PC4 = 2'b10,
        WB_SEC = 2'b11
    } wb_src_t;

    typedef logic [2:0] funct3_t;

    // R-type
    localparam funct3_t F3_ADD  = 3'b000;
    localparam funct3_t F3_SUB  = 3'b001;
    localparam funct3_t F3_MUL  = 3'b000;
    localparam funct3_t F3_DIV  = 3'b001;
    localparam funct3_t F3_REM  = 3'b010;
    localparam funct3_t F3_AND  = 3'b010;
    localparam funct3_t F3_OR   = 3'b011;
    localparam funct3_t F3_XOR  = 3'b100;
    localparam funct3_t F3_SLL  = 3'b101;
    localparam funct3_t F3_SRL  = 3'b110;

    // I-type
    localparam funct3_t F3_ADDI = 3'b000;
    localparam funct3_t F3_XORI = 3'b001;
    localparam funct3_t F3_SLLI = 3'b010;
    localparam funct3_t F3_SRLI = 3'b011;
    localparam funct3_t F3_LW   = 3'b100;

    // S-type
    localparam funct3_t F3_SW   = 3'b000;

    // B-type
    localparam funct3_t F3_BEQ  = 3'b000;
    localparam funct3_t F3_BNE  = 3'b001;
    localparam funct3_t F3_BGT  = 3'b010;
    localparam funct3_t F3_BLT  = 3'b011;
    localparam funct3_t F3_BGE  = 3'b100;
    localparam funct3_t F3_BLE  = 3'b101;

    // J-type
    localparam funct3_t F3_J    = 3'b000;
    localparam funct3_t F3_JAL  = 3'b001;
    localparam funct3_t F3_JR   = 3'b010;

    // U-type
    localparam funct3_t F3_LUHW = 3'b000;
    localparam funct3_t F3_LLHW = 3'b001;

    typedef enum logic [1:0] {
        PC_PLUS4 = 2'b00,
        PC_IMM   = 2'b10,
        PC_JR    = 2'b01
    } pc_src_t;

    // Register aliases
    localparam logic [4:0] R_ZERO  = 5'd0;
    localparam logic [4:0] R_RA    = 5'd1;
    localparam logic [4:0] R_SP    = 5'd2;
    localparam logic [4:0] R_SR    = 5'd20;
    localparam logic [4:0] R_DELTA = 5'd30;
    localparam logic [4:0] R_VP    = 5'd31;

    // --- Pipeline Stage Registers (Structs) ---

    // IF/ID Pipeline Register
    typedef struct packed {
        logic [31:0] pc;
        logic [31:0] instr;
        logic [31:0] pc_plus4;
    } if_id_t;

    // ID/EX Pipeline Register
    typedef struct packed {
        logic [31:0] pc;
        logic [31:0] pc_plus4;
        logic [31:0] rs1_data;
        logic [31:0] rs2_data;
        logic [31:0] k_out;       // Security key read from vault
        logic [31:0] imm_ext;
        logic [4:0]  rs1_addr;
        logic [4:0]  rs2_addr;
        logic [4:0]  rd_addr;
        
        // Control signals
        pc_src_t     pc_src;
        wb_src_t     wb_src;
        alu_op_t     alu_op;
        sec_op_t     sec_op;
        logic        reg_write;
        logic        mem_write;
        logic        alu_src;
        logic        branch;
        logic        jal;
        logic        vault_we;
    } id_ex_t;

    // EX/MEM Pipeline Register
    typedef struct packed {
        logic [31:0] alu_result;
        logic [31:0] sec_result;  // Output from Secure ALU
        logic [31:0] rs2_data;    // Data for Memory Store
        logic [31:0] pc_plus4;
        logic [31:0] pc_imm;      // Calculated branch target
        logic [4:0]  rd_addr;
        
        // Control signals
        wb_src_t     wb_src;
        logic        reg_write;
        logic        mem_write;
        logic        vault_we;
        logic        branch_taken;
    } ex_mem_t;

    // MEM/WB Pipeline Register
    typedef struct packed {
        logic [31:0] alu_result;
        logic [31:0] sec_result;
        logic [31:0] mem_rdata;
        logic [31:0] pc_plus4;
        logic [4:0]  rd_addr;
        
        // Control signals
        wb_src_t     wb_src;
        logic        reg_write;
    } mem_wb_t;
endpackage