import isa_defs::*;

module cpu_top #(
    parameter int XLEN        = 32,
    parameter int IMEM_DEPTH  = 65536,
    parameter int DMEM_DEPTH  = 65536,
    parameter PROGRAM_FILE = "programs/program.hex"
)(
    input  logic clk,
    input  logic rst
);

    // PC / fetch
    logic [XLEN-1:0] pc_cur;
    logic [XLEN-1:0] pc_plus4;
    logic [XLEN-1:0] pc_imm;
    logic [XLEN-1:0] pc_next;
    logic [31:0]     instr;

    // Decode
    opcode_t         opcode;
    funct3_t         funct3;
    logic [6:0]      funct7;
    logic [4:0]      rs1;
    logic [4:0]      rs2;
    logic [4:0]      rd;
    logic [XLEN-1:0] imm_ext;

    // Control
    pc_src_t pc_src;
    wb_src_t wb_src;
    alu_op_t alu_op;

    logic reg_write;
    logic mem_write;
    logic alu_src;
    logic jal;

    // Register file
    logic [4:0]      rs1_addr;
    logic [4:0]      rd_addr;
    logic [XLEN-1:0] rs1_data;
    logic [XLEN-1:0] rs2_data;
    logic [XLEN-1:0] wb_data;
    logic            we3;

    // ALU
    logic [XLEN-1:0] alu_b;
    logic [XLEN-1:0] alu_result;
    logic            Z;
    logic            N;
    logic            C;
    logic            V;

    // Data memory
    logic [XLEN-1:0] mem_rdata;

    // U-type
    logic u_load;

    assign rs1_addr = u_load ? rd : rs1;

    // jal
    assign rd_addr = jal ? rs2 : rd;

    assign we3 = reg_write;

    // PC / fetch
    pc #(.XLEN(XLEN)) u_pc (
        .clk(clk),
        .rst(rst),
        .next_pc(pc_next),
        .pc(pc_cur)
    );

    pc_adder #(.XLEN(XLEN)) u_pc_adder (
        .pc(pc_cur),
        .imm(imm_ext),
        .next_pc(pc_plus4),
        .pc_imm(pc_imm)
    );

    instr_mem #(
        .XLEN(XLEN),
        .DEPTH(IMEM_DEPTH),
        .PROGRAM_FILE("programs/program.hex")
//        .PROGRAM_FILE(PROGRAM_FILE)
    ) u_imem (
        .pc(pc_cur),
        .instruction(instr)
    );

    // Decode
    decoder #(.XLEN(XLEN)) u_decoder (
        .instr(instr),
        .opcode(opcode),
        .funct3(funct3),
        .funct7(funct7),
        .rs1(rs1),
        .rs2(rs2),
        .rd(rd),
        .imm(imm_ext)
    );

    // Register file
    register_file #(.XLEN(XLEN)) u_rf (
        .clk(clk),
        .rs1(rs1_addr),
        .rs2(rs2),
        .rd1(rs1_data),
        .rd2(rs2_data),
        .rs3(rd_addr),
        .wd3(wb_data),
        .we3(we3)
    );

    // Control
    control_unit u_cu (
        .opcode(opcode),
        .funct3(funct3),
        .funct7(funct7),
        .zero_fl(Z),
        .negative_fl(N),
        .carry_fl(C),
        .overflow_fl(V),
        .pc_src(pc_src),
        .reg_write(reg_write),
        .mem_write(mem_write),
        .alu_src(alu_src),
        .jal(jal),
        .u_load(u_load),
        .wb_src(wb_src),
        .alu_op(alu_op)
    );

    // ALU
    assign alu_b = alu_src ? imm_ext : rs2_data;

    alu #(.XLEN(XLEN)) u_alu (
        .a(rs1_data),
        .b(alu_b),
        .alu_op(alu_op),
        .result(alu_result),
        .zero_fl(Z),
        .negative_fl(N),
        .carry_fl(C),
        .overflow_fl(V)
    );

    // Data memory
    data_mem #(
        .XLEN(XLEN),
        .DEPTH(DMEM_DEPTH)
    ) u_dmem (
        .clk(clk),
        .mem_write_enable(mem_write),
        .mem_write_data(rs2_data),
        .memory_address(alu_result),
        .mem_read_data(mem_rdata)
    );

    // Write-back mux
    always @(*) begin
        case (wb_src)
            WB_ALU:  wb_data = alu_result;
            WB_MEM:  wb_data = mem_rdata;
            WB_PC4:  wb_data = pc_plus4;
            default: wb_data = '0;
        endcase
    end

    // PC select mux
    always @(*) begin
        case (pc_src)
            PC_PLUS4: pc_next = pc_plus4;
            PC_IMM:   pc_next = pc_imm;
            PC_JR:    pc_next = rs1_data;
            default:  pc_next = pc_plus4;
        endcase
    end

endmodule