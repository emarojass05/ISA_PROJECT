// =============================================================================
// mem_write_buffer.sv - Write Buffer: L2 cache -> Main Memory
// =============================================================================
// Sits between cache_ctrl and main_mem_model. cache_ctrl enqueues dirty L2
// evictions here instead of stalling for the write to complete. The buffer
// drains writes to main memory opportunistically in the background.
//
// Coherence policy: drain-on-conflict. Before serving a read, if any buffered
// entry's line address matches rd_addr, those entries are drained first. No
// forwarding; correctness relies on the drain completing before the read issues.
//
// Protocol toward main_mem_model: identical to cache_ctrl usage - single-cycle
// req pulse, then wait for ready (~25 cycles later, one cycle wide).
// =============================================================================

module mem_write_buffer #(
    parameter int XLEN      = 32,
    parameter int LINE_BITS = 256,
    parameter int DEPTH     = 4
)(
    input  logic clk,
    input  logic rst,

    // -- Upstream enqueue (from cache_ctrl) -----------------------------------
    input  logic                 enq,
    input  logic [XLEN-1:0]      enq_addr,
    input  logic [LINE_BITS-1:0] enq_data,
    output logic                 full,

    // -- Upstream read request (from cache_ctrl) ------------------------------
    input  logic                 rd_req,
    input  logic [XLEN-1:0]      rd_addr,
    output logic                 rd_ready,
    output logic [LINE_BITS-1:0] rd_data,

    // -- Observability --------------------------------------------------------
    output logic                 empty,

    // -- Downstream (to main_mem_model) ---------------------------------------
    output logic                 mm_req,
    output logic                 mm_we,
    output logic [XLEN-1:0]      mm_addr,
    output logic [LINE_BITS-1:0] mm_wdata,
    input  logic                 mm_ready,
    input  logic [LINE_BITS-1:0] mm_rdata,

    // -- Optional performance counters ----------------------------------------
    output logic [31:0]          perf_wb_drains,
    output logic [31:0]          perf_wb_conflict_drains,
    output logic [31:0]          perf_wb_full_stalls
);

    localparam int OFFSET_BITS = 5;  // 256-bit line -> 32 bytes -> 5 offset bits

    // -- FIFO storage ---------------------------------------------------------
    logic [XLEN-1:0]       buf_addr  [0:DEPTH-1];
    logic [LINE_BITS-1:0]  buf_data  [0:DEPTH-1];
    logic                  buf_valid [0:DEPTH-1];

    logic [$clog2(DEPTH)-1:0]   head;
    logic [$clog2(DEPTH)-1:0]   tail;
    logic [$clog2(DEPTH+1)-1:0] count;

    assign full  = (count == DEPTH[$clog2(DEPTH+1)-1:0]);
    assign empty = (count == '0);

    // -- Conflict detection ----------------------------------------------------
    // Detect if any valid buffer entry conflicts with the pending read address.
    // Icarus Verilog: no dynamic-index continuous assigns on unpacked arrays;
    // use explicit per-slot comparisons instead.
    logic [XLEN-1:0] rd_line_addr;
    assign rd_line_addr = {rd_addr[XLEN-1:OFFSET_BITS], {OFFSET_BITS{1'b0}}};

    logic conflict0, conflict1, conflict2, conflict3;
    assign conflict0 = buf_valid[0] &&
        ({buf_addr[0][XLEN-1:OFFSET_BITS], {OFFSET_BITS{1'b0}}} == rd_line_addr);
    assign conflict1 = buf_valid[1] &&
        ({buf_addr[1][XLEN-1:OFFSET_BITS], {OFFSET_BITS{1'b0}}} == rd_line_addr);
    assign conflict2 = buf_valid[2] &&
        ({buf_addr[2][XLEN-1:OFFSET_BITS], {OFFSET_BITS{1'b0}}} == rd_line_addr);
    assign conflict3 = buf_valid[3] &&
        ({buf_addr[3][XLEN-1:OFFSET_BITS], {OFFSET_BITS{1'b0}}} == rd_line_addr);

    // rd_conflict is combinational on rd_addr (which is latched to rd_addr_lat).
    // After rd_req latches rd_addr_lat, the conflict check below in FSM uses
    // rd_line_addr which is wired to the INPUT rd_addr port. We need it based
    // on the latched version. Use a separate latched-conflict signal.
    logic rd_conflict;  // conflict against live rd_addr (used in WB_IDLE on rd_req)
    generate
        if (DEPTH >= 4)
            assign rd_conflict = conflict0 | conflict1 | conflict2 | conflict3;
        else if (DEPTH == 3)
            assign rd_conflict = conflict0 | conflict1 | conflict2;
        else if (DEPTH == 2)
            assign rd_conflict = conflict0 | conflict1;
        else
            assign rd_conflict = conflict0;
    endgenerate

    // -- Latched-address conflict -----------------------------------------------
    // Once rd_req is latched, rd_addr_lat holds the target and rd_line_addr
    // follows it (rd_addr is kept stable by cache_ctrl while rd_pending is high).
    // So rd_conflict above remains valid throughout the drain sequence.

    // -- FSM ------------------------------------------------------------------
    typedef enum logic [1:0] {
        WB_IDLE,
        WB_DRAIN,
        WB_READ
    } wb_state_t;

    wb_state_t state;

    logic                 rd_pending;
    logic [XLEN-1:0]      rd_addr_lat;

    // Single-pulse guard: once mm_req fires, do not re-assert until mm_ready.
    logic mm_req_sent;

    // -- Combinational head address/data ---------------------------------------
    // Icarus limitation: cannot use a logic signal as an unpacked-array index in
    // a continuous assign.  Use explicit ternary muxes.
    logic [XLEN-1:0]      head_addr;
    logic [LINE_BITS-1:0] head_data;

    assign head_addr = (head == 2'd0) ? buf_addr[0] :
                       (head == 2'd1) ? buf_addr[1] :
                       (head == 2'd2) ? buf_addr[2] : buf_addr[3];

    assign head_data = (head == 2'd0) ? buf_data[0] :
                       (head == 2'd1) ? buf_data[1] :
                       (head == 2'd2) ? buf_data[2] : buf_data[3];

    // -- mm interface drives ---------------------------------------------------
    assign mm_req   = ((state == WB_DRAIN) || (state == WB_READ)) && !mm_req_sent;
    assign mm_we    = (state == WB_DRAIN);
    assign mm_addr  = (state == WB_DRAIN) ? head_addr : rd_addr_lat;
    assign mm_wdata = head_data;

    // -- Performance counter registers ----------------------------------------
    logic [31:0] perf_drains_r;
    logic [31:0] perf_conflict_drains_r;
    logic [31:0] perf_full_stalls_r;

    assign perf_wb_drains          = perf_drains_r;
    assign perf_wb_conflict_drains = perf_conflict_drains_r;
    assign perf_wb_full_stalls     = perf_full_stalls_r;

    // -- Sequential logic -----------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        integer i;
        if (rst) begin
            state                  <= WB_IDLE;
            head                   <= '0;
            tail                   <= '0;
            count                  <= '0;
            rd_pending             <= 1'b0;
            rd_addr_lat            <= '0;
            rd_ready               <= 1'b0;
            rd_data                <= '0;
            mm_req_sent            <= 1'b0;
            perf_drains_r          <= '0;
            perf_conflict_drains_r <= '0;
            perf_full_stalls_r     <= '0;
            for (i = 0; i < DEPTH; i = i + 1) begin
                buf_valid[i] <= 1'b0;
                buf_addr[i]  <= '0;
                buf_data[i]  <= '0;
            end
        end else begin
            rd_ready <= 1'b0;  // default: one-cycle pulse only

            // -- Latch incoming rd_req ----------------------------------------
            // cache_ctrl issues rd_req for exactly one cycle.
            if (rd_req) begin
                rd_pending  <= 1'b1;
                rd_addr_lat <= rd_addr;
            end

            // -- Track full-stall events ---------------------------------------
            if (enq && full)
                perf_full_stalls_r <= perf_full_stalls_r + 1;

            // -- FSM ----------------------------------------------------------
            case (state)

                // -- WB_IDLE --------------------------------------------------
                WB_IDLE: begin
                    mm_req_sent <= 1'b0;

                    // Enqueue arriving this cycle into FIFO
                    if (enq && !full) begin
                        buf_addr[tail]  <= enq_addr;
                        buf_data[tail]  <= enq_data;
                        buf_valid[tail] <= 1'b1;
                        tail            <= tail + 1'b1;
                        count           <= count + 1'b1;
                    end

                    // State transition: evaluate after potential enqueue.
                    // rd_req arriving this cycle -> rd_pending will be set by the
                    // latch above; conflict check uses rd_addr (live combinational).
                    // rd_pending already true -> conflict check uses rd_addr_lat
                    // which is stable and equal to rd_addr (ctrl keeps it stable).
                    if (rd_req || rd_pending) begin
                        if (rd_conflict)
                            state <= WB_DRAIN;
                        else
                            state <= WB_READ;
                    end else if (!empty && !enq) begin
                        // Background drain: only start if no enq arrived this cycle.
                        // Waiting one cycle after a new enq lets the wb_rd_req that
                        // cache_ctrl issues the very next cycle arrive in WB_IDLE so
                        // the conflict check runs against the now-registered entry.
                        state <= WB_DRAIN;
                    end
                    // enq && !rd_req && !rd_pending: stay idle one more cycle.
                end

                // -- WB_DRAIN -------------------------------------------------
                // Write head entry to main memory.  Return to WB_IDLE on mm_ready.
                // No-preemption: once mm_req is issued, we stay here until ready.
                WB_DRAIN: begin
                    if (!mm_req_sent)
                        mm_req_sent <= 1'b1;

                    // Accept new enqueues while waiting for mm_ready
                    if (enq && !full) begin
                        buf_addr[tail]  <= enq_addr;
                        buf_data[tail]  <= enq_data;
                        buf_valid[tail] <= 1'b1;
                        tail            <= tail + 1'b1;
                        count           <= count + 1'b1;
                    end

                    if (mm_ready) begin
                        buf_valid[head] <= 1'b0;
                        head            <= head + 1'b1;

                        // count bookkeeping: drain removes 1.
                        // If enq also fired this cycle, it already added 1 in the
                        // block above (count <= count+1). We need to subtract 1 for
                        // the drain. Since non-blocking assignments take the last
                        // write, we must compute the combined result explicitly.
                        if (enq && !full)
                            count <= count;         // +1 enq, -1 drain -> net 0
                        else
                            count <= count - 1'b1;

                        mm_req_sent        <= 1'b0;
                        state              <= WB_IDLE;
                        perf_drains_r      <= perf_drains_r + 1;
                        if (rd_pending && rd_conflict)
                            perf_conflict_drains_r <= perf_conflict_drains_r + 1;
                    end
                end

                // -- WB_READ --------------------------------------------------
                // Issue a read to main memory and return data to cache_ctrl.
                WB_READ: begin
                    if (!mm_req_sent)
                        mm_req_sent <= 1'b1;

                    // Accept enqueues while waiting
                    if (enq && !full) begin
                        buf_addr[tail]  <= enq_addr;
                        buf_data[tail]  <= enq_data;
                        buf_valid[tail] <= 1'b1;
                        tail            <= tail + 1'b1;
                        count           <= count + 1'b1;
                    end

                    if (mm_ready) begin
                        rd_data     <= mm_rdata;
                        rd_ready    <= 1'b1;
                        rd_pending  <= 1'b0;
                        mm_req_sent <= 1'b0;
                        state       <= WB_IDLE;
                    end
                end

                default: state <= WB_IDLE;
            endcase
        end
    end

endmodule
