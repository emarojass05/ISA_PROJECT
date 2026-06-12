module forwarding_unit (
    input  logic [4:0] id_ex_rs1,
    input  logic [4:0] id_ex_rs2,

    input  logic [4:0] ex_mem_rd,
    input  logic       ex_mem_reg_write,

    input  logic [4:0] mem_wb_rd,
    input  logic       mem_wb_reg_write,

    output logic [1:0] forward_a,
    output logic [1:0] forward_b
);

    logic ex_mem_fwds_rs1;
    logic mem_wb_fwds_rs1;
    logic ex_mem_fwds_rs2;
    logic mem_wb_fwds_rs2;

    assign ex_mem_fwds_rs1 = ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs1);
    assign mem_wb_fwds_rs1 = mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs1);
    assign ex_mem_fwds_rs2 = ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs2);
    assign mem_wb_fwds_rs2 = mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs2);

    always_comb begin
        if      (ex_mem_fwds_rs1) forward_a = 2'b10;
        else if (mem_wb_fwds_rs1) forward_a = 2'b01;
        else                      forward_a = 2'b00;
    end

    always_comb begin
        if      (ex_mem_fwds_rs2) forward_b = 2'b10;
        else if (mem_wb_fwds_rs2) forward_b = 2'b01;
        else                      forward_b = 2'b00;
    end

endmodule
