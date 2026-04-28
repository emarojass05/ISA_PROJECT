module forwarding_unit (
    // Inputs from ID/EX stage (Current instruction in Execute)
    input  logic [4:0] id_ex_rs1,
    input  logic [4:0] id_ex_rs2,

    // Inputs from EX/MEM stage (Previous instruction)
    input  logic [4:0] ex_mem_rd,
    input  logic       ex_mem_reg_write,

    // Inputs from MEM/WB stage (Instruction before previous)
    input  logic [4:0] mem_wb_rd,
    input  logic       mem_wb_reg_write,

    // Outputs to ALU multiplexers in EX stage
    output logic [1:0] forward_a,
    output logic [1:0] forward_b
);

    // Forwarding logic for ALU input A (rs1)
    always_comb begin
        if (ex_mem_reg_write && (ex_mem_rd != 5'b0) && (ex_mem_rd == id_ex_rs1)) begin
            forward_a = 2'b10;
        end else if (mem_wb_reg_write && (mem_wb_rd != 5'b0) && (mem_wb_rd == id_ex_rs1)) begin
            forward_a = 2'b01;
        end else begin
            forward_a = 2'b00;
        end
    end

    // Forwarding logic for ALU input B (rs2)
    always_comb begin
        if (ex_mem_reg_write && (ex_mem_rd != 5'b0) && (ex_mem_rd == id_ex_rs2)) begin
            forward_b = 2'b10;
        end else if (mem_wb_reg_write && (mem_wb_rd != 5'b0) && (mem_wb_rd == id_ex_rs2)) begin
            forward_b = 2'b01;
        end else begin
            forward_b = 2'b00;
        end
    end

endmodule