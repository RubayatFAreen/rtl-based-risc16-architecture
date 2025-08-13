`ifndef DESIGN_SV
`define DESIGN_SV
`include "core.v"
`include "mem_data.v"

module toplevel (
    input  logic        clk,    // global system clock
    output logic [15:0] pc      // expose PC for waveform/debug
);

    // --------------------------------------------------------
    //  Parameters and local constants
    // --------------------------------------------------------
    localparam int p_INST_NUM       = 1024;          // depth of I-mem
    localparam int p_DATA_ADDR_LEN  = 10;            // log2(data words)
    localparam int p_DATA_NUM       = 2 ** p_DATA_ADDR_LEN;
    localparam     p_CODE_FILE      = "code.data";   // hex/bit file

    // --------------------------------------------------------
    //  Instruction memory  (simple ROM initialised from file)
    // --------------------------------------------------------
    reg [15:0] inst_memory [0:p_INST_NUM-1];

    initial begin
        // $readmemb expects binary text lines (e.g., "10101010")
        // Use $readmemh if your file is hex.
        $readmemb(p_CODE_FILE, inst_memory);
    end

    // --------------------------------------------------------
    //  Wires between core ↔ data-memory
    // --------------------------------------------------------
    wire [15:0] w_rd_data;   // data read from mem_data
    wire [15:0] w_wr_data;   // data to write
    wire [15:0] w_addr;      // address bus
    wire        w_wr_en;     // write-enable

    // --------------------------------------------------------
    //  Device Under Test: CPU core (no I-mem)
    // --------------------------------------------------------
    core core_dut (
        // --- global ---
        .i_clk          (clk),
        .i_rst          (1'b0),               // hard-wired no-reset

        // --- instruction interface ---
        .i_inst         (inst_memory[pc]),    // simple ROM lookup
        .o_pc           (pc),

        // --- data-memory interface ---
        .i_mem_rd_data  ( (w_addr < p_DATA_NUM) ? w_rd_data : 16'b0 ),
        .o_mem_wr_data  (w_wr_data),
        .o_mem_addr     (w_addr),
        .o_mem_wr_en    (w_wr_en)
    );

    // --------------------------------------------------------
    //  Data memory (single-port RAM with async read)
    // --------------------------------------------------------
    mem_data #(
        .p_WORD_LEN (16),
        .p_ADDR_LEN (p_DATA_ADDR_LEN)
    ) datamem (
        .i_clk      (clk),
        // mask writes that exceed data-RAM bounds
        .i_wr_en    (w_wr_en && (w_addr < p_DATA_NUM)),

        .i_addr     (w_addr),
        .o_rd_data  (w_rd_data),
        .i_wr_data  (w_wr_data)
    );

endmodule

`endif  // DESIGN_SV
