`ifndef MEM_DATA_V
`define MEM_DATA_V

module mem_data #(
    // ------------------- User parameters -------------------
    parameter int p_WORD_LEN   = 16,         // bits per word
    parameter int p_ADDR_LEN   = 10,         // address lines (depth = 2**p_ADDR_LEN)
    parameter bit p_ASYNC_READ = 1,          // 1 → async, 0 → registered read
    parameter bit p_INIT_TO_ZERO = 1,        // zero‑initialise in sim
    parameter string p_INIT_FILE = "",      // preload file (hex)

    // ----------------- Derived constant --------------------
    localparam int p_MEM_SIZE   = 1 << p_ADDR_LEN
)(
    // -----------------  Port list --------------------------
    input  logic                      i_clk,     // rising‑edge clock
    input  logic                      i_wr_en,   // write enable

    input  logic [p_ADDR_LEN-1:0]     i_addr,    // R/W address
    output logic [p_WORD_LEN-1:0]     o_rd_data, // read data
    input  logic [p_WORD_LEN-1:0]     i_wr_data  // write data
);

    // --------------------------------------------------------
    //  Memory array declaration
    // --------------------------------------------------------
    logic [p_WORD_LEN-1:0] r_memory [p_MEM_SIZE];

`ifndef SYNTHESIS
    generate
        if (p_INIT_TO_ZERO) begin : gen_zero_init
            initial for (int idx = 0; idx < p_MEM_SIZE; idx++)
                r_memory[idx] = '0;
        end
        if (p_INIT_FILE != "") begin : gen_file_init
            initial $readmemh(p_INIT_FILE, r_memory);
        end
    endgenerate
`endif

    // --------------------------------------------------------
    //  Synchronous write — write‑first
    // --------------------------------------------------------
    always_ff @(posedge i_clk) begin
        if (i_wr_en)
            r_memory[i_addr] <= i_wr_data;
    end

    // --------------------------------------------------------
    //  Read path (async vs. sync selectable)
    // --------------------------------------------------------
    generate
        if (p_ASYNC_READ) begin
            assign o_rd_data = r_memory[i_addr];
        end else begin
            logic [p_WORD_LEN-1:0] r_rd_q;
            assign o_rd_data = r_rd_q;
            always_ff @(posedge i_clk)
                r_rd_q <= r_memory[i_addr];
        end
    endgenerate

`ifndef FORMAL_OFF
    (* anyconst *) logic [p_ADDR_LEN-1:0] f_test_addr;
    logic [p_WORD_LEN-1:0] f_test_data = '0;

    always_comb begin
        assert(r_memory[f_test_addr] == f_test_data);
        if (i_addr == f_test_addr)
            assert(o_rd_data == f_test_data);
    end

    always_ff @(posedge i_clk)
        if (i_wr_en && (i_addr == f_test_addr))
            f_test_data <= i_wr_data;
`endif

endmodule

`endif // MEM_DATA_V
