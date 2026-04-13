module register_file (
    input  logic        clk,

    // Read
    input  logic [3:0]  registerAddress1,
    input  logic [3:0]  registerAddress2,
    output logic [31:0] registerData1,
    output logic [31:0] registerData2,

    // Write
    input  logic [3:0]  registerAddress3,
    input  logic [31:0] registerWriteData,
    input  logic        registerWriteEnable
);

    // Registers
    logic [31:0] registers [15:0];

    // Reading
    assign registerData1 = (registerAddress1 == 4'd0) ? 32'd0 : registers[registerAddress1];
    assign registerData2 = (registerAddress2 == 4'd0) ? 32'd0 : registers[registerAddress2];

    // Writting
    always @(negedge clk) begin
        if (regWriteEnable && registerAddress3 != 3'd0) begin
            registers[registerAddress3] <= regWriteData;
        end
    end

endmodule