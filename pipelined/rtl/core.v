`ifndef CORE_V
`define CORE_V

`include "mem_reg.v"
`include "alu.v"

// Everything except the instruction memory
module core (
    // Control signals
    input               i_clk,                  // Main clock signal
    input               i_rst,                  // Global reset (sync)

    // Instruction memory interface
    input  [15:0]       i_inst,                 // Instruction input (combinational read assumed)
    output [15:0]       o_pc_next,              // Program counter to instruction memory

    // Data memory interface
    input  [15:0]       i_mem_rd_data,          // Data read from memory
    output [15:0]       o_mem_wr_data,          // Data to write to memory
    output [15:0]       o_mem_addr,             // Address to write or read
    output              o_mem_wr_en             // Write enable for memory
);

    // ---------------------------
    // Opcode encodings
    // ---------------------------
    localparam ADD  = 3'd0,
               ADDI = 3'd1,
               NAND = 3'd2,
               LUI  = 3'd3,
               SW   = 3'd4,
               LW   = 3'd5,
               BEQ  = 3'd6,
               JALR = 3'd7;

    // ---------------------------
    // Pipeline registers / valids
    // ---------------------------
    logic        r_valid_fetch   = 1'b0;
    logic        r_valid_decode  = 1'b0;
    logic        r_valid_exec    = 1'b0;
    logic        r_valid_mem     = 1'b0;
    logic        r_valid_wb      = 1'b0;

    // PCs per stage (debug & branch base)
    logic [15:0] r_pc_fetch      = 16'h0;
    logic [15:0] r_pc_decode     = 16'h0;
    logic [15:0] r_pc_exec       = 16'h0;
    logic [15:0] r_pc_mem        = 16'h0;    // debug
    logic [15:0] r_pc_wb         = 16'h0;    // debug

    // Instruction/opcodes in flight
    logic [15:0] r_instn_fetch   = 16'h0;
    wire  [2:0]  w_opcode_fetch  = r_instn_fetch[15:13];
    logic [2:0]  r_opcode_decode = 3'd0;
    logic [2:0]  r_opcode_exec   = 3'd0;
    logic [2:0]  r_opcode_mem    = 3'd0;     // debug
    logic [2:0]  r_opcode_wb     = 3'd0;     // debug

    // Register indices per stage
    logic [2:0]  r_src1_decode   = 3'd0;
    logic [2:0]  r_src2_decode   = 3'd0;

    logic [2:0]  r_tgt_decode    = 3'd0;
    logic [2:0]  r_tgt_exec      = 3'd0;
    logic [2:0]  r_tgt_mem       = 3'd0;
    logic [2:0]  r_tgt_wb        = 3'd0;

    // Operands (ID/EX) and immediates
    logic [15:0] r_operand_imm_decode = 16'h0;
    logic [15:0] r_operand_imm_exec   = 16'h0;
    logic [15:0] r_operand1_decode    = 16'h0;
    logic [15:0] r_operand2_decode    = 16'h0;

    // Forwarded operands used by EX selection logic (combinational)
    logic [15:0] r_operand1_fwd;
    logic [15:0] r_operand2_fwd;

    // Store-data captured in EX for SW (forwarded path already applied)
    logic [15:0] r_swdata_exec   = 16'h0;

    // Results along the pipe
    logic [15:0] r_result_alu_exec = 16'h0;
    logic [15:0] r_result_alu_mem  = 16'h0;
    wire  [15:0] w_result_mem;                // mux(ALU, MEM)
    logic [15:0] r_result_wb       = 16'h0;
    logic        r_result_eq_exec  = 1'b0;

    // ---------------------------
    // Stall logic (per-stage origins)
    // ---------------------------
    logic r_stall_fetch = 1'b0;
    logic r_stall_decode= 1'b0;
    logic r_stall_exec  = 1'b0;
    logic r_stall_mem   = 1'b0;   // not used (kept for symmetry)
    logic r_stall_wb    = 1'b0;   // not used (kept for symmetry)

    // Propagated stall (if an earlier stage stalls, upstream stages stall too)
    wire  w_stall_wb     = r_stall_wb;
    wire  w_stall_mem    = r_stall_mem   || w_stall_wb;
    wire  w_stall_exec   = r_stall_exec  || w_stall_mem;
    wire  w_stall_decode = r_stall_decode|| w_stall_exec;
    wire  w_stall_fetch  = r_stall_fetch || w_stall_decode;

    // ---------------------------
    // IF: Program counter & fetch
    // ---------------------------
    logic [15:0] r_pc       = 16'h0;  // architectural next (sequential)
    logic [15:0] r_pc_curr;           // the address we *actually* fetch this cycle

    // Expose address to I-mem
    assign o_pc_next = r_pc_curr;

    // Next PC selection:
    //  - If EX has BEQ: branch resolved here (use r_pc_exec as base)
    //  - Else if ID has JALR: redirect to regB (forwarded)
    //  - Else: sequential r_pc
    always_comb begin
        // default
        r_pc_curr = r_pc;

        // BEQ resolved in EX
        if (r_valid_exec && (r_opcode_exec == BEQ)) begin
            if (r_result_eq_exec)
                r_pc_curr = r_pc_exec + 16'h0001 + r_operand_imm_exec;
            else
                r_pc_curr = r_pc_exec + 16'h0001;
        end
        // JALR resolved in ID (uses forwarded regB value)
        else if (r_valid_decode && (r_opcode_decode == JALR)) begin
            r_pc_curr = r_operand1_fwd;
        end
    end

    // Fetch-stage stall policy:
    //   - Stall IF when current *fetched* opcode is control-flow (prevents
    //     bringing a second wrong-path insn while ID/EX resolves redirect).
    always_comb begin
        r_stall_fetch = 1'b0;
        if (r_valid_fetch && ((w_opcode_fetch == JALR) || (w_opcode_fetch == BEQ)))
            r_stall_fetch = 1'b1;
    end

    // Decode-stage stall policy (hold ID on BEQ until EX resolves)
    always_comb begin
        r_stall_decode = 1'b0;
        if (r_valid_decode && (r_opcode_decode == BEQ))
            r_stall_decode = 1'b1;
    end

    // Execute-stage stall policy (classic LW-use hazard)
    //   EX = LW writing r_tgt_exec, and ID consumes it as src1/src2 → 1-cycle stall
    always_comb begin
        r_stall_exec = 1'b0;
        if (r_valid_exec && r_valid_decode &&
            (r_opcode_exec == LW) &&
            (r_tgt_exec != 3'd0) &&
            ((r_tgt_exec == r_src1_decode) || (r_tgt_exec == r_src2_decode)))
            r_stall_exec = 1'b1;
    end

    // IF pipeline register update (fetch instruction + PC)
    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            r_pc          <= 16'h0000;
            r_pc_fetch    <= 16'h0000;
            r_instn_fetch <= 16'h0000;
            r_valid_fetch <= 1'b0;
        end else begin
            if (w_stall_decode) begin
                // freeze IF (hold everything)
                r_pc          <= r_pc;
                r_pc_fetch    <= r_pc_fetch;
                r_instn_fetch <= r_instn_fetch;
                r_valid_fetch <= r_valid_fetch;
            end else if (r_stall_fetch) begin
                // inject bubble at IF output, keep PC steady
                r_pc          <= r_pc;
                r_pc_fetch    <= r_pc_fetch;
                r_instn_fetch <= 16'h0000;
                r_valid_fetch <= 1'b0;
            end else begin
                // normal fetch
                r_pc          <= r_pc_curr + 16'h0001;
                r_pc_fetch    <= r_pc_curr;
                r_instn_fetch <= i_inst;
                r_valid_fetch <= 1'b1;
            end
        end
    end

    // ---------------------------
    // ID: Decode, register reads
    // ---------------------------
    // Split fetched instruction
    wire [2:0] w_opcode_decode = r_instn_fetch[15:13];
    wire [2:0] w_rega_decode   = r_instn_fetch[12:10];
    wire [2:0] w_regb_decode   = r_instn_fetch[9:7];
    wire [2:0] w_regc_decode   = r_instn_fetch[2:0];
    wire [9:0] w_limm_decode   = r_instn_fetch[9:0];
    wire [6:0] w_simm_decode   = r_instn_fetch[6:0];

    // Immediate expansions
    wire [15:0] w_simm_ext_decode = {{9{w_simm_decode[6]}}, w_simm_decode}; // sign-extend 7 → 16
    wire [15:0] w_limm_ext_decode = {w_limm_decode, 6'b0};                  // imm10 << 6

    // Next decoded addresses/immediate (combinational decode)
    logic [2:0]  r_tgt_next,  r_src1_next, r_src2_next;
    logic [15:0] r_imm_next;

    always_comb begin
        // defaults
        r_tgt_next  = 3'd0;
        r_src1_next = 3'd0;
        r_src2_next = 3'd0;
        r_imm_next  = 16'h0000;

        unique case (w_opcode_decode)
            ADD : begin
                r_tgt_next  = w_rega_decode;
                r_src1_next = w_regb_decode;
                r_src2_next = w_regc_decode;
            end
            ADDI: begin
                r_tgt_next  = w_rega_decode;
                r_src1_next = w_regb_decode;
                r_src2_next = 3'd0;
                r_imm_next  = w_simm_ext_decode;
            end
            NAND: begin
                r_tgt_next  = w_rega_decode;
                r_src1_next = w_regb_decode;
                r_src2_next = w_regc_decode;
            end
            LUI : begin
                r_tgt_next  = w_rega_decode;
                r_src1_next = 3'd0;
                r_src2_next = 3'd0;
                r_imm_next  = w_limm_ext_decode;
            end
            SW  : begin
                r_tgt_next  = 3'd0;
                r_src1_next = w_regb_decode; // base
                r_src2_next = w_rega_decode; // store value
                r_imm_next  = w_simm_ext_decode;
            end
            LW  : begin
                r_tgt_next  = w_rega_decode;
                r_src1_next = w_regb_decode; // base
                r_src2_next = 3'd0;
                r_imm_next  = w_simm_ext_decode;
            end
            BEQ : begin
                r_tgt_next  = 3'd0;
                r_src1_next = w_regb_decode; // compare B vs A (ISA ordering)
                r_src2_next = w_rega_decode;
                r_imm_next  = w_simm_ext_decode;
            end
            JALR: begin
                r_tgt_next  = w_rega_decode; // link reg
                r_src1_next = w_regb_decode; // jump target (regB)
                r_src2_next = 3'd0;
            end
            default: ;
        endcase
    end

    // Register file (async reads, sync write at MEM stage)
    wire [15:0] w_operand1_rd, w_operand2_rd;

    mem_reg regfile_inst (
        .i_clk      (i_clk),
        .i_src1     (r_src1_next),
        .i_src2     (r_src2_next),
        .i_tgt      (r_tgt_mem),        // write in MEM stage
        .o_src1_data(w_operand1_rd),
        .o_src2_data(w_operand2_rd),
        .i_tgt_data (w_result_mem),
        .i_wr_en    (r_valid_mem)       // only when MEM stage holds a valid insn
    );

    // ID pipeline regs
    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            r_valid_decode        <= 1'b0;
            r_pc_decode           <= 16'h0000;
            r_tgt_decode          <= 3'd0;
            r_src1_decode         <= 3'd0;
            r_src2_decode         <= 3'd0;
            r_opcode_decode       <= ADD;
            r_operand1_decode     <= 16'h0000;
            r_operand2_decode     <= 16'h0000;
            r_operand_imm_decode  <= 16'h0000;
        end else if (w_stall_exec) begin
            // hold ID (possible LW-use)
            r_valid_decode        <= r_valid_decode;
            r_pc_decode           <= r_pc_decode;
            r_tgt_decode          <= r_tgt_decode;
            r_src1_decode         <= r_src1_decode;
            r_src2_decode         <= r_src2_decode;
            r_opcode_decode       <= r_opcode_decode;
            // allow late forwarding to refresh operands while stalled
            if ((r_src1_decode != 3'd0) && (r_src1_decode == r_tgt_wb))  r_operand1_decode <= r_result_wb;
            if ((r_src2_decode != 3'd0) && (r_src2_decode == r_tgt_wb))  r_operand2_decode <= r_result_wb;
            r_operand_imm_decode  <= r_operand_imm_decode;
        end else if (r_stall_decode) begin
            // inject bubble into ID/EX boundary
            r_valid_decode        <= 1'b0;
            r_pc_decode           <= r_pc_decode;
            r_tgt_decode          <= 3'd0;
            r_src1_decode         <= 3'd0;
            r_src2_decode         <= 3'd0;
            r_opcode_decode       <= ADD;
            r_operand1_decode     <= 16'h0000;
            r_operand2_decode     <= 16'h0000;
            r_operand_imm_decode  <= 16'h0000;
        end else begin
            // normal advance
            r_valid_decode        <= r_valid_fetch;
            r_pc_decode           <= r_pc_fetch;
            r_tgt_decode          <= r_tgt_next;
            r_src1_decode         <= r_src1_next;
            r_src2_decode         <= r_src2_next;
            r_opcode_decode       <= w_opcode_decode;
            r_operand1_decode     <= w_operand1_rd;
            r_operand2_decode     <= w_operand2_rd;
            r_operand_imm_decode  <= r_imm_next;
        end
    end

    // ---------------------------
    // EX: Forwarding + ALU/compare
    // ---------------------------

    // Forward src1
    always_comb begin
        if (r_src1_decode == 3'd0)
            r_operand1_fwd = 16'h0000;
        else if (r_src1_decode == r_tgt_exec)
            r_operand1_fwd = r_result_alu_exec;
        else if (r_src1_decode == r_tgt_mem)
            r_operand1_fwd = w_result_mem;
        else if (r_src1_decode == r_tgt_wb)
            r_operand1_fwd = r_result_wb;
        else
            r_operand1_fwd = r_operand1_decode;
    end

    // Forward src2
    always_comb begin
        if (r_src2_decode == 3'd0)
            r_operand2_fwd = 16'h0000;
        else if (r_src2_decode == r_tgt_exec)
            r_operand2_fwd = r_result_alu_exec;
        else if (r_src2_decode == r_tgt_mem)
            r_operand2_fwd = w_result_mem;
        else if (r_src2_decode == r_tgt_wb)
            r_operand2_fwd = r_result_wb;
        else
            r_operand2_fwd = r_operand2_decode;
    end

    // ALU operand/op selection
    logic        r_aluop;
    logic [15:0] r_aluina, r_aluinb;

    always_comb begin
        // defaults
        r_aluop  = 1'b0;
        r_aluina = r_operand1_fwd;
        r_aluinb = r_operand2_fwd;

        unique case (r_opcode_decode)
            ADD : begin
                r_aluop  = 1'b0;
                r_aluina = r_operand1_fwd;
                r_aluinb = r_operand2_fwd;
            end
            ADDI: begin
                r_aluop  = 1'b0;
                r_aluina = r_operand1_fwd;
                r_aluinb = r_operand_imm_decode;
            end
            NAND: begin
                r_aluop  = 1'b1;
                r_aluina = r_operand1_fwd;
                r_aluinb = r_operand2_fwd;
            end
            LUI : begin
                r_aluop  = 1'b0;
                r_aluina = r_operand1_fwd;          // don't care; ALU adds zero-based imm path
                r_aluinb = r_operand_imm_decode;
            end
            SW, LW, BEQ: begin
                r_aluop  = 1'b0;
                r_aluina = r_operand1_fwd;
                r_aluinb = (r_opcode_decode == BEQ) ? r_operand2_fwd
                                                    : r_operand_imm_decode; // base+imm for SW/LW
            end
            JALR: begin
                r_aluop  = 1'b0;
                r_aluina = r_pc_decode + 16'h0001;  // link value
                r_aluinb = 16'h0000;
            end
            default: ;
        endcase
    end

    // ALU instance (ADD/NAND + equality compare)
    wire [15:0] w_aluout;
    wire        w_alueq;

    alu alu_inst (
        .i_op  (r_aluop),     // 0 ADD, 1 NAND
        .i_ina (r_aluina),
        .i_inb (r_aluinb),
        .o_out (w_aluout),
        .o_eq  (w_alueq)
    );

    // EX pipeline regs
    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            r_valid_exec       <= 1'b0;
            r_pc_exec          <= 16'h0000;
            r_tgt_exec         <= 3'd0;
            r_opcode_exec      <= 3'd0;
            r_swdata_exec      <= 16'h0000;
            r_result_eq_exec   <= 1'b0;
            r_result_alu_exec  <= 16'h0000;
            r_operand_imm_exec <= 16'h0000;
        end else if (w_stall_mem) begin
            // hold EX (rarely used here; symmetry)
            r_valid_exec       <= r_valid_exec;
            r_pc_exec          <= r_pc_exec;
            r_tgt_exec         <= r_tgt_exec;
            r_opcode_exec      <= r_opcode_exec;
            r_swdata_exec      <= r_swdata_exec;
            r_result_eq_exec   <= r_result_eq_exec;
            r_result_alu_exec  <= r_result_alu_exec;
            r_operand_imm_exec <= r_operand_imm_exec;
        end else if (r_stall_exec) begin
            // inject bubble into EX/MEM boundary
            r_valid_exec       <= 1'b0;
            r_pc_exec          <= r_pc_exec;
            r_tgt_exec         <= 3'd0;
            r_opcode_exec      <= 3'd0;
            r_swdata_exec      <= 16'h0000;
            r_result_eq_exec   <= 1'b0;
            r_result_alu_exec  <= 16'h0000;
            r_operand_imm_exec <= 16'h0000;
        end else begin
            // normal advance
            r_valid_exec       <= r_valid_decode;
            r_pc_exec          <= r_pc_decode;
            r_tgt_exec         <= r_tgt_decode;
            r_opcode_exec      <= r_opcode_decode;
            r_swdata_exec      <= r_operand2_fwd;   // store data (already forwarded)
            r_result_eq_exec   <= w_alueq;
            r_result_alu_exec  <= w_aluout;
            r_operand_imm_exec <= r_operand_imm_decode;
        end
    end

    // ---------------------------
    // MEM: Data memory access
    // ---------------------------
    assign o_mem_addr    = r_result_alu_exec;     // base + imm computed in EX
    assign o_mem_wr_data = r_swdata_exec;
    assign o_mem_wr_en   = r_valid_exec && (r_opcode_exec == SW); // gate with valid

    // MEM pipeline regs
    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            r_valid_mem      <= 1'b0;
            r_pc_mem         <= 16'h0000;
            r_opcode_mem     <= 3'd0;
            r_tgt_mem        <= 3'd0;
            r_result_alu_mem <= 16'h0000;
        end else if (w_stall_wb) begin
            // hold MEM
            r_valid_mem      <= r_valid_mem;
            r_pc_mem         <= r_pc_mem;
            r_opcode_mem     <= r_opcode_mem;
            r_tgt_mem        <= r_tgt_mem;
            r_result_alu_mem <= r_result_alu_mem;
        end else if (r_stall_mem) begin
            // inject bubble (not used; symmetry)
            r_valid_mem      <= 1'b0;
            r_pc_mem         <= r_pc_mem;
            r_opcode_mem     <= r_opcode_mem;
            r_tgt_mem        <= 3'd0;
            r_result_alu_mem <= 16'h0000;
        end else begin
            // normal advance
            r_valid_mem      <= r_valid_exec;
            r_pc_mem         <= r_pc_exec;
            r_opcode_mem     <= r_opcode_exec;
            r_tgt_mem        <= r_tgt_exec;
            r_result_alu_mem <= r_result_alu_exec;
        end
    end

    // Result after MEM (load vs pass-through)
    assign w_result_mem = (r_opcode_mem == LW) ? i_mem_rd_data
                                               : r_result_alu_mem;

    // ---------------------------
    // WB: Write-back into regfile
    // ---------------------------
    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            r_valid_wb  <= 1'b0;
            r_pc_wb     <= 16'h0000;
            r_opcode_wb <= 3'd0;
            r_tgt_wb    <= 3'd0;
            r_result_wb <= 16'h0000;
        end else if (r_stall_wb) begin
            // inject bubble (not used; symmetry)
            r_valid_wb  <= 1'b0;
            r_pc_wb     <= r_pc_wb;
            r_opcode_wb <= r_opcode_wb;
            r_tgt_wb    <= 3'd0;
            r_result_wb <= 16'h0000;
        end else begin
            // move along (note: actual regfile write happens in MEM stage)
            r_valid_wb  <= r_valid_mem;
            r_pc_wb     <= r_pc_mem;
            r_opcode_wb <= r_opcode_mem;
            r_tgt_wb    <= r_tgt_mem;
            r_result_wb <= w_result_mem;
        end
    end

// ---------------------------
// (Optional) lightweight formal
// ---------------------------
`ifdef FORMAL
    // Simple pipeline-flow sanity:
    //  - bubbles advance
    //  - LW-use creates a bubble in EX
    logic f_past_valid = 1'b0;
    always_ff @(posedge i_clk) begin
        if (f_past_valid) begin
            if ($past(r_valid_exec && (r_opcode_exec == LW) &&
                      (r_tgt_exec != 0) &&
                      ( (r_tgt_exec == r_src1_decode) || (r_tgt_exec == r_src2_decode) )))
                assert(!r_valid_exec); // bubble inserted
        end
        f_past_valid <= 1'b1;
    end
`endif

endmodule

`endif // CORE_V
