`ifndef MEM_REG_TEST
`define MEM_REG_TEST

`include "mem_reg.v"
`include "mem_reg_ref.svh"   // class regfile with read_reg/write_reg/reset

module mem_reg_test;

  // -----------------------------
  // Configuration parameters
  // -----------------------------
  localparam int p_WORD_LEN  = 16;
  localparam int p_MAX_TESTS = 1000;

  // -----------------------------
  // Signals to/from the DUT
  // -----------------------------
  wire [p_WORD_LEN-1:0] out1;   // async read data 1
  wire [p_WORD_LEN-1:0] out2;   // async read data 2

  bit  [2:0]            src1;   // read address 1
  bit  [2:0]            src2;   // read address 2
  bit  [2:0]            tgt;    // write address
  bit  [p_WORD_LEN-1:0] inp;    // write data

  bit                   clk;    // clock
  bit                   writeEn;// write enable

  // -----------------------------
  // Device Under Test
  // -----------------------------
  mem_reg #(
      .p_WORD_LEN      (p_WORD_LEN),
      .p_REG_ADDR_LEN  (3),
      .p_REG_FILE_SIZE (8)
  ) regfile_dut (
    .i_clk       (clk),
    .i_wr_en     (writeEn),
    .i_src1      (src1),
    .i_src2      (src2),
    .i_tgt       (tgt),
    .o_src1_data (out1),
    .o_src2_data (out2),
    .i_tgt_data  (inp)
  );

  // -----------------------------
  // Reference model
  // -----------------------------
  regfile reference;

  // -----------------------------
  // Functional coverage
  // -----------------------------
  covergroup cg @(posedge clk);
      // Cover all read addresses and (when writing) all targets
      coverpoint src1;
      coverpoint src2;
      coverpoint tgt iff (writeEn);

      // Structural hazards (forwarding cases in a pipeline)
      same_src1_tgt : coverpoint (tgt == src1) iff (writeEn);
      same_src2_tgt : coverpoint (tgt == src2) iff (writeEn);

      // Writes to r0 (should be ignored by RTL)
      write_r0 : coverpoint (tgt == 3'd0) iff (writeEn);
  endgroup : cg
  cg cg_inst;

  // -----------------------------
  // Clocking block (race-free I/F)
  //   • outputs drive at #0
  //   • inputs sampled #1step later
  // -----------------------------
  clocking cb_reg @(posedge clk);
      default output #0 input #1step;
      output src1, src2, tgt, inp, writeEn;
      input  out1, out2;
  endclocking

  // -----------------------------
  // 100 MHz clock
  // -----------------------------
  always #5 clk = ~clk;

  // -----------------------------
  // Main test
  // -----------------------------
  initial begin
    $display("[TB] Starting register file test");
    $display("[TB] Random seed: %0d", $get_initial_random_seed());

    // Waveform dump
    $dumpfile("mem_reg_tb.vcd");
    $dumpvars(0, mem_reg_test);

    // Initialize reference model and coverage
    reference = new();
    reference.reset();
    cg_inst   = new();

    // Small settle time
    #1;

    // Stimulus loop
    repeat (p_MAX_TESTS) begin
        // Randomize with in-range addresses; bias against writing r0
        void'( std::randomize(src1, src2, tgt, inp, writeEn)
               with {
                  src1 inside {[0:7]};
                  src2 inside {[0:7]};
                  tgt  inside {[0:7]};
                  // Either no write, or write to a non-zero register most of the time
                  (writeEn == 0) || (tgt != 0);
               });

        // Drive DUT for this cycle
        cb_reg.src1    <= src1;
        cb_reg.src2    <= src2;
        cb_reg.tgt     <= tgt;
        cb_reg.inp     <= inp;
        cb_reg.writeEn <= writeEn;

        // Immediate checks (same cycle): async reads and X-safety
        assert (^out1 !== 1'bx) else $fatal("out1 is X/Z at time %0t", $time);
        assert (^out2 !== 1'bx) else $fatal("out2 is X/Z at time %0t", $time);

        // Asynchronous read data must reflect the current reference contents
        assert (reference.read_reg(src1) === out1)
          else $fatal("%0t SRC1 mismatch. r%0d : DUT=%h REF=%h",
                      $time, src1, out1, reference.read_reg(src1));
        assert (reference.read_reg(src2) === out2)
          else $fatal("%0t SRC2 mismatch. r%0d : DUT=%h REF=%h",
                      $time, src2, out2, reference.read_reg(src2));

        // Advance one clock; DUT may write on this edge
        @(cb_reg);

        // Update the reference model AFTER the clock if a write occurred
        if (writeEn)
          reference.write_reg(tgt, inp);
    end

    // Coverage report
    $display("Coverage : %.2f%%", cg_inst.get_coverage());

    $display("[TB] Finished register file test");
    $finish();
  end

endmodule

`endif // MEM_REG_TEST
