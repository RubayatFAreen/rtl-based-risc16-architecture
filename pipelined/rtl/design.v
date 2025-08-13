`ifndef DESIGN_SV
`define DESIGN_SV

`include "core.v"
`include "mem_data.v"

module toplevel (
    input         clk,          // Global clock
    output [15:0] pc            // Expose program counter (used to index ROM)
);

    // -------------------------------
    //  System sizing parameters
    // -------------------------------
    localparam int p_INST_NUM       = 1024;                     // I-mem depth
    localparam int p_DATA_ADDR_LEN  = 10;                       // log2(D-mem)
    localparam int p_DATA_NUM       = 2 ** p_DATA_ADDR_LEN;     // D-mem words

    // File to preload the instruction ROM (binary lines for $readmemb)
    parameter string p_CODE_FILE = "code.data";

    // -------------------------------
    //  Instruction memory (ROM)
    // -------------------------------
    // Simple behavioral ROM; change $readmemb to $readmemh if using hex.
    logic [15:0] inst_memory [0:p_INST_NUM-1];

    initial begin
        $display("[TOP] Loading instruction ROM from '%s' ...", p_CODE_FILE);
        $readmemb(p_CODE_FILE, inst_memory);
    end

    // -------------------------------
    //  Data memory <-> core wiring
    // -------------------------------
    wire [15:0] w_rd_data;     // data read from data memory
    wire [15:0] w_wr_data;     // data written to data memory
    wire [15:0] w_addr;        // data memory address
    wire        w_wr_en;       // write enable to data memory

    // Register the address for clean OOB gating on async read
    logic [15:0] r_addr_prev;

    always_ff @(posedge clk)
        r_addr_prev <= w_addr;

    // -------------------------------
    //  Device Under Test — the core
    // -------------------------------
    core core_dut (
        .i_clk         (clk),
        .i_rst         (1'b0),                      // no global reset in this top

        // Instruction memory interface (combinational read)
        .i_inst        (inst_memory[pc]),
        .o_pc_next     (pc),

        // Data memory interface
        //  - Read data is gated by previous-cycle address bounds to avoid
        //    out-of-range values when address changes near the clock.
        .i_mem_rd_data ((r_addr_prev < p_DATA_NUM) ? w_rd_data : 16'h0000),
        .o_mem_wr_data (w_wr_data),
        .o_mem_addr    (w_addr),
        .o_mem_wr_en   (w_wr_en)
    );

    // -------------------------------
    //  Data memory
    // -------------------------------
    //  • Asynchronous read (default parameter) to match the core timing.
    //  • Writes beyond D-mem size are masked off.
    mem_data #(
        .p_WORD_LEN (16),
        .p_ADDR_LEN (p_DATA_ADDR_LEN)
    ) datamem (
        .i_clk     (clk),
        .i_wr_en   (w_wr_en && (w_addr < p_DATA_NUM)),  // mask OOB writes
        .i_addr    (w_addr),
        .o_rd_data (w_rd_data),
        .i_wr_data (w_wr_data)
    );

endmodule

`endif // DESIGN_SV
