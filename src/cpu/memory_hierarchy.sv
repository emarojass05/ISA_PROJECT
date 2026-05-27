module memory_hierarchy #(
    parameter int XLEN = 32,
    parameter int DEPTH = 65536,
    parameter INITIAL_MEM = "",

    parameter int LINE_WORDS = 8,
    parameter int L1_WORDS = 1024,
    parameter int L1_WAYS = 2,
    parameter int L2_WORDS = 4096,
    parameter int L2_WAYS = 4,

    parameter int L2_HIT_CYCLES = 8,
    parameter int MAIN_MEM_LATENCY = 25
)(
    input  logic              clk,
    input  logic              rst,

    input  logic              mem_read_enable,
    input  logic              mem_write_enable,
    input  logic [XLEN-1:0]   mem_write_data,
    input  logic [XLEN-1:0]   memory_address,

    output logic [XLEN-1:0]   mem_read_data,
    output logic              cache_stall,

    output logic [63:0]       l1_read_accesses,
    output logic [63:0]       l1_write_accesses,
    output logic [63:0]       l1_read_hits,
    output logic [63:0]       l1_read_misses,
    output logic [63:0]       l1_write_hits,
    output logic [63:0]       l1_write_misses,

    output logic [63:0]       l2_read_accesses,
    output logic [63:0]       l2_write_accesses,
    output logic [63:0]       l2_read_hits,
    output logic [63:0]       l2_read_misses,
    output logic [63:0]       l2_write_hits,
    output logic [63:0]       l2_write_misses,

    output logic [63:0]       main_mem_accesses,
    output logic [63:0]       main_mem_cycles,
    output logic [63:0]       cache_stall_cycles
);

    localparam int WORD_OFFSET_BITS = $clog2(LINE_WORDS);
    localparam int L1_LINES = L1_WORDS / LINE_WORDS;
    localparam int L1_SETS = L1_LINES / L1_WAYS;
    localparam int L1_SET_BITS = $clog2(L1_SETS);

    localparam int L2_LINES = L2_WORDS / LINE_WORDS;
    localparam int L2_SETS = L2_LINES / L2_WAYS;
    localparam int L2_SET_BITS = $clog2(L2_SETS);

    localparam int MEM_ADDR_BITS = $clog2(DEPTH);
    localparam int MISS_MEM_CYCLES = L2_HIT_CYCLES + MAIN_MEM_LATENCY + LINE_WORDS;

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_WAIT_L2,
        ST_WAIT_MEM,
        ST_RESPONSE
    } state_t;

    state_t state;

    logic [XLEN-1:0] memory [0:DEPTH-1];
    logic [XLEN-1:0] main_memory [0:DEPTH-1];

    logic [XLEN-1:0] l1_data [0:L1_SETS-1][0:L1_WAYS-1][0:LINE_WORDS-1];
    logic [31:0]     l1_tags [0:L1_SETS-1][0:L1_WAYS-1];
    logic            l1_valid [0:L1_SETS-1][0:L1_WAYS-1];
    logic            l1_lru [0:L1_SETS-1];

    logic [XLEN-1:0] l2_data [0:L2_SETS-1][0:L2_WAYS-1][0:LINE_WORDS-1];
    logic [31:0]     l2_tags [0:L2_SETS-1][0:L2_WAYS-1];
    logic            l2_valid [0:L2_SETS-1][0:L2_WAYS-1];
    logic            l2_dirty [0:L2_SETS-1][0:L2_WAYS-1];
    logic [$clog2(L2_WAYS)-1:0] l2_rr_ptr [0:L2_SETS-1];

    logic request_valid;
    logic current_read;
    logic current_write;

    logic [31:0] req_word_addr;
    logic [WORD_OFFSET_BITS-1:0] req_word_offset;
    logic [L1_SET_BITS-1:0] req_l1_set;
    logic [L2_SET_BITS-1:0] req_l2_set;
    logic [31:0] req_l1_tag;
    logic [31:0] req_l2_tag;

    logic l1_hit;
    logic l2_hit;
    logic [$clog2(L1_WAYS)-1:0] l1_hit_way;
    logic [$clog2(L2_WAYS)-1:0] l2_hit_way;
    logic [$clog2(L1_WAYS)-1:0] l1_victim_way;
    logic [$clog2(L2_WAYS)-1:0] l2_victim_way;

    logic [XLEN-1:0] pending_addr;
    logic [XLEN-1:0] pending_wdata;
    logic            pending_read;
    logic            pending_write;
    logic            pending_l1_hit;
    logic            pending_l2_hit;
    logic [$clog2(L1_WAYS)-1:0] pending_l1_way;
    logic [$clog2(L2_WAYS)-1:0] pending_l2_way;
    logic [$clog2(L1_WAYS)-1:0] pending_l1_victim;
    logic [$clog2(L2_WAYS)-1:0] pending_l2_victim;
    logic [31:0] pending_word_addr;
    logic [WORD_OFFSET_BITS-1:0] pending_word_offset;
    logic [L1_SET_BITS-1:0] pending_l1_set;
    logic [L2_SET_BITS-1:0] pending_l2_set;
    logic [31:0] pending_l1_tag;
    logic [31:0] pending_l2_tag;

    logic [15:0] wait_counter;
    logic [XLEN-1:0] response_data;

    integer i;
    integer j;
    integer k;

    assign request_valid = mem_read_enable || mem_write_enable;
    assign current_read  = mem_read_enable && !mem_write_enable;
    assign current_write = mem_write_enable;

    assign req_word_addr   = memory_address[31:2];
    assign req_word_offset = req_word_addr[WORD_OFFSET_BITS-1:0];
    assign req_l1_set      = req_word_addr[WORD_OFFSET_BITS +: L1_SET_BITS];
    assign req_l2_set      = req_word_addr[WORD_OFFSET_BITS +: L2_SET_BITS];
    assign req_l1_tag      = req_word_addr >> (WORD_OFFSET_BITS + L1_SET_BITS);
    assign req_l2_tag      = req_word_addr >> (WORD_OFFSET_BITS + L2_SET_BITS);

    always_comb begin
        l1_hit = 1'b0;
        l1_hit_way = '0;

        for (int way = 0; way < L1_WAYS; way++) begin
            if (l1_valid[req_l1_set][way] && (l1_tags[req_l1_set][way] == req_l1_tag)) begin
                l1_hit = 1'b1;
                l1_hit_way = way;
            end
        end
    end

    always_comb begin
        l2_hit = 1'b0;
        l2_hit_way = '0;

        for (int way = 0; way < L2_WAYS; way++) begin
            if (l2_valid[req_l2_set][way] && (l2_tags[req_l2_set][way] == req_l2_tag)) begin
                l2_hit = 1'b1;
                l2_hit_way = way;
            end
        end
    end

    always_comb begin
        l1_victim_way = l1_lru[req_l1_set];

        for (int way = 0; way < L1_WAYS; way++) begin
            if (!l1_valid[req_l1_set][way]) begin
                l1_victim_way = way;
            end
        end
    end

    always_comb begin
        l2_victim_way = l2_rr_ptr[req_l2_set];

        for (int way = 0; way < L2_WAYS; way++) begin
            if (!l2_valid[req_l2_set][way]) begin
                l2_victim_way = way;
            end
        end
    end

    always_comb begin
        mem_read_data = '0;

        if ((state == ST_IDLE) && current_read && l1_hit) begin
            mem_read_data = l1_data[req_l1_set][l1_hit_way][req_word_offset];
        end else if (state == ST_RESPONSE) begin
            mem_read_data = response_data;
        end
    end

    always_comb begin
        cache_stall = 1'b0;

        case (state)
            ST_IDLE: begin
                if (request_valid) begin
                    if (current_write) begin
                        cache_stall = 1'b1;
                    end else if (current_read && !l1_hit) begin
                        cache_stall = 1'b1;
                    end
                end
            end

            ST_WAIT_L2,
            ST_WAIT_MEM: begin
                cache_stall = 1'b1;
            end

            ST_RESPONSE: begin
                cache_stall = 1'b0;
            end

            default: begin
                cache_stall = 1'b0;
            end
        endcase
    end

    task automatic writeback_l2_victim;
        input int set_idx;
        input int way_idx;
        logic [31:0] old_base_word;
        logic [31:0] mem_word_index;
        begin
            if (l2_valid[set_idx][way_idx] && l2_dirty[set_idx][way_idx]) begin
                old_base_word = (((l2_tags[set_idx][way_idx] << L2_SET_BITS) | set_idx) << WORD_OFFSET_BITS);

                for (int word = 0; word < LINE_WORDS; word++) begin
                    mem_word_index = old_base_word + word;
                    main_memory[mem_word_index[MEM_ADDR_BITS-1:0]] = l2_data[set_idx][way_idx][word];
                    memory[mem_word_index[MEM_ADDR_BITS-1:0]] = l2_data[set_idx][way_idx][word];
                end

                main_mem_accesses <= main_mem_accesses + 64'd1;
                main_mem_cycles   <= main_mem_cycles + (MAIN_MEM_LATENCY + LINE_WORDS);
            end
        end
    endtask

    task automatic fill_l2_line_from_memory;
        input int set_idx;
        input int way_idx;
        input logic [31:0] tag_value;
        input logic [31:0] base_word;
        logic [31:0] mem_word_index;
        begin
            for (int word = 0; word < LINE_WORDS; word++) begin
                mem_word_index = base_word + word;
                l2_data[set_idx][way_idx][word] <= main_memory[mem_word_index[MEM_ADDR_BITS-1:0]];
            end

            l2_tags[set_idx][way_idx]  <= tag_value;
            l2_valid[set_idx][way_idx] <= 1'b1;
            l2_dirty[set_idx][way_idx] <= 1'b0;
            l2_rr_ptr[set_idx] <= l2_rr_ptr[set_idx] + 1'b1;
        end
    endtask

    task automatic fill_l1_line_from_l2;
        input int l1_set_idx;
        input int l1_way_idx;
        input logic [31:0] l1_tag_value;
        input int l2_set_idx;
        input int l2_way_idx;
        begin
            for (int word = 0; word < LINE_WORDS; word++) begin
                l1_data[l1_set_idx][l1_way_idx][word] <= l2_data[l2_set_idx][l2_way_idx][word];
            end

            l1_tags[l1_set_idx][l1_way_idx]  <= l1_tag_value;
            l1_valid[l1_set_idx][l1_way_idx] <= 1'b1;
            l1_lru[l1_set_idx] <= ~l1_way_idx[0];
        end
    endtask

    task automatic fill_l1_line_from_memory;
        input int l1_set_idx;
        input int l1_way_idx;
        input logic [31:0] l1_tag_value;
        input logic [31:0] base_word;
        logic [31:0] mem_word_index;
        begin
            for (int word = 0; word < LINE_WORDS; word++) begin
                mem_word_index = base_word + word;
                l1_data[l1_set_idx][l1_way_idx][word] <= main_memory[mem_word_index[MEM_ADDR_BITS-1:0]];
            end

            l1_tags[l1_set_idx][l1_way_idx]  <= l1_tag_value;
            l1_valid[l1_set_idx][l1_way_idx] <= 1'b1;
            l1_lru[l1_set_idx] <= ~l1_way_idx[0];
        end
    endtask

    task automatic complete_pending_l2_hit;
        begin
            if (pending_read) begin
                fill_l1_line_from_l2(
                    pending_l1_set,
                    pending_l1_victim,
                    pending_l1_tag,
                    pending_l2_set,
                    pending_l2_way
                );

                response_data <= l2_data[pending_l2_set][pending_l2_way][pending_word_offset];
                l2_dirty[pending_l2_set][pending_l2_way] <= l2_dirty[pending_l2_set][pending_l2_way];
            end else begin
                l2_data[pending_l2_set][pending_l2_way][pending_word_offset] <= pending_wdata;
                l2_dirty[pending_l2_set][pending_l2_way] <= 1'b1;
                memory[pending_word_addr[MEM_ADDR_BITS-1:0]] <= pending_wdata;
                response_data <= '0;
            end
        end
    endtask

    task automatic complete_pending_l2_miss;
        logic [31:0] line_base_word;
        logic [31:0] mem_word_index;
        begin
            line_base_word = (pending_word_addr >> WORD_OFFSET_BITS) << WORD_OFFSET_BITS;

            writeback_l2_victim(pending_l2_set, pending_l2_victim);
            fill_l2_line_from_memory(pending_l2_set, pending_l2_victim, pending_l2_tag, line_base_word);

            if (pending_read) begin
                fill_l1_line_from_memory(pending_l1_set, pending_l1_victim, pending_l1_tag, line_base_word);
                mem_word_index = pending_word_addr;
                response_data <= main_memory[mem_word_index[MEM_ADDR_BITS-1:0]];
            end else begin
                l2_data[pending_l2_set][pending_l2_victim][pending_word_offset] <= pending_wdata;
                l2_dirty[pending_l2_set][pending_l2_victim] <= 1'b1;
                memory[pending_word_addr[MEM_ADDR_BITS-1:0]] <= pending_wdata;
                response_data <= '0;
            end
        end
    endtask

    initial begin
        for (i = 0; i < DEPTH; i = i + 1) begin
            memory[i] = '0;
            main_memory[i] = '0;
        end

        if (INITIAL_MEM != "") begin
            $display("Loading backing memory from: %s", INITIAL_MEM);
            $readmemh(INITIAL_MEM, memory);
            $readmemh(INITIAL_MEM, main_memory);
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_IDLE;
            wait_counter <= '0;
            response_data <= '0;

            pending_addr <= '0;
            pending_wdata <= '0;
            pending_read <= 1'b0;
            pending_write <= 1'b0;
            pending_l1_hit <= 1'b0;
            pending_l2_hit <= 1'b0;
            pending_l1_way <= '0;
            pending_l2_way <= '0;
            pending_l1_victim <= '0;
            pending_l2_victim <= '0;
            pending_word_addr <= '0;
            pending_word_offset <= '0;
            pending_l1_set <= '0;
            pending_l2_set <= '0;
            pending_l1_tag <= '0;
            pending_l2_tag <= '0;

            l1_read_accesses <= 64'd0;
            l1_write_accesses <= 64'd0;
            l1_read_hits <= 64'd0;
            l1_read_misses <= 64'd0;
            l1_write_hits <= 64'd0;
            l1_write_misses <= 64'd0;

            l2_read_accesses <= 64'd0;
            l2_write_accesses <= 64'd0;
            l2_read_hits <= 64'd0;
            l2_read_misses <= 64'd0;
            l2_write_hits <= 64'd0;
            l2_write_misses <= 64'd0;

            main_mem_accesses <= 64'd0;
            main_mem_cycles <= 64'd0;
            cache_stall_cycles <= 64'd0;

            for (i = 0; i < L1_SETS; i = i + 1) begin
                l1_lru[i] <= 1'b0;
                for (j = 0; j < L1_WAYS; j = j + 1) begin
                    l1_valid[i][j] <= 1'b0;
                    l1_tags[i][j] <= '0;
                    for (k = 0; k < LINE_WORDS; k = k + 1) begin
                        l1_data[i][j][k] <= '0;
                    end
                end
            end

            for (i = 0; i < L2_SETS; i = i + 1) begin
                l2_rr_ptr[i] <= '0;
                for (j = 0; j < L2_WAYS; j = j + 1) begin
                    l2_valid[i][j] <= 1'b0;
                    l2_dirty[i][j] <= 1'b0;
                    l2_tags[i][j] <= '0;
                    for (k = 0; k < LINE_WORDS; k = k + 1) begin
                        l2_data[i][j][k] <= '0;
                    end
                end
            end
        end else begin
            if (cache_stall) begin
                cache_stall_cycles <= cache_stall_cycles + 64'd1;
            end

            case (state)
                ST_IDLE: begin
                    if (request_valid) begin
                        pending_addr <= memory_address;
                        pending_wdata <= mem_write_data;
                        pending_read <= current_read;
                        pending_write <= current_write;
                        pending_l1_hit <= l1_hit;
                        pending_l2_hit <= l2_hit;
                        pending_l1_way <= l1_hit_way;
                        pending_l2_way <= l2_hit_way;
                        pending_l1_victim <= l1_victim_way;
                        pending_l2_victim <= l2_victim_way;
                        pending_word_addr <= req_word_addr;
                        pending_word_offset <= req_word_offset;
                        pending_l1_set <= req_l1_set;
                        pending_l2_set <= req_l2_set;
                        pending_l1_tag <= req_l1_tag;
                        pending_l2_tag <= req_l2_tag;

                        if (current_read) begin
                            l1_read_accesses <= l1_read_accesses + 64'd1;

                            if (l1_hit) begin
                                l1_read_hits <= l1_read_hits + 64'd1;
                                l1_lru[req_l1_set] <= ~l1_hit_way[0];
                                response_data <= l1_data[req_l1_set][l1_hit_way][req_word_offset];
                            end else begin
                                l1_read_misses <= l1_read_misses + 64'd1;
                                l2_read_accesses <= l2_read_accesses + 64'd1;

                                if (l2_hit) begin
                                    l2_read_hits <= l2_read_hits + 64'd1;
                                    wait_counter <= L2_HIT_CYCLES;
                                    state <= ST_WAIT_L2;
                                end else begin
                                    l2_read_misses <= l2_read_misses + 64'd1;
                                    main_mem_accesses <= main_mem_accesses + 64'd1;
                                    main_mem_cycles <= main_mem_cycles + (MAIN_MEM_LATENCY + LINE_WORDS);
                                    wait_counter <= MISS_MEM_CYCLES;
                                    state <= ST_WAIT_MEM;
                                end
                            end
                        end else if (current_write) begin
                            l1_write_accesses <= l1_write_accesses + 64'd1;
                            l2_write_accesses <= l2_write_accesses + 64'd1;

                            if (l1_hit) begin
                                l1_write_hits <= l1_write_hits + 64'd1;
                                l1_data[req_l1_set][l1_hit_way][req_word_offset] <= mem_write_data;
                                l1_lru[req_l1_set] <= ~l1_hit_way[0];
                            end else begin
                                l1_write_misses <= l1_write_misses + 64'd1;
                            end

                            if (l2_hit) begin
                                l2_write_hits <= l2_write_hits + 64'd1;
                                wait_counter <= L2_HIT_CYCLES;
                                state <= ST_WAIT_L2;
                            end else begin
                                l2_write_misses <= l2_write_misses + 64'd1;
                                main_mem_accesses <= main_mem_accesses + 64'd1;
                                main_mem_cycles <= main_mem_cycles + (MAIN_MEM_LATENCY + LINE_WORDS);
                                wait_counter <= MISS_MEM_CYCLES;
                                state <= ST_WAIT_MEM;
                            end
                        end
                    end
                end

                ST_WAIT_L2: begin
                    if (wait_counter > 16'd1) begin
                        wait_counter <= wait_counter - 16'd1;
                    end else begin
                        complete_pending_l2_hit();
                        wait_counter <= '0;
                        state <= ST_RESPONSE;
                    end
                end

                ST_WAIT_MEM: begin
                    if (wait_counter > 16'd1) begin
                        wait_counter <= wait_counter - 16'd1;
                    end else begin
                        complete_pending_l2_miss();
                        wait_counter <= '0;
                        state <= ST_RESPONSE;
                    end
                end

                ST_RESPONSE: begin
                    state <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule