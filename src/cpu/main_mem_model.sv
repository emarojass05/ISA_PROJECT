// =============================================================================
// main_mem_model.sv — Main Memory Model
// =============================================================================
// Capacity   : 64 KB (16 384 x 32-bit words)
// Latency    : LATENCY CPU clock cycles per transaction
// Burst size : 256 bits (one full cache line = 8 x 32-bit words)
// Init file  : optional hex file loaded via $readmemh (INIT_FILE parameter)
//
// MEM_CLK_DIV: clock-enable divisor that models a slower memory clock without
// introducing a second physical clock domain. The latency FSM advances only
// when an internal tick fires (every MEM_CLK_DIV CPU cycles). Effective
// latency = LATENCY * MEM_CLK_DIV CPU cycles. With MEM_CLK_DIV=1 (default),
// tick is always 1 and behavior is identical to the pre-divisor implementation.
//
// Protocol (used by cache_ctrl):
//
//   Read request:
//     1. cache_ctrl asserts req=1, we=0, addr=line base address (one cycle)
//     2. This module counts LATENCY ticks
//     3. On tick LATENCY: ready=1 for exactly one CPU cycle, rdata holds the line
//
//   Write request (write-back of a dirty cache line):
//     1. cache_ctrl asserts req=1, we=1, addr=line base, wdata=256-bit line
//     2. This module counts LATENCY ticks
//     3. On tick LATENCY: ready=1 for exactly one CPU cycle (write confirmation)
//
// Important: cache_ctrl must not issue a new request until ready arrives.
//            ready is guaranteed to be high for exactly one CPU cycle.
// =============================================================================

module main_mem_model #(
    parameter int    XLEN        = 32,
    parameter int    DEPTH       = 16384,            // 64 KB / 4 bytes per word
    parameter int    LINE_WORDS  = 8,
    parameter int    LINE_BITS   = LINE_WORDS * 32,  // 256 bits per cache line
    parameter int    LATENCY     = 25,
    parameter int    MEM_CLK_DIV = 1,
    parameter [1023:0] INIT_FILE = ""
)(
    input  logic                  clk,
    input  logic                  rst,

    // -- Interface with cache_ctrl ----------------------------------------
    input  logic                  req,    // single-cycle pulse: start a new transaction
    input  logic                  we,     // 1 = write, 0 = read
    input  logic [XLEN-1:0]       addr,   // byte address of the cache line base
    input  logic [LINE_BITS-1:0]  wdata,  // data to write (only used when we=1)

    output logic                  ready,  // single-cycle pulse: transaction done
    output logic [LINE_BITS-1:0]  rdata   // line returned on a read (valid when ready=1 and we=0)
);

    // -- Memory array -----------------------------------------------------
    logic [31:0] memory [0:DEPTH-1];

    initial begin
        integer i;
        string plus_init_file;
        for (i = 0; i < DEPTH; i++)
            memory[i] = 32'h0;
        if ($value$plusargs("INITIAL_MEM=%s", plus_init_file) && plus_init_file != "") begin
            $readmemh(plus_init_file, memory);
        end else if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, memory);
        end
    end

    // -- Clock-enable divisor ---------------------------------------------
    // Width guard: $clog2(1)=0, which would create a zero-width signal.
    // Use at least 1 bit so synthesis/simulation are always valid.
    localparam int DIV_W = (MEM_CLK_DIV > 1) ? $clog2(MEM_CLK_DIV) : 1;
    logic [DIV_W-1:0] div_cnt;
    logic             tick;

    generate
        if (MEM_CLK_DIV <= 1) begin : gen_tick_always
            assign tick = 1'b1;
        end else begin : gen_tick_div
            assign tick = (div_cnt == DIV_W'(MEM_CLK_DIV - 1));
        end
    endgenerate

    // -- Transaction state ------------------------------------------------
    logic                 active;       // a transaction is currently in progress
    logic                 active_we;    // type of the active transaction (0=read, 1=write)
    logic [XLEN-1:0]      active_addr;  // latched address for the active transaction
    logic [LINE_BITS-1:0] active_wdata; // latched write data
    logic [$clog2(LATENCY+1)-1:0] count; // tick counter (counts 1 to LATENCY-1)

    // Convert the byte address to a word index, aligned to the start of the
    // cache line. Bits [1:0] are the byte offset (always 0 for aligned access)
    // and bits [4:2] are the word offset within the line — both are dropped here
    // since we always read/write the full line starting at word_base.
    logic [$clog2(DEPTH)-1:0] word_base;
    assign word_base = active_addr[$clog2(DEPTH)+1 : 2];

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            active       <= 1'b0;
            active_we    <= 1'b0;
            active_addr  <= '0;
            active_wdata <= '0;
            count        <= '0;
            div_cnt      <= '0;
            ready        <= 1'b0;
            rdata        <= '0;
        end else begin
            ready <= 1'b0;  // default: ready is low every cycle

            // Skipped for MEM_CLK_DIV=1: tick is a constant 1, so div_cnt is unused.
            if (MEM_CLK_DIV > 1) begin
                if (div_cnt == DIV_W'(MEM_CLK_DIV - 1))
                    div_cnt <= '0;
                else
                    div_cnt <= div_cnt + 1'b1;
            end

            if (!active) begin
                // Idle — capture is not gated by tick so new requests register
                // on the very next CPU cycle regardless of div_cnt phase.
                if (req) begin
                    active       <= 1'b1;
                    active_we    <= we;
                    active_addr  <= addr;
                    active_wdata <= wdata;

                    if (MEM_CLK_DIV > 1) begin
                        // Phase-align: set div_cnt to 1 so the first tick fires
                        // exactly MEM_CLK_DIV-1 CPU cycles after this posedge.
                        // count starts at 0; LATENCY ticks advance it to LATENCY-1,
                        // yielding exactly LATENCY*MEM_CLK_DIV CPU cycles total.
                        div_cnt <= DIV_W'(1);
                        count   <= '0;
                    end else begin
                        // MEM_CLK_DIV=1: original behavior unchanged, count starts at 1.
                        count <= 1;
                    end
                end
            end else if (tick) begin
                // Same threshold (LATENCY-1) works for both count-start values:
                //   MEM_CLK_DIV=1  -> count: 1..LATENCY-1 -> exactly LATENCY CPU cycles.
                //   MEM_CLK_DIV>1  -> count: 0..LATENCY-1 -> exactly LATENCY*MEM_CLK_DIV CPU cycles.
                if (count == LATENCY - 1) begin
                    ready  <= 1'b1;
                    active <= 1'b0;
                    count  <= '0;

                    if (active_we) begin
                        // Write-back: unpack the 256-bit line into 8 consecutive words.
                        memory[word_base + 0] <= active_wdata[0*32 +: 32];
                        memory[word_base + 1] <= active_wdata[1*32 +: 32];
                        memory[word_base + 2] <= active_wdata[2*32 +: 32];
                        memory[word_base + 3] <= active_wdata[3*32 +: 32];
                        memory[word_base + 4] <= active_wdata[4*32 +: 32];
                        memory[word_base + 5] <= active_wdata[5*32 +: 32];
                        memory[word_base + 6] <= active_wdata[6*32 +: 32];
                        memory[word_base + 7] <= active_wdata[7*32 +: 32];
                        rdata <= '0;
                    end else begin
                        // Read: pack 8 consecutive words into the 256-bit output line.
                        rdata[0*32 +: 32] <= memory[word_base + 0];
                        rdata[1*32 +: 32] <= memory[word_base + 1];
                        rdata[2*32 +: 32] <= memory[word_base + 2];
                        rdata[3*32 +: 32] <= memory[word_base + 3];
                        rdata[4*32 +: 32] <= memory[word_base + 4];
                        rdata[5*32 +: 32] <= memory[word_base + 5];
                        rdata[6*32 +: 32] <= memory[word_base + 6];
                        rdata[7*32 +: 32] <= memory[word_base + 7];
                    end
                end else begin
                    count <= count + 1;
                end
            end
        end
    end

endmodule