// =============================================================================
// main_mem_model.sv — Main Memory Model
// =============================================================================
// Capacity  : 64 KB (16 384 x 32-bit words)
// Latency   : 25 clock cycles from request to data ready
// Burst size: 256 bits (one full cache line = 8 x 32-bit words)
// Init file : optional hex file loaded via $readmemh (INIT_FILE parameter)
//
// This module simulates the latency of real DRAM. The cache controller sends
// a single-cycle request pulse, then waits. Exactly 25 cycles later the module
// asserts ready for one cycle and either returns a line (read) or confirms the
// write (write-back).
//
// Protocol (used by cache_ctrl):
//
//   Read request:
//     1. cache_ctrl asserts req=1, we=0, addr=line base address (one cycle)
//     2. This module counts 25 cycles
//     3. On cycle 25: ready=1 for exactly one cycle, rdata holds the 256-bit line
//
//   Write request (write-back of a dirty cache line):
//     1. cache_ctrl asserts req=1, we=1, addr=line base, wdata=256-bit line
//     2. This module counts 25 cycles
//     3. On cycle 25: ready=1 for exactly one cycle (write confirmation)
//
// Important: cache_ctrl must not issue a new request until ready arrives.
//            ready is guaranteed to be high for exactly one cycle.
// =============================================================================

module main_mem_model #(
    parameter int    XLEN       = 32,
    parameter int    DEPTH      = 16384,             // 64 KB / 4 bytes per word
    parameter int    LINE_WORDS = 8,
    parameter int    LINE_BITS  = LINE_WORDS * 32,   // 256 bits per cache line
    parameter int    LATENCY    = 25,
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

    // -- Transaction state ------------------------------------------------
    logic                 active;       // a transaction is currently in progress
    logic                 active_we;    // type of the active transaction (0=read, 1=write)
    logic [XLEN-1:0]      active_addr;  // latched address for the active transaction
    logic [LINE_BITS-1:0] active_wdata; // latched write data
    logic [$clog2(LATENCY+1)-1:0] count; // cycle counter (counts 1 to LATENCY-1)

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
            ready        <= 1'b0;
            rdata        <= '0;
        end else begin
            ready <= 1'b0;  // default: ready is low every cycle

            if (!active) begin
                // Idle — waiting for cache_ctrl to issue a request.
                if (req) begin
                    active       <= 1'b1;
                    active_we    <= we;
                    active_addr  <= addr;
                    active_wdata <= wdata;
                    count        <= 1;
                end
            end else begin
                // Counting down the latency. We fire on LATENCY-1 (not LATENCY)
                // because the request is registered on the first active cycle,
                // so the counter can only be checked starting from cycle 2.
                // This gives us exactly LATENCY cycles from req to ready.
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