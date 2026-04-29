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

    // --- SEÑALES INTERMEDIAS PARA DESCOMPONER TEA ---
    logic [XLEN-1:0] tea_shift_l;
    logic [XLEN-1:0] tea_shift_r;
    logic [XLEN-1:0] tea_add_l;
    logic [XLEN-1:0] tea_add_r;

    // Hardware defense: Zero-attack detection
    // Prevents extracting the raw key through identity operations
    assign zero_attack_detected = (a == '0) && (sec_op == SEC_ADDK || sec_op == SEC_XORK);

    always_comb begin
        // Valores por defecto
        result    = '0;
        exception = 1'b0;
        tea_shift_l = '0;
        tea_shift_r = '0;
        tea_add_l   = '0;
        tea_add_r   = '0;

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
                        
                        tea_shift_l = a << 4;
                        tea_shift_r = a >> 5;

                        
                        tea_add_l = tea_shift_l + key;
                        tea_add_r = tea_shift_r + key;

                        
                        result = tea_add_l ^ b ^ tea_add_r;
                    end

                    default: begin
                        result = '0;
                    end
                endcase
            end
        end
    end

endmodule