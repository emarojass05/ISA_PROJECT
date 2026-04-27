import isa_defs::*;

module sec_alu #(
    parameter int XLEN = 32
)(
    // Input signals
    input  logic [XLEN-1:0] a,
    input  logic [XLEN-1:0] b,
    input  logic [XLEN-1:0] key,
    
    input  sec_op_t         sec_op,
    input  logic            auth_en,
    
    // Output signals
    output logic [XLEN-1:0] result,
    output logic            exception
);

    logic zero_attack_detected;

    // Hardware defense: Zero-attack detection
    // Prevents extracting the raw key through identity operations
    assign zero_attack_detected = (a == '0) && (sec_op == SEC_ADDK || sec_op == SEC_XORK);

    always_comb begin
        result    = '0;
        exception = 1'b0;

        // Logical security barrier
        if (sec_op != SEC_NONE && sec_op != SEC_AUTH) begin
            if (!auth_en || zero_attack_detected) begin
                exception = 1'b1;
                result    = '0;
            end else begin
                
                // Secure mathematical engine
                case (sec_op)
                    
                    SEC_ADDK: begin
                        result = a + key;
                    end
                    
                    SEC_XORK: begin
                        result = a ^ key;
                    end
                    
                    SEC_TEA: begin
                        // TEA core formula: ((v1<<4) + k0) ^ (v1 + sum) ^ ((v1>>5) + k1)
                        result = ((a << 4) + key) ^ b ^ ((a >> 5) + key);
                    end

                    default: begin
                        result = '0;
                    end
                endcase
            end
        end
    end

endmodule