`ifndef INSTRUCTION_SVH
`define INSTRUCTION_SVH

// -----------------------------
// Opcode enumeration (3 bits)
// -----------------------------
typedef enum logic [2:0] {
    ADD  = 3'd0,
    ADDI = 3'd1,
    NAND = 3'd2,
    LUI  = 3'd3,
    SW   = 3'd4,
    LW   = 3'd5,
    BEQ  = 3'd6,
    JALR = 3'd7
} opcode_t;

// ---------------------------------
// Instruction format enumeration
// ---------------------------------
typedef enum logic [1:0] {
    RRR = 2'd0,   // reg, reg, reg
    RRI = 2'd1,   // reg, reg, imm7 (signed)
    RI  = 2'd2    // reg, imm10 (unsigned)
} opcode_format_t;

// 3-bit register field (0..7) — name preserved intentionally
typedef logic [2:0] regflield_t;

// ---------------------------------
// Instruction class definition
// ---------------------------------
class instruction;

  // -------- Randomized fields (names preserved) ----------
  rand opcode_t     opcode;          // operation code
  rand regflield_t  rega;            // destination / first source
  rand regflield_t  regb;            // source B
  rand regflield_t  regc;            // source C (RRR only)
  rand int          imm;             // immediate (signed int for convenience)

  // -------- Format lookup table (by opcode) --------------
  //     (name preserved as format_lookup)
  static const opcode_format_t format_lookup[opcode_t] = '{
    ADD  : RRR,
    ADDI : RRI,
    NAND : RRR,
    LUI  : RI,
    SW   : RRI,
    LW   : RRI,
    BEQ  : RRI,
    JALR : RRI
  };

  // -------- Immediate constraints ------------------------
  //  • RRI: −64..+63; for JALR force imm==0
  //  • RI : 0..1023 (unsigned 10-bit)
  //  • RRR: no immediate → imm==0
  constraint imm_limit {
    solve opcode before imm;

    if (format_lookup[opcode] == RRI) {
      if (opcode == JALR) imm == 0;
      else imm dist { 0 := 10, -64 := 5, 63 := 5, [-63:-1] :/ 40, [1:62] :/ 40 };
    }
    else if (format_lookup[opcode] == RI) {
      imm dist { 0 := 10, 1023 := 10, [1:1022] :/ 80 };
    }
    else { // RRR
      imm == 0;
    }
  }

  // -------- Functional coverage --------------------------
  covergroup cg;
    // Opcode coverage per format
    RRR_opcode_cover: coverpoint opcode iff (format_lookup[opcode] == RRR) {
      bins ADD  = {ADD};
      bins NAND = {NAND};
    }

    RRI_opcode_cover: coverpoint opcode iff (format_lookup[opcode] == RRI) {
      bins ADDI = {ADDI};
      bins SW   = {SW};
      bins LW   = {LW};
      bins BEQ  = {BEQ};
      bins JALR = {JALR};
    }

    RI_opcode_cover: coverpoint opcode iff (format_lookup[opcode] == RI) {
      bins LUI = {LUI};
    }

    // Register fields
    rega_cover: coverpoint rega;
    regb_cover: coverpoint regb iff (format_lookup[opcode] != RI);
    regc_cover: coverpoint regc iff (format_lookup[opcode] == RRR);

    // Immediates
    sig_imm : coverpoint imm iff (format_lookup[opcode] == RRI) {
      bins zero = {0};
      bins min  = {-64};
      bins max  = {63};
      bins pos  = {[1:63]};
      bins neg  = {[-63:-1]};
    }

    long_imm: coverpoint imm iff (format_lookup[opcode] == RI) {
      bins zero = {0};
      bins max  = {1023};
      bins vals[5] = {[1:1022]};
    }

    // Crosses
    RRR_cover : cross RRR_opcode_cover, rega_cover, regb_cover, regc_cover;

    RRI_cover : cross RRI_opcode_cover, rega_cover, regb_cover, sig_imm {
      // Ignore illegal JALR-with-nonzero-imm combinations
      ignore_bins jalr_inv = binsof(RRI_opcode_cover.JALR) && (!binsof(sig_imm.zero));
    }

    RI_cover  : cross RI_opcode_cover, rega_cover, long_imm;
  endgroup

  // -------- Constructor ----------------------------------
  function new(
    opcode_t     op_in   = opcode_t'(3'b000),
    regflield_t  rega_in = regflield_t'(3'b000),
    regflield_t  regb_in = regflield_t'(3'b000),
    regflield_t  regc_in = regflield_t'(3'b000),
    int          imm_in  = 0
  );
    opcode = op_in;
    rega   = rega_in;
    regb   = regb_in;
    regc   = regc_in;
    imm    = imm_in;
    cg     = new();
  endfunction

  // -------- Pretty print ---------------------------------
  function string to_string();
    string regs = "";
    unique case (opcode)
      ADD, NAND:          regs = $sformatf("r%0d, r%0d, r%0d", rega, regb, regc);
      ADDI, SW, LW, BEQ:  regs = $sformatf("r%0d, r%0d, %0d",  rega, regb, imm);
      JALR:               regs = $sformatf("r%0d, r%0d",       rega, regb);
      LUI:                regs = $sformatf("r%0d, %0d",        rega, imm);
      default:            return "x";
    endcase
    return $sformatf("%-4s %-11s", opcode.name, regs);
  endfunction : to_string

  // -------- Encode to 16-bit word ------------------------
  function logic [15:0] to_bin();
    logic [15:0] temp = '0;
    temp[15:13] = opcode;

    unique case (format_lookup[opcode])
      RRR: temp[12:0] = {rega, regb, 4'b0000, regc};
      RRI: temp[12:0] = {rega, regb, imm[6:0]};  // low 7 bits taken
      RI : temp[12:0] = {rega, imm[9:0]};        // low 10 bits taken
    endcase

    return temp;
  endfunction : to_bin

  // -------- Decode from 16-bit word ----------------------
  function void from_bin(logic [15:0] bin_code);
    opcode = opcode_t'(bin_code[15:13]);
    rega   = bin_code[12:10];

    unique case (format_lookup[opcode])
      RRR: begin
        regb = bin_code[9:7];
        regc = bin_code[2:0];
        imm  = 0;
      end
      RRI: begin
        regb = bin_code[9:7];
        // Sign-extend 7-bit immediate to 32-bit int
        imm  = {{25{bin_code[6]}}, bin_code[6:0]};
      end
      RI: begin
        // Zero-extend 10-bit immediate to 32-bit int
        imm  = bin_code[9:0];
      end
    endcase
  endfunction : from_bin

  // -------- Coverage summary string ----------------------
  function string get_coverage;
    return $sformatf("TOTAL %.2f  RRR %.2f  RRI %.2f  RI %.2f",
                      cg.get_coverage(),
                      cg.RRR_cover.get_coverage(),
                      cg.RRI_cover.get_coverage(),
                      cg.RI_cover.get_coverage());
  endfunction

endclass : instruction

`endif // INSTRUCTION_SVH
