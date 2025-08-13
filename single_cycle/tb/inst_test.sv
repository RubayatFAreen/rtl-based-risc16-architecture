`ifndef INST_TEST_SV
`define INST_TEST_SV

`include "simulator.svh"      // only for typedefs if used in instruction
`include "instruction.svh"    // class instruction with rand, to_bin, from_bin, cg

module inst_test;

    // --------------------------------------------------------
    //  Configuration
    // --------------------------------------------------------
    localparam int MAX_COUNT = 25_000;

    // --------------------------------------------------------
    //  Objects under test
    // --------------------------------------------------------
    instruction inst;   // randomly generated
    instruction inst2;  // result of encode→decode round‑trip

    int mismatch_cnt = 0;

    // --------------------------------------------------------
    //  Test procedure
    // --------------------------------------------------------
    initial begin
        $display("[TB] Starting instruction encode/decode test …");
        $dumpfile("inst_tb.vcd");
        $dumpvars(0, inst_test);

        inst  = new();
        inst2 = new();

        for (int i = 0; i < MAX_COUNT; i++) begin
            // Randomize with constraints internal to instruction class
            assert (inst.randomize()) else $fatal("Randomize failed at iter %0d", i);
            inst.cg.sample();                    // functional coverage

            // Round‑trip: bin → struct → bin
            logic [15:0] inst_bin = inst.to_bin();
            inst2.from_bin(inst_bin);

            // Optional trace (1% of iterations)
            if (i % (MAX_COUNT/100) == 0)
                $display("%0d  %s  |  %s", i, inst.to_string(), inst2.to_string());

            // Compare human‑readable strings for equality; could also compare fields
            if (inst.to_string() !== inst2.to_string()) begin
                mismatch_cnt++;
                $display("Mismatch @ %0d : %s vs %s", i, inst.to_string(), inst2.to_string());
            end
        end

        $display("Mismatches : %0d", mismatch_cnt);
        $display("Coverage   : %.2f%%", inst.get_coverage());
        $display("[TB] Instruction test completed.");
        $finish;
    end

endmodule

`endif // INST_TEST_SV
