`ifndef INST_TEST_SV
`define INST_TEST_SV

`include "simulator.svh"    // not strictly required, but harmless
`include "instruction.svh"  // class 'instruction' with rand/coverage/helpers

module inst_test;

  // -----------------------------
  // Configuration
  // -----------------------------
  localparam int max_count = 25_000;

  // -----------------------------
  // Objects under test
  // -----------------------------
  instruction inst;   // randomized source
  instruction inst2;  // result of decode(from_bin)

  int i = 0;

  // -----------------------------
  // Main test
  // -----------------------------
  initial begin
    int mismatch_str = 0;
    int mismatch_bin = 0;

    $display("[TB] Starting instruction encode/decode test …");
    $display("[TB] Random seed: %0d", $get_initial_random_seed());

    // VCD for optional debug
    $dumpfile("inst_tb.vcd");
    $dumpvars(0, inst_test);

    // Construct objects
    inst  = new();
    inst2 = new();

    // Main loop
    for (i = 0; i < max_count; i++) begin
      logic [15:0] bin1, bin2;

      // Generate a random instruction (respecting internal constraints)
      if (inst.randomize()) begin
        // Sample functional coverage inside the class
        inst.cg.sample();

        // Encode → Decode → Encode
        bin1 = inst.to_bin();
        inst2.from_bin(bin1);
        bin2 = inst2.to_bin();

        // Occasionally print a trace (about 1% of the time)
        if (i % (max_count / 100) == 0) begin
          $display("%6d  %s  |  %s", i, inst.to_string(), inst2.to_string());
        end

        // Human-readable equality (useful to spot formatting/pretty-print issues)
        assert (inst.to_string() == inst2.to_string()) else begin
          mismatch_str++;
          $display("! String mismatch @%0d : '%s'  vs  '%s'",
                   i, inst.to_string(), inst2.to_string());
        end

        // **Binary round-trip** equality — the important check
        // Catches bugs in sign-extension, reserved bits, or encoding layout.
        assert (bin2 === bin1) else begin
          mismatch_bin++;
          $display("! Binary mismatch  @%0d : bin1=%h  bin2=%h  (%s)",
                   i, bin1, bin2, inst.to_string());
        end

      end else begin
        // Randomization failed — report and continue (rare if constraints are sound)
        $display("! Randomization
