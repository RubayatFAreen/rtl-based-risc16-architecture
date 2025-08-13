`ifndef CORE_TEST_SV
`define CORE_TEST_SV

`include "simulator.svh"
`include "instruction.svh"

`include "core.v"
`include "mem_data.v"

// -----------------------------
// Test the processor core
// -----------------------------
module core_test;

    // Configuration
    localparam int p_INST_COUNT        = 100_000;
    localparam int p_DATA_ADDR_LEN     = 10;
    localparam int p_DATA_COUNT        = 2 ** p_DATA_ADDR_LEN;
    localparam bit p_LOG_TRACE         = 0;   // high-level trace
    localparam bit p_LOG_TRACE_DETAILED= 0;   // pipeline internals

    // Instruction objects and windows
    instruction inst;           // freshly randomized instruction
    instruction inst2;          // copy pushed into window/history
    instruction inst_window[$]; // pending to be “committed” by sim
    instruction inst_hist[$];   // history for debugging
    int         pc_pointer = 0; // (reserved for future use)

    // DUT interface
    logic        clk = 0;
    logic        rst = 0;
    logic [15:0] inst_reg;
    wire  [15:0] pc;

    // Data memory wires
    wire [15:0] w_rd_data, w_wr_data, w_addr;
    wire        w_wr_en;

    // Register previous address for clean async-read gating
    logic [15:0] r_addr_prev;

    // Event to coordinate TB phases within a cycle
    event update_evt;

    // 100 MHz clock
    always #5 clk = ~clk;

    // Address register for OOB gating of read data
    always_ff @(posedge clk)
        r_addr_prev <= w_addr;

    // -----------------------------
    //  Device Under Test (core)
    // -----------------------------
    core core_dut (
        .i_clk        (clk),
        .i_rst        (rst),

        .i_inst       (inst_reg),
        .o_pc_next    (pc),

        .i_mem_rd_data((r_addr_prev < p_DATA_COUNT) ? w_rd_data : 16'h0000),
        .o_mem_wr_data(w_wr_data),
        .o_mem_addr   (w_addr),
        .o_mem_wr_en  (w_wr_en)
    );

    // -----------------------------
    //  Data memory
    // -----------------------------
    mem_data #(
        .p_WORD_LEN(16),
        .p_ADDR_LEN(p_DATA_ADDR_LEN)
    ) datamem (
        .i_clk     (clk),
        .i_wr_en   (w_wr_en && (w_addr < p_DATA_COUNT)),
        .i_addr    (w_addr),
        .o_rd_data (w_rd_data),
        .i_wr_data (w_wr_data)
    );

    // -----------------------------
    //  Golden reference model
    // -----------------------------
    simulator #(
        .INSTRUCTION_COUNT(p_INST_COUNT),
        .DATA_COUNT      (p_DATA_COUNT)
    ) sim;

    // Misc
    string temp;
    int    fail_count = 0;

    // ---------------------------------
    // Main test sequence
    // ---------------------------------
    initial begin
        $display("[TB] Starting core processor test");
        $display("[TB] Random seed: %0d", $get_initial_random_seed());

        // Dumpfile
        $dumpfile("core_pipe_tb.vcd");
        $dumpvars(0, core_test);

        // Init classes
        sim  = new();
        inst = new();

        // Synchronous reset pulse
        rst = 1;
        @(negedge clk);
        rst = 0;

        // Main instruction loop
        for (int i = 0; i < p_INST_COUNT; i++) begin
            if (i % (p_INST_COUNT/10) == 0)
                $display("%0d instructions completed", i);

            // Drain bubbles until WB is valid (i.e., a commit happened)
            do @(negedge clk); while (~core_dut.r_valid_wb);

            // Let the negedge printer run and the issuance logic push to window
            @(update_evt);

            // Optionally show instruction window
            if (p_LOG_TRACE_DETAILED) begin
                $display("Instruction window:");
                foreach (inst_window[j]) $display("  %s", inst_window[j].to_string());
                $display();
            end

            // Pop the oldest instruction from the window and execute in SIM
            sim.set_inst(inst_window.pop_front());
            sim.exec_inst();

            // Verify architectural state at commit
            if (~verify_status()) break;
        end

        $display("Number of failures       : %0d", fail_count);
        $display("Instruction coverage     : %s", inst.get_coverage());
        $display("[TB] Finished core processor test");
        $finish;
    end

    // ---------------------------------
    // Trace + instruction issuance
    // ---------------------------------
    bit disp_detailed = 0;

    always @(negedge clk) begin
        // Pretty prints for debugging
        disp_detailed = 0;
        if (p_LOG_TRACE) begin
            $display("----------------------------------------------------");
            $display("time: %0t", $time);
            $display("dut : %s", dut_to_string());
            // Example peek into data memory (hierarchical) — address 33
            $display("mem[33] : %4h", datamem.r_memory[33]);

            if (p_LOG_TRACE_DETAILED || disp_detailed)
                $display("%s", dut_to_string_detailed());
        end

        // Issue a new instruction if fetch is not stalled
        if (~core_dut.w_stall_fetch) begin
            generate_inst();                   // randomize + queue a copy
            inst_reg = inst.to_bin();          // drive to core fetch

            if (p_LOG_TRACE)
                $display("Issuing: %s", inst.to_string());
        end else if (p_LOG_TRACE) begin
            $display("Fetch stalled!");
        end

        if (p_LOG_TRACE) $display();

        -> update_evt; // signal the main thread
    end

    // ---------------------------------
    // Randomize an instruction and push a **copy** into window/history
    // ---------------------------------
    function void generate_inst();
        // Randomize with internal constraints + sample coverage
        assert(inst.randomize()) else $fatal("Randomization failed");
        inst.cg.sample();

        // Make a frozen copy (encode→decode to prevent later mutation)
        inst2 = new();
        inst2.from_bin(inst.to_bin());

        inst_window.push_back(inst2);
        inst_hist.push_back(inst2);
    endfunction

    // ---------------------------------
    // Compare DUT (at commit) vs simulator
    // ---------------------------------
    function bit verify_status();
        bit failed = 0;

        // Compare program counter at commit
        // If your simulator exposes `program_counter_prev` instead, swap below.
        assert(core_dut.r_pc_wb === sim.program_counter) else begin
            fail_count++; failed = 1;
        end

        // Compare register file (skip r0)
        for (int i = 1; i < 8; i++) begin
            assert(sim.registers.read_reg(i) === core_dut.regfile_inst.r_memory[i]) else begin
                fail_count++; failed = 1;
            end
        end

        // Debug prints on failure (or when trace is enabled)
        if (failed || p_LOG_TRACE) begin
            if (failed) $display("Verification FAILED!");
            $display("dut : %s", dut_to_string());
            $display("sim : %s", sim.to_string());
            if (failed) $display("%s", dut_to_string_detailed());

            if (sim.inst.opcode == LW) begin
                $display(sim.data_mem.write_hist);
                $display(sim.data_mem.write_data_hist);
            end

            if (failed) begin
                int start = (inst_hist.size() > 50) ? inst_hist.size()-50 : 0;
                for (int k = start; k < inst_hist.size(); k++)
                    $display("%0d : %s", k, inst_hist[k].to_string());
            end
            $display();
        end

        return ~failed;
    endfunction

    // ---------------------------------
    // Short DUT state line (PC + regs)
    // ---------------------------------
    function string dut_to_string();
        automatic string s = "";
        s = $sformatf("%4h : %-17s : ", core_dut.r_pc_wb, inst.to_string());
        for (int i = 0; i < 8; i++)
            s = $sformatf("%s r%0d-%h", s, i, core_dut.regfile_inst.r_memory[i]);
        return s;
    endfunction

    // ---------------------------------
    // Detailed pipeline snapshot (one line per group)
    // ---------------------------------
    function string dut_to_string_detailed();
        automatic string t = "";
        t = $sformatf("%sStall origins     : %4d %4d %4d %4d %4d \n", t,
                      core_dut.r_stall_fetch, core_dut.r_stall_decode, core_dut.r_stall_exec, core_dut.r_stall_mem, core_dut.r_stall_wb);
        t = $sformatf("%sStalled           : %4d %4d %4d %4d %4d \n", t,
                      core_dut.w_stall_fetch, core_dut.w_stall_decode, core_dut.w_stall_exec, core_dut.w_stall_mem, core_dut.w_stall_wb);
        t = $sformatf("%sValid             : %4d %4d %4d %4d %4d \n", t,
                      core_dut.r_valid_fetch, core_dut.r_valid_decode, core_dut.r_valid_exec, core_dut.r_valid_mem, core_dut.r_valid_wb);
        t = $sformatf("%sProgram counters  : %4h %4h %4h %4h %4h \n", t,
                      core_dut.r_pc_fetch, core_dut.r_pc_decode, core_dut.r_pc_exec, core_dut.r_pc_mem, core_dut.r_pc_wb);
        t = $sformatf("%sOpcodes           : ", t);
        t = $sformatf("%s%4s %4s %4s %4s %4s\n", t,
                      opcode_to_string(core_dut.w_opcode_fetch),
                      opcode_to_string(core_dut.r_opcode_decode),
                      opcode_to_string(core_dut.r_opcode_exec),
                      opcode_to_string(core_dut.r_opcode_mem),
                      opcode_to_string(core_dut.r_opcode_wb));
        t = $sformatf("%sResults           : %4s %4s %4h %4h %4h\n", t, "",
                      "", core_dut.r_result_alu_exec, core_dut.w_result_mem, core_dut.r_result_wb);
        t = $sformatf("%sTarget            : %4s %4d %4d %4d %4d\n", t, "",
                      core_dut.r_tgt_decode, core_dut.r_tgt_exec, core_dut.r_tgt_mem, core_dut.r_tgt_wb);
        t = $sformatf("%sDecode stage output : op1 %4h, op2 %4h, src1 %1d, src2 %1d, op_imm %4h\n", t,
                      core_dut.r_operand1_decode, core_dut.r_operand2_decode,
                      core_dut.r_src1_decode, core_dut.r_src2_decode, core_dut.r_operand_imm_decode);
        t = $sformatf("%sExecute stage input : op1 %4h, op2 %4h, aluina %4h, aluinb %4h, aluop %1d\n", t,
                      core_dut.r_operand1_fwd, core_dut.r_operand2_fwd,
                      core_dut.r_aluina, core_dut.r_aluinb, core_dut.r_aluop);
        t = $sformatf("%sMemory : addr %4h datain %4h wren %1d dataout %4h", t,
                      w_addr, w_rd_data, w_wr_en && (w_addr < p_DATA_COUNT), w_wr_data);
        return t;
    endfunction

    // ---------------------------------
    // Human-readable opcode
    // ---------------------------------
    function string opcode_to_string(bit [2:0] inp);
        case (inp)
            3'd0: return "ADD";
            3'd1: return "ADDI";
            3'd2: return "NAND";
            3'd3: return "LUI";
            3'd4: return "SW";
            3'd5: return "LW";
            3'd6: return "BEQ";
            3'd7: return "JALR";
            default: return "??";
        endcase
    endfunction

endmodule

`endif // CORE_TEST_SV
