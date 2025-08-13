`ifndef MEM_DATA_V
`define MEM_DATA_V

module mem_data #(
    parameter int p_WORD_LEN = 16,                 // bits per word
    parameter int p_ADDR_LEN = 10,                 // address lines
    localparam int p_MEM_SIZE = 2 ** p_ADDR_LEN    // number of words
) (
    input  logic                    i_clk,         // Clock signal
    input  logic                    i_wr_en,       // High to write on posedge

    input  logic [p_ADDR_LEN-1:0]   i_addr,        // Address of data
    output logic [p_WORD_LEN-1:0]   o_rd_data = '0,// **Registered** read data
    input  logic [p_WORD_LEN-1:0]   i_wr_data      // Data for writing (on posedge)
);

    // ------------------------------------------
    // Address truncation (protect against OOB)
    // ------------------------------------------
    // Since depth is 2**p_ADDR_LEN, truncation is effectively `i_addr[p_ADDR_LEN-1:0]`.
    // Using $clog2(p_MEM_SIZE) keeps intent obvious if the formula ever changes.
    wire [$clog2(p_MEM_SIZE)-1:0] w_addr_trunc = i_addr[$clog2(p_MEM_SIZE)-1:0];

    // ------------------------------------------
    // Memory array
    // ------------------------------------------
    logic [p_WORD_LEN-1:0] r_memory [p_MEM_SIZE-1:0];

    // ------------------------------------------
    // Simulation init (zero contents)
    // ------------------------------------------
    // Use blocking '=' in initial for deterministic init in sim.
    integer i;
    initial begin
        for (i = 0; i < p_MEM_SIZE; i = i + 1)
            r_memory[i] = '0;
    end

    // ------------------------------------------
    // Synchronous write + registered read
    // ------------------------------------------
    // Read-during-write to same address returns the **old** value (R->W ordering).
    always_ff @(posedge i_clk) begin
        if (i_wr_en)
            r_memory[w_addr_trunc] <= i_wr_data;

        o_rd_data <= r_memory[w_addr_trunc];
    end

// ------------------------------------------
// Lightweight formal instrumentation
// ------------------------------------------
`ifdef FORMAL
    (* anyconst *) logic [p_ADDR_LEN-1:0] f_test_addr;
    logic [p_WORD_LEN-1:0] f_test_data = '0;
    logic f_past_valid = 1'b0;

    // Mirror the truncation used by the RTL
    wire [$clog2(p_MEM_SIZE)-1:0] f_addr_trunc = f_test_addr[$clog2(p_MEM_SIZE)-1:0];

    // Invariant: our shadow value tracks the RTL memory at f_addr_trunc
    always_comb begin
        assert(r_memory[f_addr_trunc] == f_test_data);
    end

    always_ff @(posedge i_clk) begin
        // Registered read check (1-cycle latency with truncation)
        if (f_past_valid && ($past(i_addr[$clog2(p_MEM_SIZE)-1:0]) == f_addr_trunc))
            assert(o_rd_data == $past(f_test_data));

        // Update shadow on writes to the tracked address
        if (i_wr_en && (w_addr_trunc == f_addr_trunc))
            f_test_data <= i_wr_data;

        f_past_valid <= 1'b1;
    end
`endif

endmodule

`endif // MEM_DATA_V
