`ifndef MEM_DATA_TEST
`define MEM_DATA_TEST

`include "mem_data.v"
`include "mem_data_ref.svh"  // class datamem #(SIZE) with write_mem/read_mem

module mem_data_test;

  // -----------------------------
  // Configuration parameters
  // -----------------------------
  localparam int p_ADDR_LEN   = 10;
  localparam int p_MAX_TESTS  = 100_000;
  localparam int p_MEM_SIZE   = 2 ** p_ADDR_LEN;

  // -----------------------------
  // Signals to/from the DUT
  // -----------------------------
  logic                       clk;       // Clock
  logic                       writeEn;   // Write enable
  logic [p_ADDR_LEN-1:0]      address;   // Address
  logic [15:0]                dataIn;    // Data for writing
  wire  [15:0]                dataOut;   // Registered read data

  // -----------------------------
  // DUT
  // -----------------------------
  mem_data #(
      .p_WORD_LEN (16),
      .p_ADDR_LEN (p_ADDR_LEN)
  ) datamem_dut (
    .i_clk     (clk),
    .i_wr_en   (writeEn),
    .i_addr    (address),
    .o_rd_data (dataOut),
    .i_wr_data (dataIn)
  );

  // -----------------------------
  // Reference model (behavioral)
  // -----------------------------
  datamem #(p_MEM_SIZE) reference;

  // -----------------------------
  // Functional coverage
  // -----------------------------
  covergroup cg_mem @(posedge clk);
    addr_cg : coverpoint address {
      bins all_addr[] = {[0:p_MEM_SIZE-1]}; // one bin per address (auto-sliced)
    }
    rw_cross : cross addr_cg, writeEn;
  endgroup
  cg_mem cg_inst;

  // -----------------------------
  // Clocking block (race-free I/F)
  //   • outputs drive at #0
  //   • inputs sampled #1step later
  // -----------------------------
  clocking cb_mem @(posedge clk);
    default output #0 input #1step;
    output address, dataIn, writeEn;
    input  dataOut;
  endclocking

  // 100 MHz clock
  always #5 clk = ~clk;

  // -----------------------------
  // Test sequence
  // -----------------------------
  initial begin
    $display("[TB] Starting data memory test");
    $display("[TB] Random seed: %0d", $get_initial_random_seed());

    // VCD dump
    $dumpfile("mem_data_tb.vcd");
    $dumpvars(0, mem_data_test);

    // Initialize objects
    reference = new();
    cg_inst   = new();

    // Main randomized stimulus loop
    repeat (p_MAX_TESTS) begin
      // Randomize inputs with in-range address
      void'( std::randomize(address, dataIn, writeEn)
             with { address inside {[0:p_MEM_SIZE-1]}; } );

      // Drive DUT via clocking block
      cb_mem.address <= address;
      cb_mem.dataIn  <= dataIn;
      cb_mem.writeEn <= writeEn;

      // Advance one clock: DUT o_rd_data now reflects
      // the *old* value at `address` (registered read, read-before-write)
      @(cb_mem);

      // Check read matches the reference model's *pre-write* value
      assert (reference.read_mem(address) === dataOut)
        else $fatal("Read mismatch @%0t  addr=%0d  DUT=%h  REF=%h",
                    $time, address, dataOut, reference.read_mem(address));

      // Update reference model after the check (mirrors DUT ordering)
      if (writeEn)
        reference.write_mem(address, dataIn);
    end

    // Coverage report
    $display("Address coverage : %.2f%%", cg_inst.get_coverage());
    $display("[TB] Data memory test PASS");
    $finish();
  end

endmodule

`endif // MEM_DATA_TEST
