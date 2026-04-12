module cu_alu(
    input clk,

    input [2:0] Op,
    input [1:0] funct2,
    input [3:0] funct4,

    input [2:0] rs1,
    input [2:0] rs2,
    input [2:0] rd,

    input [31:0] write_data_ext, // para inicializar registros
    input write_enable_ext,

    output [31:0] alu_result
);

    wire [31:0] read_data1, read_data2;
    wire [2:0] ALUOp;
    wire RegWrite, MemWrite, ResultSrc, Branch;

    // -------------------------
    // Control Unit
    // -------------------------
    control_unit cu(
        .Op(Op),
        .funct2(funct2),
        .funct4(funct4),
        .RegWrite(RegWrite),
        .MemWrite(MemWrite),
        .ResultSrc(ResultSrc),
        .Branch(Branch),
        .ALUOp(ALUOp)
    );

    // -------------------------
    // Register File
    // -------------------------
    register_file rf(
        .clk(clk),
        .rs1(rs1),
        .rs2(rs2),
        .read_data1(read_data1),
        .read_data2(read_data2),
        .rd(rd),
        .write_data(write_data_ext),
        .reg_write(write_enable_ext)
    );

    // -------------------------
    // ALU
    // -------------------------
    alu alu_inst(
        .A(read_data1),
        .B(read_data2),
        .alu_op(ALUOp),
        .result(alu_result)
    );

endmodule