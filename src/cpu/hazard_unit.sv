module hazard_unit (
    // Inputs from Fetch and Decode stages
    input  logic [4:0] if_id_rs1,
    input  logic [4:0] if_id_rs2,
    
    // Inputs from Execute stage (Current instruction in flight)
    input  logic [4:0] id_ex_rd,
    input  logic       id_ex_mem_read, // High if the EX instruction is a LOAD
    
    // Input for control flow
    input  logic       branch_taken,

    // Outputs to control pipeline progress
    output logic       pc_write,     // 0 to stall PC
    output logic       if_id_write,  // 0 to stall IF/ID register
    output logic       id_ex_flush   // 1 to clear control signals in EX (NOP)
);

    always_comb begin
        // Default values: Pipeline flows normally
        pc_write    = 1'b1;
        if_id_write = 1'b1;
        id_ex_flush = 1'b0;

        // Load-use hazard detection
        // If the instruction in EX is a Load and its destination is used by the next instruction
        if (id_ex_mem_read && ((id_ex_rd == if_id_rs1) || (id_ex_rd == if_id_rs2))) begin
            pc_write    = 1'b0;
            if_id_write = 1'b0;
            id_ex_flush = 1'b1; // Insert a bubble (NOP)
        end

        // Control hazard: Branch taken
        // If we jump, we must discard the instruction currently being decoded
        if (branch_taken) begin
            if_id_write = 1'b1; // Allow the new branch target to enter
            id_ex_flush = 1'b1; // Flush the instruction that was wrongly fetched
        end
    end

endmodule