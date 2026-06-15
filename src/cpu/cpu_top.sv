import isa_defs::*;

module cpu_top #(
    parameter int XLEN        = 32,
    parameter int IMEM_DEPTH  = 65536,
    parameter int DMEM_DEPTH  = 65536,
    parameter int CACHE_ENABLE = 1,
    parameter int MEM_CLK_DIV  = 4,
    parameter [1023:0] PROGRAM_FILE = "programs/hex/program.hex",
    parameter [1023:0] INITIAL_MEM  = ""
)(
    input  logic clk,
    input  logic rst
);

    // Password checked against rs1 to grant key-vault access
    localparam logic [31:0] AUTH_MAGIC_WORD = 32'hDEAD_BEEF;

    if_id_t  if_id_reg;
    id_ex_t  id_ex_reg;
    ex_mem_t ex_mem_reg;
    mem_wb_t mem_wb_reg;

    logic [2:0] id_ex_funct3;

    logic       pc_write;
    logic       if_id_write;
    logic       if_id_flush;
    logic       id_ex_flush;

    logic       id_jump_taken;
    logic       if_id_uses_rs1;
    logic       if_id_uses_rs2;

    logic [1:0] forward_a;
    logic [1:0] forward_b;

    logic [XLEN-1:0] pc_next_stall;

    logic [XLEN-1:0] if_pc_cur;
    logic [XLEN-1:0] if_pc_next;
    logic [XLEN-1:0] if_pc_plus4;
    logic [31:0]     if_instr;

    logic [XLEN-1:0] id_rs1_data;
    logic [XLEN-1:0] id_rs2_data;
    logic [XLEN-1:0] id_k_out;
    logic [XLEN-1:0] id_imm_ext;

    logic [4:0] id_rs1_addr;
    logic [4:0] id_rs2_addr;
    logic [4:0] id_rd_addr;
    logic [4:0] final_rs1_addr;
    logic [4:0] id_dest_addr;

    pc_src_t id_pc_src;
    wb_src_t id_wb_src;
    alu_op_t id_alu_op;
    sec_op_t id_sec_op;

    logic id_reg_write;
    logic id_mem_write;
    logic id_alu_src;
    logic id_branch;
    logic id_jal;
    logic id_vault_we;
    logic id_u_load;

    logic auth_bit;
    logic [3:0] kv_addr;

    logic [6:0] id_funct7;
    funct3_t    id_funct3;
    opcode_t    id_opcode;

    logic [XLEN-1:0] ex_alu_result;
    logic [XLEN-1:0] ex_sec_result;
    logic [XLEN-1:0] ex_forwarded_rs1;
    logic [XLEN-1:0] ex_forwarded_rs2;
    logic [XLEN-1:0] ex_pc_imm;
    logic            ex_branch_taken;
    logic            sec_exception;

    logic [XLEN-1:0] mem_rdata;
    logic [XLEN-1:0] wb_data;

    logic [XLEN-1:0] forward_ex_mem_val;
    logic [XLEN-1:0] ex_alu_b;

    logic ex_Z;
    logic ex_N;
    logic ex_C;
    logic ex_V;

    logic cache_stall;
    logic wb_empty;
    logic ch_mem_read;
    assign ch_mem_read = (ex_mem_reg.wb_src == WB_MEM);

    // ── Performance counters ─────────────────────────────────────────────
    // Cache-hierarchy counters (wired from u_cache outputs)
    logic [31:0] perf_l1_accesses;
    logic [31:0] perf_l1_hits;
    logic [31:0] perf_l1_misses;
    logic [31:0] perf_l2_hits;
    logic [31:0] perf_l2_misses;
    logic [31:0] perf_mm_accesses;
    logic [31:0] perf_cache_stall_cycles;

    // Pipeline-level counters (computed here)
    logic [31:0] perf_instr_retired;    // instructions that passed IF→ID without flush
    logic [31:0] perf_ctrl_stall_cycles; // wasted slots due to branches/jumps

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            if_id_reg    <= '0;
            id_ex_reg    <= '0;
            ex_mem_reg   <= '0;
            mem_wb_reg   <= '0;
            id_ex_funct3 <= '0;

        end else if (cache_stall) begin
            mem_wb_reg <= '0;

        end else begin

            if (if_id_write) begin
                if (if_id_flush) begin
                    if_id_reg <= '0;
                end else begin
                    if_id_reg.pc       <= if_pc_cur;
                    if_id_reg.instr    <= if_instr;
                    if_id_reg.pc_plus4 <= if_pc_plus4;
                end
            end

            if (id_ex_flush) begin
                id_ex_reg    <= '0;
                id_ex_funct3 <= '0;
            end else begin
                id_ex_funct3 <= id_funct3;

                id_ex_reg.pc       <= if_id_reg.pc;
                id_ex_reg.pc_plus4 <= if_id_reg.pc_plus4;

                id_ex_reg.rs1_data <= id_rs1_data;
                id_ex_reg.rs2_data <= id_rs2_data;
                id_ex_reg.k_out    <= id_k_out;
                id_ex_reg.imm_ext  <= id_imm_ext;

                id_ex_reg.rs1_addr <= final_rs1_addr;
                id_ex_reg.rs2_addr <= id_rs2_addr;
                id_ex_reg.rd_addr  <= id_dest_addr;

                id_ex_reg.pc_src    <= id_pc_src;
                id_ex_reg.wb_src    <= id_wb_src;
                id_ex_reg.alu_op    <= id_alu_op;
                id_ex_reg.sec_op    <= id_sec_op;

                id_ex_reg.reg_write <= id_reg_write;
                id_ex_reg.mem_write <= id_mem_write;
                id_ex_reg.alu_src   <= id_alu_src;
                id_ex_reg.branch    <= id_branch;
                id_ex_reg.jal       <= id_jal;
                id_ex_reg.vault_we  <= id_vault_we;
            end

            ex_mem_reg.alu_result   <= ex_alu_result;
            ex_mem_reg.sec_result   <= ex_sec_result;
            ex_mem_reg.rs2_data     <= ex_forwarded_rs2;
            ex_mem_reg.pc_plus4     <= id_ex_reg.pc_plus4;
            ex_mem_reg.pc_imm       <= ex_pc_imm;
            ex_mem_reg.rd_addr      <= id_ex_reg.rd_addr;

            ex_mem_reg.wb_src       <= id_ex_reg.wb_src;
            ex_mem_reg.reg_write    <= id_ex_reg.reg_write;
            ex_mem_reg.mem_write    <= id_ex_reg.mem_write;
            ex_mem_reg.vault_we     <= id_ex_reg.vault_we;
            ex_mem_reg.branch_taken <= ex_branch_taken;

            mem_wb_reg.alu_result <= ex_mem_reg.alu_result;
            mem_wb_reg.sec_result <= ex_mem_reg.sec_result;
            mem_wb_reg.mem_rdata  <= mem_rdata;
            mem_wb_reg.pc_plus4   <= ex_mem_reg.pc_plus4;
            mem_wb_reg.rd_addr    <= ex_mem_reg.rd_addr;

            mem_wb_reg.wb_src     <= ex_mem_reg.wb_src;
            mem_wb_reg.reg_write  <= ex_mem_reg.reg_write;
        end
    end

    assign pc_next_stall = pc_write ? if_pc_next : if_pc_cur;

    decoder #(
        .XLEN(XLEN)
    ) u_decoder (
        .instr(if_id_reg.instr),
        .opcode(id_opcode),
        .funct3(id_funct3),
        .funct7(id_funct7),
        .rs1(id_rs1_addr),
        .rs2(id_rs2_addr),
        .rd(id_rd_addr),
        .imm(id_imm_ext)
    );

    control_unit u_cu (
        .opcode(id_opcode),
        .funct3(id_funct3),
        .funct7(id_funct7),
        .pc_src(id_pc_src),
        .reg_write(id_reg_write),
        .mem_write(id_mem_write),
        .alu_src(id_alu_src),
        .jal(id_jal),
        .u_load(id_u_load),
        .branch(id_branch),
        .wb_src(id_wb_src),
        .alu_op(id_alu_op),
        .sec_op(id_sec_op)
    );

    assign final_rs1_addr = id_u_load ? id_rd_addr : id_rs1_addr;

    assign id_dest_addr =
        ((id_opcode == OP_JUMP) && (id_funct3 == F3_JAL))
        ? id_rs2_addr
        : id_rd_addr;

    assign id_jump_taken = (id_opcode == OP_JUMP) && (id_pc_src != PC_PLUS4);

    always @(*) begin
        if_id_uses_rs1 = 1'b0;
        if_id_uses_rs2 = 1'b0;

        case (id_opcode)
            OP_ALU: begin
                if_id_uses_rs1 = 1'b1;
                if_id_uses_rs2 = 1'b1;
            end

            OP_ALUI,
            OP_LOAD: begin
                if_id_uses_rs1 = 1'b1;
            end

            OP_STORE,
            OP_BRANCH: begin
                if_id_uses_rs1 = 1'b1;
                if_id_uses_rs2 = 1'b1;
            end

            OP_JUMP: begin
                if (id_funct3 == F3_JR) begin
                    if_id_uses_rs1 = 1'b1;
                end
            end

            OP_U: begin
                if_id_uses_rs1 = 1'b1;
            end

            OP_SEC: begin
                if_id_uses_rs1 = 1'b1;
                if_id_uses_rs2 = 1'b1;
            end

            default: begin
                if_id_uses_rs1 = 1'b0;
                if_id_uses_rs2 = 1'b0;
            end
        endcase
    end

    hazard_unit u_hazard (
        .if_id_rs1(final_rs1_addr),
        .if_id_rs2(id_rs2_addr),

        .if_id_uses_rs1(if_id_uses_rs1),
        .if_id_uses_rs2(if_id_uses_rs2),

        .id_ex_rd(id_ex_reg.rd_addr),
        .id_ex_reg_write(id_ex_reg.reg_write),

        .ex_mem_rd(ex_mem_reg.rd_addr),
        .ex_mem_reg_write(ex_mem_reg.reg_write),

        .branch_taken(ex_branch_taken),
        .jump_taken(id_jump_taken),
        .cache_stall(cache_stall),

        .pc_write(pc_write),
        .if_id_write(if_id_write),
        .if_id_flush(if_id_flush),
        .id_ex_flush(id_ex_flush)
    );

    forwarding_unit u_forwarding (
        .id_ex_rs1(id_ex_reg.rs1_addr),
        .id_ex_rs2(id_ex_reg.rs2_addr),

        .ex_mem_rd(ex_mem_reg.rd_addr),
        .ex_mem_reg_write(ex_mem_reg.reg_write),

        .mem_wb_rd(mem_wb_reg.rd_addr),
        .mem_wb_reg_write(mem_wb_reg.reg_write),

        .forward_a(forward_a),
        .forward_b(forward_b)
    );

    always @(*) begin
        if (ex_branch_taken) begin
            if_pc_next = ex_pc_imm;
        end else if (id_pc_src == PC_IMM) begin
            if_pc_next = if_id_reg.pc + id_imm_ext;
        end else if (id_pc_src == PC_JR) begin
            if_pc_next = id_rs1_data;
        end else begin
            if_pc_next = if_pc_plus4;
        end
    end

    pc #(
        .XLEN(XLEN)
    ) u_pc (
        .clk(clk),
        .rst(rst),
        .next_pc(pc_next_stall),
        .pc(if_pc_cur)
    );

    pc_adder #(
        .XLEN(XLEN)
    ) u_pc_adder (
        .pc(if_pc_cur),
        .imm(32'd0),
        .next_pc(if_pc_plus4),
        .pc_imm()
    );

    instr_mem #(
        .XLEN(XLEN),
        .DEPTH(IMEM_DEPTH),
        .PROGRAM_FILE(PROGRAM_FILE)
    ) u_imem (
        .pc(if_pc_cur),
        .instruction(if_instr)
    );

    register_file #(
        .XLEN(XLEN)
    ) u_rf (
        .clk(clk),

        .rs1(final_rs1_addr),
        .rs2(id_rs2_addr),
        .rs3(mem_wb_reg.rd_addr),

        .wd3(wb_data),
        .we3(mem_wb_reg.reg_write),

        .rd1(id_rs1_data),
        .rd2(id_rs2_data)
    );

    assign id_vault_we = (id_sec_op == SEC_LDK);

    // SEC_TEA always reads from key slot 0; LDK pipelines the address; otherwise use rs2
    assign kv_addr = id_ex_reg.vault_we ? id_ex_reg.rs2_data[3:0] :
                     (id_sec_op == SEC_TEA) ? 4'd0 : id_rs2_data[3:0];

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            auth_bit <= 1'b0;
        end else if (id_sec_op == SEC_AUTH) begin
            if (id_rs1_data == AUTH_MAGIC_WORD) begin
                auth_bit <= 1'b1;
            end else begin
                auth_bit <= 1'b0;
            end
        end
    end

    key_vault #(
        .XLEN(XLEN),
        .KEYS(4),
        .WORDS_PER_KEY(4)
    ) u_key_vault (
        .clk(clk),
        .vault_we(id_ex_reg.vault_we),
        .auth_en(auth_bit),
        .addr(kv_addr),
        .wdata(id_ex_reg.rs1_data),
        .k_out(id_k_out)
    );

    always @(*) begin
        case (ex_mem_reg.wb_src)
            WB_ALU:  forward_ex_mem_val = ex_mem_reg.alu_result;
            WB_MEM:  forward_ex_mem_val = mem_rdata;
            WB_PC4:  forward_ex_mem_val = ex_mem_reg.pc_plus4;
            WB_SEC:  forward_ex_mem_val = ex_mem_reg.sec_result;
            default: forward_ex_mem_val = ex_mem_reg.alu_result;
        endcase
    end

    always @(*) begin
        case (forward_a)
            2'b10:   ex_forwarded_rs1 = forward_ex_mem_val;
            2'b01:   ex_forwarded_rs1 = wb_data;
            default: ex_forwarded_rs1 = id_ex_reg.rs1_data;
        endcase
    end

    always @(*) begin
        case (forward_b)
            2'b10:   ex_forwarded_rs2 = forward_ex_mem_val;
            2'b01:   ex_forwarded_rs2 = wb_data;
            default: ex_forwarded_rs2 = id_ex_reg.rs2_data;
        endcase
    end

    assign ex_alu_b  = id_ex_reg.alu_src ? id_ex_reg.imm_ext : ex_forwarded_rs2;
    assign ex_pc_imm = id_ex_reg.pc + id_ex_reg.imm_ext;

    alu #(
        .XLEN(XLEN)
    ) u_alu (
        .a(ex_forwarded_rs1),
        .b(ex_alu_b),
        .alu_op(id_ex_reg.alu_op),
        .result(ex_alu_result),
        .zero_fl(ex_Z),
        .negative_fl(ex_N),
        .carry_fl(ex_C),
        .overflow_fl(ex_V)
    );

    sec_alu #(
        .XLEN(XLEN)
    ) u_sec_alu (
        .a(ex_forwarded_rs1),
        .b(ex_forwarded_rs2),
        .key(id_ex_reg.k_out),
        .sec_op(id_ex_reg.sec_op),
        .auth_en(auth_bit),
        .result(ex_sec_result),
        .exception(sec_exception)
    );

    always_ff @(posedge clk) begin
        if (sec_exception) begin
            $display("SECURITY ERROR: Unauthorized operation or zero-attack detected.");
            $fatal(1);
        end
    end

    always @(*) begin
        ex_branch_taken = 1'b0;

        if (id_ex_reg.branch) begin
            case (id_ex_funct3)
                F3_BEQ: ex_branch_taken = ex_Z;
                F3_BNE: ex_branch_taken = !ex_Z;
                F3_BLT: ex_branch_taken = (ex_N != ex_V);
                F3_BGT: ex_branch_taken = (!ex_Z && (ex_N == ex_V));
                F3_BGE: ex_branch_taken = (ex_N == ex_V);
                F3_BLE: ex_branch_taken = (ex_Z || (ex_N != ex_V));
                default: ex_branch_taken = 1'b0;
            endcase
        end
    end

    cache_hierarchy #(
        .XLEN           (XLEN),
        .MEM_DEPTH      (DMEM_DEPTH),
        .MEM_CLK_DIV    (MEM_CLK_DIV),
        .MEM_INIT_FILE  (INITIAL_MEM)
    ) u_cache (
        .clk(clk),
        .rst(rst),
        .cache_enable(CACHE_ENABLE != 0),
        .mem_read    (ch_mem_read),
        .mem_write   (ex_mem_reg.mem_write),
        .addr        (ex_mem_reg.alu_result),
        .write_data  (ex_mem_reg.rs2_data),
        .read_data         (mem_rdata),
        .cache_stall       (cache_stall),
        .perf_l1_accesses  (perf_l1_accesses),
        .perf_l1_hits      (perf_l1_hits),
        .perf_l1_misses    (perf_l1_misses),
        .perf_l2_hits      (perf_l2_hits),
        .perf_l2_misses    (perf_l2_misses),
        .perf_mm_accesses  (perf_mm_accesses),
        .perf_stall_cycles (perf_cache_stall_cycles),
        .wb_empty          (wb_empty)
    );

    always @(*) begin
        case (mem_wb_reg.wb_src)
            WB_ALU:  wb_data = mem_wb_reg.alu_result;
            WB_MEM:  wb_data = mem_wb_reg.mem_rdata;
            WB_PC4:  wb_data = mem_wb_reg.pc_plus4;
            WB_SEC:  wb_data = mem_wb_reg.sec_result;
            default: wb_data = '0;
        endcase
    end

    // ── Pipeline performance counters ────────────────────────────────────
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            perf_instr_retired    <= '0;
            perf_ctrl_stall_cycles <= '0;
        end else begin
            // Instruction retired: every cycle a real instruction advances IF→ID
            // (not frozen by cache_stall, not squashed by a flush)
            if (if_id_write && !if_id_flush && !cache_stall)
                perf_instr_retired <= perf_instr_retired + 1;

            // Control hazard wasted slots:
            //   taken branch flushes 2 stages (IF/ID + ID/EX)
            //   taken jump   flushes 1 stage  (IF/ID only)
            if (ex_branch_taken && !cache_stall)
                perf_ctrl_stall_cycles <= perf_ctrl_stall_cycles + 2;
            else if (id_jump_taken && !cache_stall)
                perf_ctrl_stall_cycles <= perf_ctrl_stall_cycles + 1;
        end
    end

endmodule