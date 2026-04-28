import isa_defs::*;

module cpu_top #(
    parameter int XLEN        = 32,
    parameter int IMEM_DEPTH  = 65536,
    parameter int DMEM_DEPTH  = 65536,
    parameter PROGRAM_FILE    = "programs/hex/program.hex"
)(
    input  logic clk,
    input  logic rst
);

    // Pipeline registers
    if_id_t  if_id_reg;
    id_ex_t  id_ex_reg;
    ex_mem_t ex_mem_reg;
    mem_wb_t mem_wb_reg;

    logic [2:0] id_ex_funct3;

    // Hazard and Forwarding unit signals
    logic       pc_write;
    logic       if_id_write;
    logic       id_ex_flush;
    logic [1:0] forward_a;
    logic [1:0] forward_b;

    // Fetch stage signals
    logic [XLEN-1:0] if_pc_cur;
    logic [XLEN-1:0] if_pc_next;
    logic [XLEN-1:0] if_pc_plus4;
    logic [31:0]     if_instr;

    // Decode stage signals
    logic [XLEN-1:0] id_rs1_data;
    logic [XLEN-1:0] id_rs2_data;
    logic [XLEN-1:0] id_k_out;
    logic [XLEN-1:0] id_imm_ext;
    logic [4:0]      id_rs1_addr;
    logic [4:0]      id_rs2_addr;
    logic [4:0]      id_rd_addr;
    pc_src_t         id_pc_src;
    wb_src_t         id_wb_src;
    alu_op_t         id_alu_op;
    sec_op_t         id_sec_op;
    logic            id_reg_write;
    logic            id_mem_write;
    logic            id_alu_src;
    logic            id_branch;
    logic            id_jal;
    logic            id_vault_we;
    logic            auth_bit;

    logic [6:0] id_funct7;      
    funct3_t    id_funct3;
    opcode_t    id_opcode;
    logic       id_u_load;

    // Execute stage signals
    logic [XLEN-1:0] ex_alu_result;
    logic [XLEN-1:0] ex_sec_result;
    logic [XLEN-1:0] ex_forwarded_rs1;
    logic [XLEN-1:0] ex_forwarded_rs2;
    logic [XLEN-1:0] ex_pc_imm;
    logic            ex_branch_taken;
    logic            sec_exception;

    // Memory stage signals
    logic [XLEN-1:0] mem_rdata;

    // Write-Back stage signals
    logic [XLEN-1:0] wb_data;

    // Pipeline synchronous datapath
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            if_id_reg  <= '0;
            id_ex_reg  <= '0;
            ex_mem_reg <= '0;
            mem_wb_reg <= '0;
        end else begin
            
            // IF/ID Register update
            if (if_id_write) begin
                if_id_reg.pc       <= if_pc_cur;
                if_id_reg.instr    <= if_instr;
                if_id_reg.pc_plus4 <= if_pc_plus4;
            end

            // ID/EX Register update
            if (id_ex_flush) begin
                id_ex_reg <= '0;
                id_ex_funct3 <= '0;
            end else begin
                id_ex_funct3 <= id_funct3;
                id_ex_reg.pc       <= if_id_reg.pc;
                id_ex_reg.pc_plus4 <= if_id_reg.pc_plus4;
                id_ex_reg.rs1_data <= id_rs1_data;
                id_ex_reg.rs2_data <= id_rs2_data;
                id_ex_reg.k_out    <= id_k_out;
                id_ex_reg.imm_ext  <= id_imm_ext;
                id_ex_reg.rs1_addr <= id_rs1_addr;
                id_ex_reg.rs2_addr <= id_rs2_addr;
                id_ex_reg.rd_addr  <= id_rd_addr;

                id_ex_reg.pc_src   <= id_pc_src;
                id_ex_reg.wb_src   <= id_wb_src;
                id_ex_reg.alu_op   <= id_alu_op;
                id_ex_reg.sec_op   <= id_sec_op;
                id_ex_reg.reg_write<= id_reg_write;
                id_ex_reg.mem_write<= id_mem_write;
                id_ex_reg.alu_src  <= id_alu_src;
                id_ex_reg.branch   <= id_branch;
                id_ex_reg.jal      <= id_jal;
                id_ex_reg.vault_we <= id_vault_we;
            end

            // EX/MEM Register update
            ex_mem_reg.alu_result <= ex_alu_result;
            ex_mem_reg.sec_result <= ex_sec_result;
            ex_mem_reg.rs2_data   <= ex_forwarded_rs2;
            ex_mem_reg.pc_plus4   <= id_ex_reg.pc_plus4;
            ex_mem_reg.pc_imm     <= ex_pc_imm;
            ex_mem_reg.rd_addr    <= id_ex_reg.rd_addr;

            ex_mem_reg.wb_src     <= id_ex_reg.wb_src;
            ex_mem_reg.reg_write  <= id_ex_reg.reg_write;
            ex_mem_reg.mem_write  <= id_ex_reg.mem_write;
            ex_mem_reg.vault_we   <= id_ex_reg.vault_we;
            ex_mem_reg.branch_taken <= ex_branch_taken;

            // MEM/WB Register update
            mem_wb_reg.alu_result <= ex_mem_reg.alu_result;
            mem_wb_reg.sec_result <= ex_mem_reg.sec_result;
            mem_wb_reg.mem_rdata  <= mem_rdata;
            mem_wb_reg.pc_plus4   <= ex_mem_reg.pc_plus4;
            mem_wb_reg.rd_addr    <= ex_mem_reg.rd_addr;

            mem_wb_reg.wb_src     <= ex_mem_reg.wb_src;
            mem_wb_reg.reg_write  <= ex_mem_reg.reg_write;
        end
    end

// ========================================================================
    // PIPELINE CONTROL UNITS
    // ========================================================================

    hazard_unit u_hazard (
        .if_id_rs1(id_rs1_addr),
        .if_id_rs2(id_rs2_addr),
        .id_ex_rd(id_ex_reg.rd_addr),
        .id_ex_mem_read(id_ex_reg.wb_src == WB_MEM),
        .branch_taken(ex_branch_taken),
        .pc_write(pc_write),
        .if_id_write(if_id_write),
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

    // ========================================================================
    // STAGE 1: INSTRUCTION FETCH (IF)
    // ========================================================================

    // PC select mux (Resolves branches from EX and jumps from ID)
    always_comb begin
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

    pc #(.XLEN(XLEN)) u_pc (
        .clk(clk),
        .rst(rst || !pc_write), // Stall PC if hazard detected
        .next_pc(if_pc_next),
        .pc(if_pc_cur)
    );

    pc_adder #(.XLEN(XLEN)) u_pc_adder (
        .pc(if_pc_cur),
        .imm(32'd0),            // Not used for plus4 in this setup
        .next_pc(if_pc_plus4),
        .pc_imm()               // Calculated in EX for branches
    );

   instr_mem #(
        .XLEN(XLEN),
        .DEPTH(IMEM_DEPTH),
        .PROGRAM_FILE("programs/hex/program.hex") // <--- TU SOLUCIÓN ORIGINAL
    ) u_imem (
        .pc(if_pc_cur),
        .instruction(if_instr)
    );

    // ========================================================================
    // STAGE 2: INSTRUCTION DECODE (ID)
    // ========================================================================
    
  

    decoder #(.XLEN(XLEN)) u_decoder (
        .instr(if_id_reg.instr),
        .opcode(id_opcode),
        .funct3(id_funct3),
        .funct7(id_funct7),
        .rs1(id_rs1_addr),
        .rs2(id_rs2_addr),
        .rd(id_rd_addr),
        .imm(id_imm_ext)
    );

    // U-type handling for rs1 address
    logic [4:0] final_rs1_addr;
    assign final_rs1_addr = id_u_load ? id_rd_addr : id_rs1_addr;

    register_file #(.XLEN(XLEN)) u_rf (
        .clk(clk),
        .rs1(final_rs1_addr),
        .rs2(id_rs2_addr),
        .rd1(id_rs1_data),
        .rd2(id_rs2_data),
        .rs3(mem_wb_reg.rd_addr),   // Write-back address comes from MEM/WB
        .wd3(wb_data),              // Write-back data comes from WB mux
        .we3(mem_wb_reg.reg_write)  // Write enable comes from MEM/WB
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

    assign id_vault_we = (id_sec_op == SEC_LDK);

    // --- Security state register (Guardian) ---
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            auth_bit <= 1'b0;
        end else if (id_sec_op == SEC_AUTH) begin
            if (id_rs1_data == 32'hDEADBEEF)
                auth_bit <= 1'b1;
            else
                auth_bit <= 1'b0;
        end
    end

    // --- Key Vault Module ---
    key_vault #(
        .XLEN(XLEN),
        .KEYS(4),
        .WORDS_PER_KEY(4)
    ) u_key_vault (
        .clk(clk),
        .vault_we(id_ex_reg.vault_we),     // Write executes safely in EX stage
        .auth_en(auth_bit),
        .addr(id_ex_reg.vault_we ? id_ex_reg.rs2_data[3:0] : id_rs2_data[3:0]), // Read in ID, Write in EX
        .wdata(id_ex_reg.rs1_data),        // Data to write comes from EX stage
        .k_out(id_k_out)                   // Secret key output to ID/EX register
    );

// ========================================================================
    // STAGE 3: EXECUTE (EX)
    // ========================================================================

    logic [XLEN-1:0] forward_ex_mem_val;
    logic [XLEN-1:0] ex_alu_b;
    logic            ex_Z, ex_N, ex_C, ex_V;

    // Resolve Forwarding Data from EX/MEM stage
    always_comb begin
        case (ex_mem_reg.wb_src)
            WB_ALU:  forward_ex_mem_val = ex_mem_reg.alu_result;
            WB_SEC:  forward_ex_mem_val = ex_mem_reg.sec_result;
            WB_PC4:  forward_ex_mem_val = ex_mem_reg.pc_plus4;
            default: forward_ex_mem_val = ex_mem_reg.alu_result;
        endcase
    end

    // Forwarding MUX A (rs1)
    always_comb begin
        case (forward_a)
            2'b10:   ex_forwarded_rs1 = forward_ex_mem_val;
            2'b01:   ex_forwarded_rs1 = wb_data; // From WB stage
            default: ex_forwarded_rs1 = id_ex_reg.rs1_data;
        endcase
    end

    // Forwarding MUX B (rs2)
    always_comb begin
        case (forward_b)
            2'b10:   ex_forwarded_rs2 = forward_ex_mem_val;
            2'b01:   ex_forwarded_rs2 = wb_data; // From WB stage
            default: ex_forwarded_rs2 = id_ex_reg.rs2_data;
        endcase
    end

    // ALU B input selection (Immediate or Register)
    assign ex_alu_b = id_ex_reg.alu_src ? id_ex_reg.imm_ext : ex_forwarded_rs2;

    // Calculate Branch Target
    assign ex_pc_imm = id_ex_reg.pc + id_ex_reg.imm_ext;

    // Main ALU
    alu #(.XLEN(XLEN)) u_alu (
        .a(ex_forwarded_rs1),
        .b(ex_alu_b),
        .alu_op(id_ex_reg.alu_op),
        .result(ex_alu_result),
        .zero_fl(ex_Z),
        .negative_fl(ex_N),
        .carry_fl(ex_C),
        .overflow_fl(ex_V)
    );

    // Secure Coprocessor ALU
    sec_alu #(.XLEN(XLEN)) u_sec_alu (
        .a(ex_forwarded_rs1),
        .b(ex_forwarded_rs2),
        .key(id_ex_reg.k_out), // Key forwarded securely via struct
        .sec_op(id_ex_reg.sec_op),
        .auth_en(auth_bit),
        .result(ex_sec_result),
        .exception(sec_exception)
    );

    // Security Exception Trap
    always_ff @(posedge clk) begin
        if (sec_exception) begin
            $display("SECURITY ERROR: Unauthorized operation or zero-attack detected.");
            $fatal(1);
        end
    end

    // Branch Resolution
    always_comb begin
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

    // ========================================================================
    // STAGE 4: MEMORY (MEM)
    // ========================================================================

    data_mem #(
        .XLEN(XLEN),
        .DEPTH(DMEM_DEPTH)
    ) u_dmem (
        .clk(clk),
        .mem_write_enable(ex_mem_reg.mem_write),
        .mem_write_data(ex_mem_reg.rs2_data), // Clean forwarded rs2 data
        .memory_address(ex_mem_reg.alu_result),
        .mem_read_data(mem_rdata)
    );

    // ========================================================================
    // STAGE 5: WRITE-BACK (WB)
    // ========================================================================

    always_comb begin
        case (mem_wb_reg.wb_src)
            WB_ALU:  wb_data = mem_wb_reg.alu_result;
            WB_MEM:  wb_data = mem_wb_reg.mem_rdata;
            WB_PC4:  wb_data = mem_wb_reg.pc_plus4;
            WB_SEC:  wb_data = mem_wb_reg.sec_result;
            default: wb_data = '0;
        endcase
    end

endmodule