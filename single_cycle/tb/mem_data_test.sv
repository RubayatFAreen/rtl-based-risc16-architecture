`ifndef MEM_DATA_TEST
`define MEM_DATA_TEST

`include "mem_data.v"
`include "mem_data_ref.svh"   // class datamem #(SIZE) with read_mem / write_mem

module mem_data_test;

    // --------------------------------------------------------
    //  Parameters
    // --------------------------------------------------------
    localparam int p_ADDR_LEN  = 10;
    localparam int p_WORD_LEN  = 16;
    localparam int p_MEM_SIZE  = 1 << p_ADDR_LEN;
    localparam int p_MAX_TESTS = 100_000;

    // --------------------------------------------------------
    //  DUT I/O
    // --------------------------------------------------------
    bit                          clk = 0;
    bit                          writeEn;
    bit  [p_ADDR_LEN-1:0]        address;
    bit  [p_WORD_LEN-1:0]        dataIn;
    wire [p_WORD_LEN-1:0]        dataOut;

    mem_data #(
        .p_WORD_LEN (p_WORD_LEN),
        .p_ADDR_LEN (p_ADDR_LEN)
    ) datamem_dut (
        .i_clk     (clk),
        .i_wr_en   (writeEn),
        .i_addr    (address),
        .o_rd_data (dataOut),
        .i_wr_data (dataIn)
    );

    // --------------------------------------------------------
    //  Reference model
    // --------------------------------------------------------
    datamem #(p_MEM_SIZE) reference;

    // --------------------------------------------------------
    //  Functional coverage — make sure entire address space hit
    // --------------------------------------------------------
    covergroup cg_mem @(posedge clk);
        address_cvg : coverpoint address {
            bins all_addr[] = {[0 : p_MEM_SIZE-1]};
        }
        rw_cross : cross address_cvg, writeEn;
    endgroup

    cg_mem cg_inst = new();

    // --------------------------------------------------------
    //  Clocking block for race-free drive/sample
    // --------------------------------------------------------
    clocking cb @(posedge clk);
        default output #0 input #1step; // outputs drive immediately, inputs sampled after delta
        output address, dataIn, writeEn;
        input  dataOut;
    endclocking

    // --------------------------------------------------------
    //  100 MHz clock (~10 ns period)
    // --------------------------------------------------------
    always #5 clk = ~clk;

    // --------------------------------------------------------
    //  Test sequence
    // --------------------------------------------------------
    initial begin
        $display("[TB] Starting data memory test…");
        $dumpfile("mem_data_tb.vcd");
        $dumpvars(0, mem_data_test);

        reference = new();

        // Stimulus loop
        repeat (p_MAX_TESTS) begin
            // Randomize with constraint (address in range)
            void'(std::randomize(address, dataIn, writeEn)
                with { address inside {[0 : p_MEM_SIZE-1]}; });

            // Drive DUT via clocking block (nonblocking assignment)
            cb.address  <= address;
            cb.dataIn   <= dataIn;
            cb.writeEn  <= writeEn;

            // Wait one clock so write can take effect before read check
            @(cb);

            // Compare DUT read with reference model
            assert (reference.read_mem(address) === dataOut)
                else $fatal("Read mismatch at %0t addr %0d: DUT=%h REF=%h", $time, address, dataOut, reference.read_mem(address));

            // Update reference model if a write occurred (write-first)
            if (writeEn)
                reference.write_mem(address, dataIn);
        end

        // Coverage report
        $display("Address coverage  : %.2f%%", cg_inst.get_coverage());
        $display("[TB] Data memory test PASS.");
        $finish;
    end

endmodule

`endif // MEM_DATA_TEST
