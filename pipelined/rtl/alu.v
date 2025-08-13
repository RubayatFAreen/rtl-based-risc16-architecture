`ifndef ALU_V
`define ALU_V

module alu #(
    // Data-path width (must match the rest of the core)
    parameter int p_WORD_LEN = 16
) (
    // -------------------- Control -------------------------
    input  logic                 i_op,        // 0=ADD, 1=NAND

    // -------------------- Operands ------------------------
    input  logic [p_WORD_LEN-1:0] i_ina,      // input A
    input  logic [p_WORD_LEN-1:0] i_inb,      // input B

    // -------------------- Results -------------------------
    output logic [p_WORD_LEN-1:0] o_out,      // ALU result
    output logic                  o_eq        // (A == B)
);

    // Comparator: 2-state equality (X/Z propagate in sim, which is useful to catch bugs).
    // If you want X-tolerant compares in simulation, change to (i_ina === i_inb).
    assign o_eq = (i_ina == i_inb);

    // Main ALU function.
    // Using always_comb + unique case is cleaner for linting/coverage than nested ?:.
    always_comb begin
        unique case (i_op)
            1'b0:   o_out = i_ina + i_inb;       // ADD (wraps on overflow)
            1'b1:   o_out = ~(i_ina & i_inb);    // NAND
            default:o_out = '0;                  // defensive default
        endcase
    end

// ---------------------------------
// Lightweight formal/sim assertions
// ---------------------------------
`ifdef FORMAL
    // Prove the ALU matches the spec for both ops.
    always @* begin
        assert(o_eq == (i_ina == i_inb));
        if (i_op == 1'b0) assert(o_out == (i_ina + i_inb));
        if (i_op == 1'b1) assert(o_out == ~(i_ina & i_inb));
    end
`endif

endmodule

`endif // ALU_V
