`ifndef MEM_REG_V
`define MEM_REG_V

module mem_reg #(
    // -----------------  Static parameters  ------------------
    parameter int p_WORD_LEN      = 16,   // width of each register
    parameter int p_ADDR_LEN      = 3 ,   // log2(number of regs)
    parameter int p_REG_FILE_SIZE = 8     // number of regs (must be 2^p_ADDR_LEN)
)(
    // -----------------  Clock  -------------------------------
    input  logic                         i_clk,

    // -----------------  Read‑port addresses  ----------------
    input  logic [p_ADDR_LEN-1:0]        i_src1,
    input  logic [p_ADDR_LEN-1:0]        i_src2,

    // -----------------  Write‑port controls  ----------------
    input  logic [p_ADDR_LEN-1:0]        i_tgt,
    input  logic [p_WORD_LEN-1:0]        i_tgt_data,
    input  logic                         i_wr_en,

    // -----------------  Read‑port data outs  ----------------
    output logic [p_WORD_LEN-1:0]        o_src1_data,
    output logic [p_WORD_LEN-1:0]        o_src2_data
);

    // --------------------------------------------------------
    //  Register array
    // --------------------------------------------------------
    //
    //  NOTE:  we call it reg_file[] everywhere for consistency.
    //
    reg [p_WORD_LEN-1:0] reg_file [0:p_REG_FILE_SIZE-1];

    // --------------------------------------------------------
    //  Power‑on initialisation (simulation only)
    // --------------------------------------------------------
    integer idx;
    initial begin
        for (idx = 0; idx < p_REG_FILE_SIZE; idx = idx + 1)
            reg_file[idx] = '0;           // all Xilinx/ASIC sims start clean
    end

    // --------------------------------------------------------
    //  Asynchronous read ports
    // --------------------------------------------------------
    //
    //  • Continuous assignments (`assign`) emulate a pure LUT read.
    //  • Register 0 is hard‑wired to zero — saves a flip‑flop.
    //  • Case‑equality (===) avoids treating X/Z as “match”.
    //
    assign o_src1_data = (i_src1 === '0) ? '0 : reg_file[i_src1];
    assign o_src2_data = (i_src2 === '0) ? '0 : reg_file[i_src2];

    // --------------------------------------------------------
    //  Synchronous write port (pos‑edge)
    // --------------------------------------------------------
    //
    //  • Normal RTL rule: use non‑blocking (<=) for sequential logic.
    //  • Attempting to write R0 is ignored.
    //
    always_ff @(posedge i_clk) begin
        if (i_wr_en && (i_tgt != '0))
            reg_file[i_tgt] <= i_tgt_data;
    end

// ------------------------------------------------------------
//  Formal‑verification harness (only when `FORMAL` undefined)
// ------------------------------------------------------------
`ifndef FORMAL
    // *anyconst* picks an arbitrary but *fixed* register index for proofs
    (* anyconst *) logic [p_ADDR_LEN-1:0] f_test_reg;

    // Shadow variable tracks the value that *should* be in that register
    logic [p_WORD_LEN-1:0] f_test_val = '0;

    // ----------  Combinational assertions  ----------
    always_comb begin
        // test register may be anything except zero (so we actually exercise RF)
        assume (f_test_reg !== '0);

        // 1) internal array value must match our shadow copy
        assert (reg_file[f_test_reg] == f_test_val);

        // 2) outputs must never be X
        assert (^o_src1_data !== 1'bx);
        assert (^o_src2_data !== 1'bx);

        // 3) reads hitting the test register must return the tracked value
        if (i_src1 == f_test_reg)  assert (o_src1_data == f_test_val);
        if (i_src2 == f_test_reg)  assert (o_src2_data == f_test_val);
    end

    // ----------  Sequential tracking  ----------
    always_ff @(posedge i_clk) begin
        if (i_wr_en && (i_tgt == f_test_reg))
            f_test_val <= i_tgt_data;
    end
`endif  // FORMAL

endmodule

`endif  // MEM_REG_V
