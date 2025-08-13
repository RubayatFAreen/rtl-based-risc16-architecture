`ifndef INSTRUCTION_SVH
`define INSTRUCTION_SVH

// ------------------------------------------------------------
//  Opcode / format enums
// ------------------------------------------------------------

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

typedef enum logic [1:0] {
    RRR = 2'd0,   // reg‑reg‑reg
    RRI = 2'd1,   // reg‑reg‑imm(7)
    RI  = 2'd2    // reg‑imm(10)
} opcode_format_t;

// 3‑bit register field (0‑7)
typedef logic [2:0] regflield_t;   

// ------------------------------------------------------------
//  Instruction class
// ------------------------------------------------------------

class instruction;

    // ------------- RAND fields (original names kept) --------
    rand opcode_t     opcode;       // operation code
    rand regflield_t  rega, regb, regc; // register specifiers
    rand int          imm;          // immediate (signed int for convenience)

    // ------------- Format lookup table ---------------------
    static const opcode_format_t FORMAT_LUT [opcode_t] = '{
        ADD  : RRR,
        ADDI : RRI,
        NAND : RRR,
        LUI  : RI,
        SW   : RRI,
        LW   : RRI,
        BEQ  : RRI,
        JALR : RRI
    };

    // ------------- Constraints -----------------------------
    //  • Valid immediates per format
    //  • JALR must have imm==0
    //
    constraint c_imm {
        solve opcode before imm;

        if (FORMAT_LUT[opcode] == RRI) {
            if (opcode == JALR)
                imm == 0;
            else
                imm inside {[-64:63]};
        } else if (FORMAT_LUT[opcode] == RI) {
            imm inside {[0:1023]};
        } else {
            imm == 0;  // no imm for RRR
        }
    }

    // Optional biasing for interesting corner immediates
    constraint c_imm_dist {
        if (FORMAT_LUT[opcode] == RRI && opcode != JALR) {
            imm dist { 0 := 10, -64 := 5, 63 := 5, [-63:-1] :/ 40, [1:62] :/ 40 };
        } else if (FORMAT_LUT[opcode] == RI) {
            imm dist { 0 := 10, 1023 := 10, [1:1022] :/ 80 };
        }
    }

    // ------------- Functional coverage ---------------------
    covergroup cg;
        RRR_op  : coverpoint opcode iff (FORMAT_LUT[opcode]==RRR) { bins ADD = {ADD}; bins NAND = {NAND}; }
        RRI_op  : coverpoint opcode iff (FORMAT_LUT[opcode]==RRI) { bins ADDI = {ADDI}; bins SW = {SW}; bins LW={LW}; bins BEQ={BEQ}; bins JALR={JALR}; }
        RI_op   : coverpoint opcode iff (FORMAT_LUT[opcode]==RI)  { bins LUI = {LUI}; }

        rega_cp : coverpoint rega;
        regb_cp : coverpoint regb iff (FORMAT_LUT[opcode]!=RI);
        regc_cp : coverpoint regc iff (FORMAT_LUT[opcode]==RRR);

        imm7_cp : coverpoint imm iff (FORMAT_LUT[opcode]==RRI) {
            bins zero = {0}; bins min = {-64}; bins max = {63}; bins pos = {[1:63]}; bins neg = {[-63:-1]};
        }
        imm10_cp: coverpoint imm iff (FORMAT_LUT[opcode]==RI) {
            bins zero = {0}; bins max = {1023}; bins others[5] = {[1:1022]};
        }

        cross_RRR : cross RRR_op, rega_cp, regb_cp, regc_cp;
        cross_RRI : cross RRI_op, rega_cp, regb_cp, imm7_cp {
            ignore_bins jalr_nonzero = binsof(RRI_op.JALR) && (!binsof(imm7_cp.zero));
        }
        cross_RI  : cross RI_op, rega_cp, imm10_cp;
    endgroup

    // ------------- Constructor -----------------------------
    function new(
        opcode_t op_in       = '0,
        regflield_t rega_in  = '0,
        regflield_t regb_in  = '0,
        regflield_t regc_in  = '0,
        int imm_in           = 0
    );
        opcode = op_in; rega = rega_in; regb = regb_in; regc = regc_in; imm = imm_in;
        cg = new();
    endfunction

    // ------------- Pretty‑print -----------------------------
    function string to_string();
        string s;
        unique case (opcode)
            ADD, NAND:  s = $sformatf("%s r%0d,r%0d,r%0d", opcode.name, rega, regb, regc);
            ADDI, SW, LW, BEQ: s = $sformatf("%s r%0d,r%0d,%0d", opcode.name, rega, regb, imm);
            JALR:        s = $sformatf("JALR r%0d,r%0d", rega, regb);
            LUI:         s = $sformatf("LUI  r%0d,%0d", rega, imm);
            default:     s = "INVALID";
        endcase
        return s;
    endfunction

    // ------------- Encode to 16‑bit word --------------------
    function logic [15:0] to_bin();
        logic [15:0] word = 16'h0;
        word[15:13] = opcode;
        unique case (FORMAT_LUT[opcode])
            RRR: word[12:0] = {rega, regb, 4'b0, regc};
            RRI: word[12:0] = {rega, regb, imm[6:0]};
            RI : word[12:0] = {rega, imm[9:0]};
        endcase
        return word;
    endfunction

    // ------------- Decode from 16‑bit word ------------------
    function void from_bin(logic [15:0] bin_code);
        opcode = opcode_t'(bin_code[15:13]);
        rega   = bin_code[12:10];
        unique case (FORMAT_LUT[opcode])
            RRR: begin regb = bin_code[9:7]; regc = bin_code[2:0]; imm = 0; end
            RRI: begin regb = bin_code[9:7]; imm = {{25{bin_code[6]}}, bin_code[6:0]}; end
            RI : begin imm = bin_code[9:0]; end
        endcase
    endfunction

    // ------------- Coverage report string ------------------
    function string get_coverage();
        return $sformatf("TOTAL %.2f  RRR %.2f  RRI %.2f  RI %.2f",
                          cg.get_coverage(), cg.cross_RRR.get_coverage(), cg.cross_RRI.get_coverage(), cg.cross_RI.get_coverage());
    endfunction

endclass

`endif // INSTRUCTION_SVH
