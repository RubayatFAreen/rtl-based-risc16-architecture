`ifndef MEM_REG_V
`define MEM_REG_V

module mem_reg #(
    parameter p_WORD_LEN      = 16,
    parameter p_REG_ADDR_LEN  = 3,
    parameter p_REG_FILE_SIZE = 8
) (
    input                               i_clk,         // Clock signal

    input  [p_REG_ADDR_LEN-1:0]         i_src1,        // Read address 1
    input  [p_REG_ADDR_LEN-1:0]         i_src2,        // Read address 2
    input  [p_REG_ADDR_LEN-1:0]         i_tgt,         // Write register address

    output [p_WORD_LEN-1:0]             o_src1_data,   // Read output 1 (async)
    output [p_WORD_LEN-1:0]             o_src2_data,   // Read output 2 (async)
    input  [p_WORD_LEN-1:0]             i_tgt_data,    // Data to write (on posedge)

    input                               i_wr_en        // High to write on posedge
);

    // ----------------------------------------------------------------
    // Storage array
    // ----------------------------------------------------------------
    reg [p_WORD_LEN-1:0] r_memory [p_REG_FILE_SIZE-1:0];

    // ----------------------------------------------------------------
    // Simulation initialization (deterministic, zeroed state)
    // ----------------------------------------------------------------
    integer i;
    initial begin
        for (i = 0; i < p_REG_FILE_SIZE; i = i + 1)
            r_memory[i] = {p_WORD_LEN{1'b0}}; // blocking '=' is fine in initial
    end

    // ----------------------------------------------------------------
    // Asynchronous read ports
    //  • r0 is forced to 0 (reads ignore stored value even if X in sim)
    //  • Using case-equality (===) so X/Z won’t spuriously match zero
    // ----------------------------------------------------------------
    assign o_src1_data = (i_src1 === {p_REG_ADDR_LEN{1'b0}}) ? {p_WORD_LEN{1'b0}} : r_memory[i_src1];
    assign o_src2_data = (i_src2 === {p_REG_ADDR_LEN{1'b0}}) ? {p_WORD_LEN{1'b0}} : r_memory[i_src2];

    // ----------------------------------------------------------------
    // Synchronous write port
    //  • Non-blocking assignments for sequential logic
    //  • Ignore writes to r0
    // ----------------------------------------------------------------
    always @(posedge i_clk) begin : write_block
        if (i_wr_en) begin
            if (i_tgt != {p_REG_ADDR_LEN{1'b0}})
                r_memory[i_tgt] <= i_tgt_data;
        end
    end

// --------------------------------------------------------------------
// Optional formal instrumentation (excluded when compiled under core)
// --------------------------------------------------------------------
`ifdef FORMAL
`ifndef CORE_V
    // Choose an arbitrary but fixed register (not r0) and track its value
    (* anyconst *) reg  [p_REG_ADDR_LEN-1:0] f_test_reg;
    reg           [p_WORD_LEN-1:0]           f_test_val = {p_WORD_LEN{1'b0}};
    reg                                      f_past_valid = 1'b0;

    always @* begin
        // Exercise a non-zero register
        assume (f_test_reg !== {p_REG_ADDR_LEN{1'b0}});

        // r0 is always zero
        assert (r_memory[{p_REG_ADDR_LEN{1'b0}}] == {p_WORD_LEN{1'b0}});

        // Track the chosen register’s mirror value
        assert (r_memory[f_test_reg] == f_test_val);

        // Outputs must never be indeterminate
        assert (^o_src1_data !== 1'bx);
        assert (^o_src2_data !== 1'bx);

        // Reading r0 yields 0
        if (i_src1 == {p_REG_ADDR_LEN{1'b0}}) assert (o_src1_data == {p_WORD_LEN{1'b0}});
        if (i_src2 == {p_REG_ADDR_LEN{1'b0}}) assert (o_src2_data == {p_WORD_LEN{1'b0}});

        // Reads of the tracked register return the tracked value
        if (i_src1 == f_test_reg) assert (o_src1_data == f_test_val);
        if (i_src2 == f_test_reg) assert (o_src2_data == f_test_val);
    end

    always @(posedge i_clk) begin
        // Update mirror on writes to the tracked register
        if (i_wr_en && (i_tgt == f_test_reg))
            f_test_val <= i_tgt_data;

        f_past_valid <= 1'b1;
    end
`endif
`endif

endmodule

`endif // MEM_REG_V
