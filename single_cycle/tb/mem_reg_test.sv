`ifndef MEM_REG_TEST
`define MEM_REG_TEST

`include "mem_reg.v"
`include "mem_reg_ref.svh"   // simple class reference model (read_reg/ write_reg)

module mem_reg_test;

    // --------------------------------------------------------
    //  Local parameters
    // --------------------------------------------------------
    localparam int p_WORD_LEN   = 16;
    localparam int p_MAX_TESTS  = 1000;

    // --------------------------------------------------------
    //  DUT I/O declarations
    // --------------------------------------------------------
    bit                     clk   = 0;
    bit                     writeEn;
    bit  [2:0]              src1, src2, tgt;
    bit  [p_WORD_LEN-1:0]   inp;
    wire [p_WORD_LEN-1:0]   out1, out2;

    // --------------------------------------------------------
    //  Device Under Test
    // --------------------------------------------------------
    mem_reg #(
        .p_WORD_LEN      (p_WORD_LEN),
        .p_ADDR_LEN      (3),
        .p_REG_FILE_SIZE (8)
    ) regfile_dut (
        .i_clk       (clk),
        .i_wr_en     (writeEn),
        .i_src1      (src1),
        .i_src2      (src2),
        .i_tgt       (tgt),
        .i_tgt_data  (inp),
        .o_src1_data (out1),
        .o_src2_data (out2)
    );

    // --------------------------------------------------------
    //  Reference model (SystemVerilog class)
    // --------------------------------------------------------
    regfile reference;

    // --------------------------------------------------------
    //  Functional coverage (simple, but illustrates usage)
    // --------------------------------------------------------
    covergroup cg_rf @(posedge clk);
        // cover all src/dst permutations
        src1_c : coverpoint src1;
        src2_c : coverpoint src2;
        tgt_c  : coverpoint tgt  iff (writeEn);

        // overlap situations
        same_src1_tgt : coverpoint (tgt == src1) iff (writeEn);
        same_src2_tgt : coverpoint (tgt == src2) iff (writeEn);
    endgroup : cg_rf

    cg_rf cg_inst = new();

    // --------------------------------------------------------
    //  Drive / sample interface using a clocking block
    // --------------------------------------------------------
    clocking cb @(posedge clk);
        default input  #1step output #0;
        output src1, src2, tgt, inp, writeEn;
        input  out1, out2;
    endclocking

    // --------------------------------------------------------
    //  Clock generation (100 MHz equivalent)
    // --------------------------------------------------------
    always #5 clk = ~clk;

    // --------------------------------------------------------
    //  Test sequence
    // --------------------------------------------------------
    initial begin
        $display("[TB] Starting register-file random test …");

        // VCD setup
        $dumpfile("mem_reg_tb.vcd");
        $dumpvars(0, mem_reg_test);

        // Instantiate reference model
        reference = new();

        // Random seed display
        $display("Random seed = %0d", $get_initial_random_seed());

        // Main stimulus loop
        repeat (p_MAX_TESTS) begin
            // randomize with in-line constraints (tgt 0 rarely written)
            void'(std::randomize(src1, src2, tgt, inp, writeEn)
                 with { src1 inside {[0:7]};
                        src2 inside {[0:7]};
                        tgt  inside {[0:7]};
                        // discourage writes to r0 so we still test it but less often
                        (writeEn == 0) || (tgt != 0);
                 });

            // drive now, sample next posedge via clocking block
            cb.src1    <= src1;
            cb.src2    <= src2;
            cb.tgt     <= tgt;
            cb.inp     <= inp;
            cb.writeEn <= writeEn;

            // Immediate checks (same cycle) — read data stable async
            assert (reference.read_reg(src1) === out1)
                else $fatal("Src1 mismatch at time %0t", $time);
            assert (reference.read_reg(src2) === out2)
                else $fatal("Src2 mismatch at time %0t", $time);
            assert (^out1 !== 1'bx && ^out2 !== 1'bx) else $fatal("Indeterminate X on outputs");

            // Wait for next clock edge (updates scoreboard)
            @(cb);

            // Update reference model after clock writes
            if (writeEn)
                reference.write_reg(tgt, inp);
        end

        // Coverage report
        $display("Functional coverage: %.2f%%", cg_inst.get_coverage());
        $display("[TB] Completed successfully.");
        $finish;
    end

endmodule

`endif // MEM_REG_TEST