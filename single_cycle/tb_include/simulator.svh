`ifndef SIMULATOR_SVH
`define SIMULATOR_SVH

`include "instruction.svh"
`include "mem_data_ref.svh"
`include "mem_reg_ref.svh"

class simulator #(int INSTRUCTION_COUNT = 100, int DATA_COUNT = 1024);

    // ------------------ State ------------------------------
    datamem #(DATA_COUNT)   data_mem;        // behavioural data memory
    regfile                 registers;       // behavioural reg file

    int unsigned            program_counter; // 16-bit PC held in 32-bit var

    // Holds instruction to execute *this* cycle (set by TB)
    instruction             inst;

    // Scratch for JALR temp target
    int unsigned            temp;

    // ------------------ Constructor ------------------------
    function new();
        program_counter = 0;
        data_mem        = new();
        registers       = new();
        inst            = new();
    endfunction

    // ------------------ Pretty-print -----------------------
    function string to_string();
        string s;
        s = $sformatf("PC=%04h : %-16s :", program_counter[15:0], inst.to_string());
        for (int i = 0; i < 8; i++)
            s = $sformatf("%s r%0d=%04h", s, i, registers.read_reg(i));
        return s;
    endfunction

    // ------------------ Inject instruction -----------------
    function void set_inst(instruction inp);
        inst = inp;
    endfunction

    // ------------------ Execute one instruction ------------
    function void exec_inst();

        // Local helpers
        automatic int signed  imm_val = inst.imm;              // sign already handled by class
        automatic int unsigned base, ea;

        unique case (inst.opcode)
            ADD:  registers.write_reg(inst.rega, registers.read_reg(inst.regb) + registers.read_reg(inst.regc));
            ADDI: registers.write_reg(inst.rega, registers.read_reg(inst.regb) + imm_val);
            NAND: registers.write_reg(inst.rega, ~(registers.read_reg(inst.regb) & registers.read_reg(inst.regc)));
            LUI:  registers.write_reg(inst.rega, {inst.imm, 6'b0});

            SW: begin
                base = registers.read_reg(inst.regb);
                ea   = base + imm_val;
                data_mem.write_mem(ea[15:0], registers.read_reg(inst.rega));
            end

            LW: begin
                base = registers.read_reg(inst.regb);
                ea   = base + imm_val;
                registers.write_reg(inst.rega, data_mem.read_mem(ea[15:0]));
            end

            BEQ: begin
                if (registers.read_reg(inst.rega) == registers.read_reg(inst.regb))
                    program_counter += 1 + imm_val;
                else
                    program_counter += 1;
            end

            JALR: begin
                temp = registers.read_reg(inst.regb);
                if (inst.rega != 0)
                    registers.write_reg(inst.rega, program_counter + 1);
                program_counter = temp;
            end

            default: ; // no-op for safety
        endcase

        // Default PC update for non-branching instructions
        if (inst.opcode inside {ADD, ADDI, NAND, LUI, SW, LW})
            program_counter += 1;

        // Wrap PC to 16 bits (RiSC-16 address space)
        program_counter &= 16'hFFFF;
    endfunction

    // ------------------ State validity checks --------------
    function void verify_state();
        assert(program_counter < 16'h10000) else $fatal("PC out of range");
    endfunction

endclass

`endif // SIMULATOR_SVH