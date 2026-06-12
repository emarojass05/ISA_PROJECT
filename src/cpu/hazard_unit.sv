module hazard_unit (
    input  logic [4:0] if_id_rs1,
    input  logic [4:0] if_id_rs2,

    input  logic       if_id_uses_rs1,
    input  logic       if_id_uses_rs2,

    input  logic [4:0] id_ex_rd,
    input  logic       id_ex_reg_write,

    input  logic [4:0] ex_mem_rd,
    input  logic       ex_mem_reg_write,

    input  logic       branch_taken,
    input  logic       jump_taken,
    input  logic       cache_stall,

    output logic       pc_write,
    output logic       if_id_write,
    output logic       if_id_flush,
    output logic       id_ex_flush
);

    logic id_ex_raw_hazard;
    logic ex_mem_raw_hazard;
    logic raw_hazard;

    always_comb begin
        id_ex_raw_hazard =
            id_ex_reg_write &&
            (id_ex_rd != 5'd0) &&
            (
                (if_id_uses_rs1 && (id_ex_rd == if_id_rs1)) ||
                (if_id_uses_rs2 && (id_ex_rd == if_id_rs2))
            );

        ex_mem_raw_hazard =
            ex_mem_reg_write &&
            (ex_mem_rd != 5'd0) &&
            (
                (if_id_uses_rs1 && (ex_mem_rd == if_id_rs1)) ||
                (if_id_uses_rs2 && (ex_mem_rd == if_id_rs2))
            );

        raw_hazard = id_ex_raw_hazard || ex_mem_raw_hazard;

        pc_write    = 1'b1;
        if_id_write = 1'b1;
        if_id_flush = 1'b0;
        id_ex_flush = 1'b0;

        if (cache_stall) begin
            pc_write    = 1'b0;
            if_id_write = 1'b0;
            if_id_flush = 1'b0;
            id_ex_flush = 1'b0;
        end else if (raw_hazard) begin
            pc_write    = 1'b0;
            if_id_write = 1'b0;
            if_id_flush = 1'b0;
            id_ex_flush = 1'b1;
        end else if (branch_taken) begin
            pc_write    = 1'b1;
            if_id_write = 1'b1;
            if_id_flush = 1'b1;
            id_ex_flush = 1'b1;
        end else if (jump_taken) begin
            pc_write    = 1'b1;
            if_id_write = 1'b1;
            if_id_flush = 1'b1;
            id_ex_flush = 1'b0;
        end
    end

endmodule