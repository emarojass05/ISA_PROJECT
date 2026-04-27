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
    logic branch;
    logic branch_taken;

    // Register file
    logic [4:0]      rs1_addr;
    logic [4:0]      rd_addr;
    logic [XLEN-1:0] rs1_data;
    logic [XLEN-1:0] rs2_data;
    logic [XLEN-1:0] wb_data;
    logic            we3;

    // Main ALU signals
    logic [XLEN-1:0] alu_b;
    logic [XLEN-1:0] alu_result;
    logic            Z;
    logic            N;
    logic            C;
    logic            V;

    // Secure coprocessor signals
    sec_op_t         sec_op;
    logic            auth_bit;
    logic [XLEN-1:0] k_out_wire;
    logic [XLEN-1:0] sec_result_wire;
    logic            sec_exception;
    logic            vault_we;

    assign vault_we = (sec_op == SEC_LDK);

    // Data memory
    logic [XLEN-1:0] mem_rdata;

    // U-type
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

    // Control unit
    control_unit u_cu (
        .opcode(opcode),
        .funct3(funct3),
        .funct7(funct7),
        .pc_src(pc_src),
        .reg_write(reg_write),
        .mem_write(mem_write),
        .alu_src(alu_src),
        .jal(jal),
        .u_load(u_load),
        .branch(branch),
        .wb_src(wb_src),
        .alu_op(alu_op),
        .sec_op(sec_op)
    );

    // Security state register (Guardian)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            auth_bit <= 1'b0;
        end else if (sec_op == SEC_AUTH) begin
            if (rs1_data == 32'hDEADBEEF)
                auth_bit <= 1'b1;
            else
                auth_bit <= 1'b0;
        end
    end

    // Key vault module
    key_vault #(
        .XLEN(XLEN),
        .KEYS(4),
        .WORDS_PER_KEY(4)
    ) u_key_vault (
        .clk(clk),
        .vault_we(vault_we),
        .auth_en(auth_bit),
        .addr(rs2_data[3:0]),
        .wdata(rs1_data),
        .k_out(k_out_wire)
    );

    // Secure ALU module
    sec_alu #(
        .XLEN(XLEN)
    ) u_sec_alu (
        .a(rs1_data),
        .b(rs2_data),
        .key(k_out_wire),
        .sec_op(sec_op),
        .auth_en(auth_bit),
        .result(sec_result_wire),
        .exception(sec_exception)
    );

    // Security exception handling
    always_ff @(posedge clk) begin
        if (sec_exception) begin
            $display("SECURITY ERROR: Unauthorized operation or zero-attack detected.");
            $fatal(1);
        end
    end

    // Main ALU
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

    // Branching logic
    always @(*) begin
        branch_taken = 1'b0;

        if (branch) begin
            case (funct3)
                F3_BEQ: branch_taken = Z;
                F3_BNE: branch_taken = !Z;
                F3_BLT: branch_taken = (N != V);
                F3_BGT: branch_taken = (!Z && (N == V));
                F3_BGE: branch_taken = (N == V);
                F3_BLE: branch_taken = (Z || (N != V));
                default: branch_taken = 1'b0;
            endcase
        end
    end

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
            WB_SEC:  wb_data = sec_result_wire;
            default: wb_data = '0;
        endcase
    end

    // PC select mux
    always @* begin
        if (branch_taken) begin
                pc_next = pc_imm;
        end else begin
            case (pc_src)
                PC_PLUS4: pc_next = pc_plus4;
                PC_IMM:   pc_next = pc_imm;
                PC_JR:    pc_next = rs1_data;
                default:  pc_next = pc_plus4;
            endcase
        end
    end

endmodule