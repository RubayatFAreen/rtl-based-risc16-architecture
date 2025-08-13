`ifndef CORE_TEST_SV
`define CORE_TEST_SV

`include "simulator.svh"       // class simulator
`include "instruction.svh"     // class instruction (randomizable)

`include "core.v"
`include "mem_data.v"

module core_test;

    // --------------------------------------------------------
    //  Configuration parameters
    // --------------------------------------------------------
    localparam int p_INST_COUNT     = 100_000;
    localparam int p_DATA_ADDR_LEN  = 10;
    localparam int p_DATA_COUNT     = 1 << p_DATA_ADDR_LEN;
    localparam bit p_LOG_TRACE      = 0;

    // --------------------------------------------------------
    //  DUT interface signals
    // --------------------------------------------------------
    bit                  clk = 0;
    bit                  rst = 0;
    bit [15:0]           inst_reg;
    wire [15:0]          pc;

    wire [15:0] w_rd_data, w_wr_data, w_addr;
    wire        w_wr_en;

    // --------------------------------------------------------
    //  Device Under Test
    // --------------------------------------------------------
    core core_dut (
        .i_clk          (clk),
        .i_rst          (rst),
        .i_inst         (inst_reg),
        .o_pc           (pc),
        .i_mem_rd_data  ( (w_addr < p_DATA_COUNT) ? w_rd_data : 16'h0 ),
        .o_mem_wr_data  (w_wr_data),
        .o_mem_addr     (w_addr),
        .o_mem_wr_en    (w_wr_en)
    );

    mem_data #(
        .p_WORD_LEN (16),
        .p_ADDR_LEN (p_DATA_ADDR_LEN)
    ) datamem (
        .i_clk      (clk),
        .i_wr_en    (w_wr_en && (w_addr < p_DATA_COUNT)),
        .i_addr     (w_addr),
        .o_rd_data  (w_rd_data),
        .i_wr_data  (w_wr_data)
    );

    // --------------------------------------------------------
    //  Reference model and instruction generator
    // --------------------------------------------------------
    simulator   #( .INSTRUCTION_COUNT(p_INST_COUNT), .DATA_COUNT(p_DATA_COUNT) ) sim;
    instruction inst;

    // Fail counter & helpers
    int fail_count = 0;

    // --------------------------------------------------------
    //  Clock generator (100 MHz)
    // --------------------------------------------------------
    always #5 clk = ~clk;

    // --------------------------------------------------------
    //  Main test process
    // --------------------------------------------------------
    initial begin
        $display("[TB] Starting core test …");
        $dumpfile("core_tb.vcd");
        $dumpvars(0, core_test);

        sim  = new();
        inst = new();
        rst  = 0;   // core currently synchronous; keep low
        #1;

        for (int i = 0; i < p_INST_COUNT; i++) begin
            // Randomize instruction and sample coverage inside instruction class
            assert (inst.randomize()) else $fatal("Randomize failed");
            inst.cg.sample();

            // Drive instruction to DUT and ref‑model
            inst_reg = inst.to_bin();
            sim.set_inst(inst);

            // Optional waveform trace
            if (p_LOG_TRACE) begin
                $display("sim : %s", sim.to_string());
                $display("dut : %s", dut_to_string());
            end
            if (i % (p_INST_COUNT/10) == 0) $display("%0d instr executed", i);

            // Execute reference model step (combinational)
            sim.exec_inst();

            // One clock for DUT
            @(negedge clk);

            // Compare states; break on first mismatch
            if (!verify_status()) break;
        end

        $display("Failures   : %0d", fail_count);
        $display("Instr cov  : %.2f%%", inst.get_coverage());
        $display("[TB] Core test finished.");
        $finish;
    end

    // --------------------------------------------------------
    //  Status verification helper
    // --------------------------------------------------------
    function bit verify_status();
        bit failed = 0;

        // Compare PC
        assert (pc === sim.program_counter) else begin
            failed = 1; fail_count++;
        end

        // Compare registers (skip r0)
        for (int idx = 1; idx < 8; idx++) begin
            assert (sim.registers.read_reg(idx) === core_dut.regfile.reg_file[idx]) else begin
                failed = 1; fail_count++;
            end
        end

        if (failed) begin
            $display("Mismatch detected at cycle %0t", $time);
            $display("dut : %s", dut_to_string());
            $display("sim : %s", sim.to_string());
        end
        return !failed;
    endfunction

    // --------------------------------------------------------
    //  Pretty‑print DUT register state
    // --------------------------------------------------------
    function string dut_to_string();
        string s;
        s = $sformatf("PC=%04h | ", pc);
        for (int idx = 0; idx < 8; idx++)
            s = $sformatf("%s r%0d=%04h", s, idx, core_dut.regfile.reg_file[idx]);
        return s;
    endfunction

endmodule

`endif // CORE_TEST_SV
