`ifndef CORE_V
`define CORE_V
`include "mem_reg.v"      // 8-register file used below

module core (
    // --------- Global control --------------------------------
    input               i_clk,          // system clock
    input               i_rst,          // synchronous reset

    // --------- Instruction-memory interface ------------------
    input  [15:0]       i_inst,         // current instruction word
    output reg [15:0]   o_pc,           // program-counter (address out)

    // --------- Data-memory interface -------------------------
    input  [15:0]       i_mem_rd_data,  // data read (async)
    output reg [15:0]   o_mem_wr_data,  // data to write
    output reg [15:0]   o_mem_addr,     // address for R/W
    output reg          o_mem_wr_en     // write-enable
);
    // ---------------------------------------------------------
    //  PC initialisation (for simulation reset)
    // ---------------------------------------------------------
    initial o_pc = 16'h0000;

    // ---------------------------------------------------------
    //  Register-file wires
    // ---------------------------------------------------------
    wire [15:0] w_reg1_out;
    wire [15:0] w_reg2_out;
    reg  [15:0] r_tgt_in    = 16'h0000; // value to write back

    // 3-bit register indices
    reg  [2:0]  r_reg1_addr = 3'b000;
    reg  [2:0]  r_reg2_addr = 3'b000;
    reg  [2:0]  r_tgt_addr  = 3'b000;

    reg         r_tgt_wr_en = 1'b0;

    // ---------------------------------------------------------
    //  Register file instance
    // ---------------------------------------------------------
    mem_reg #(
        .p_WORD_LEN     (16),
        .p_REG_ADDR_LEN (3),
        .p_REG_FILE_SIZE(8)
    ) regfile (
        .i_clk     (i_clk),

        .i_src1    (r_reg1_addr),
        .i_src2    (r_reg2_addr),
        .i_tgt     (r_tgt_addr),

        .o_src1_data(w_reg1_out),
        .o_src2_data(w_reg2_out),
        .i_tgt_data(r_tgt_in),

        .i_wr_en   (r_tgt_wr_en)
    );

    // ---------------------------------------------------------
    //  Instruction decode fields
    // ---------------------------------------------------------
    wire [2:0] opcode   = i_inst[15:13]; // 3-bit major opcode

    localparam ADD  = 0,
               ADDI = 1,
               NAND = 2,
               LUI  = 3,
               SW   = 4,
               LW   = 5,
               BEQ  = 6,
               JALR = 7;

    // Register specifiers inside instruction word
    wire [2:0] w_rega = i_inst[12:10];
    wire [2:0] w_regb = i_inst[9:7];
    wire [2:0] w_regc = i_inst[2:0];

    // Immediate fields
    wire [9:0]  w_long_imm   = i_inst[9:0];      // 10-bit for LUI
    wire [6:0]  w_sign_imm   = i_inst[6:0];      // 7-bit for RRI
    wire [15:0] w_sign_imm_ext = {{9{w_sign_imm[6]}}, w_sign_imm}; // sign-extend to 16

    // ---------------------------------------------------------
    //  Register-address generation (combinational)
    // ---------------------------------------------------------
    always @(*) begin
        case (opcode)
            ADD  : begin
                r_tgt_addr  = w_rega;
                r_reg1_addr = w_regb;
                r_reg2_addr = w_regc;
            end
            ADDI : begin
                r_tgt_addr  = w_rega;
                r_reg1_addr = w_regb;
                r_reg2_addr = 3'b000;      // unused
            end
            NAND : begin
                r_tgt_addr  = w_rega;
                r_reg1_addr = w_regb;
                r_reg2_addr = w_regc;
            end
            LUI  : begin
                r_tgt_addr  = w_rega;
                r_reg1_addr = 3'b000;
                r_reg2_addr = 3'b000;
            end
            SW   : begin
                r_tgt_addr  = 3'b000;      // no RF write
                r_reg1_addr = w_rega;      // store value
                r_reg2_addr = w_regb;      // base address
            end
            LW   : begin
                r_tgt_addr  = w_rega;
                r_reg1_addr = w_regb;      // base
                r_reg2_addr = 3'b000;
            end
            BEQ  : begin
                r_tgt_addr  = 3'b000;
                r_reg1_addr = w_rega;
                r_reg2_addr = w_regb;
            end
            JALR : begin
                r_tgt_addr  = w_rega;
                r_reg1_addr = w_regb;      // jump target
                r_reg2_addr = 3'b000;
            end
        endcase
    end

    // ---------------------------------------------------------
    //  Datapath + memory control (combinational)
    // ---------------------------------------------------------
    always @(*) begin
        case (opcode)
            // ------------ ALU register-to-register -------------
            ADD : begin
                r_tgt_in    = w_reg1_out + w_reg2_out;
                r_tgt_wr_en = 1'b1;

                o_mem_wr_en   = 1'b0;
                o_mem_addr    = 16'h0000;
                o_mem_wr_data = 16'h0000;
            end
            ADDI: begin
                r_tgt_in    = w_reg1_out + w_sign_imm_ext;
                r_tgt_wr_en = 1'b1;

                o_mem_wr_en   = 1'b0;
                o_mem_addr    = 16'h0000;
                o_mem_wr_data = 16'h0000;
            end
            NAND: begin
                r_tgt_in    = ~(w_reg1_out & w_reg2_out);
                r_tgt_wr_en = 1'b1;

                o_mem_wr_en   = 1'b0;
                o_mem_addr    = 16'h0000;
                o_mem_wr_data = 16'h0000;
            end
            LUI : begin
                r_tgt_in    = {w_long_imm, 6'b0}; // imm << 6
                r_tgt_wr_en = 1'b1;

                o_mem_wr_en   = 1'b0;
                o_mem_addr    = 16'h0000;
                o_mem_wr_data = 16'h0000;
            end
            // ------------- Store word --------------------------
            SW  : begin
                r_tgt_in    = 16'h0000;   // no RF write
                r_tgt_wr_en = 1'b0;

                o_mem_wr_en   = 1'b1;
                o_mem_addr    = w_reg2_out + w_sign_imm_ext;
                o_mem_wr_data = w_reg1_out;
            end
            // ------------- Load word ---------------------------
            LW  : begin
                o_mem_addr    = w_reg1_out + w_sign_imm_ext;
                r_tgt_in      = i_mem_rd_data;     // load to reg
                r_tgt_wr_en   = 1'b1;

                o_mem_wr_en   = 1'b0;
                o_mem_wr_data = 16'h0000;
            end
            // ------------- Branch equal ------------------------
            BEQ : begin
                r_tgt_in    = 16'h0000;
                r_tgt_wr_en = 1'b0;

                o_mem_wr_en   = 1'b0;
                o_mem_addr    = 16'h0000;
                o_mem_wr_data = 16'h0000;
            end
            // ------------- Jump and link register --------------
            JALR: begin
                r_tgt_in    = o_pc + 16'h0001; // link
                r_tgt_wr_en = 1'b1;

                o_mem_wr_en   = 1'b0;
                o_mem_addr    = 16'h0000;
                o_mem_wr_data = 16'h0000;
            end
        endcase
    end

    // ---------------------------------------------------------
    //  Program-counter update (sequential)
    // ---------------------------------------------------------
    always @(posedge i_clk) begin
        if (i_rst)
            o_pc <= 16'h0000;                       // reset vector
        else
            case (opcode)
                ADD, ADDI, NAND, LUI, SW, LW: begin
                    o_pc <= o_pc + 16'h0001;        // sequential
                end
                BEQ: begin
                    if (w_reg1_out == w_reg2_out)
                        o_pc <= o_pc + 16'h0001 + w_sign_imm_ext; // branch taken
                    else
                        o_pc <= o_pc + 16'h0001;    // fall-through
                end
                JALR: begin
                    o_pc <= w_reg1_out;             // jump target
                end
            endcase
    end

endmodule
`endif
