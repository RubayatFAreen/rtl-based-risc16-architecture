`ifndef SIMULATOR_SVH
`define SIMULATOR_SVH

`include "instruction.svh"
`include "mem_data_ref.svh"
`include "mem_reg_ref.svh"

class simulator #(int INSTRUCTION_COUNT = 100, int DATA_COUNT = 100);

  // ------------------- Architectural state -------------------
  datamem #(DATA_COUNT) data_mem;     // behavioral data memory
  regfile               registers;    // behavioral register file

  int program_counter;                // current PC (wrapped to 16 bits after each step)
  int program_counter_prev;           // PC value before executing the current instruction
  int temp;                           // scratch (JALR target)

  instruction inst;                   // instruction to execute this step

  // ------------------- Constructor ---------------------------
  function new();
    program_counter       = 0;
    program_counter_prev  = 0;

    data_mem   = new();
    registers  = new();
    inst       = new();
  endfunction : new

  // ------------------- Pretty print state --------------------
  // Format: "<prev_PC> : <instr> : r0 .. r7"
  function string to_string();
    string temp = $sformatf("%4h : %-16s : ", program_counter_prev[15:0], inst.to_string());
    for (int i = 0; i < 8; i++)
      temp = $sformatf("%s r%0d-%h", temp, i, registers.read_reg(i));
    return temp;
  endfunction : to_string

  // ------------------- Set next instruction ------------------
  function void set_inst(instruction inp);
    inst = inp;
  endfunction

  // ------------------- Execute one instruction ---------------
  function void exec_inst();
    // Snapshot PC for debug/scoreboarding
    program_counter_prev = program_counter;

    // Local helpers (types chosen to avoid accidental sign surprises)
    automatic int signed   imm_val = inst.imm;               // imm already constrained/signed by class
    automatic int unsigned base, ea;                          // for address arithmetic

    // Core behavior per opcode
    unique case (inst.opcode)
      ADD : begin
        registers.write_reg(inst.rega,
                            registers.read_reg(inst.regb) + registers.read_reg(inst.regc));
        program_counter = program_counter + 1;
      end

      ADDI : begin
        registers.write_reg(inst.rega,
                            registers.read_reg(inst.regb) + imm_val);
        program_counter = program_counter + 1;
      end

      NAND : begin
        registers.write_reg(inst.rega,
                            ~(registers.read_reg(inst.regb) & registers.read_reg(inst.regc)));
        program_counter = program_counter + 1;
      end

      LUI : begin
        // Place imm in upper bits per ISA (imm << 6)
        registers.write_reg(inst.rega, {inst.imm, 6'b0});
        program_counter = program_counter + 1;
      end

      SW : begin
        base = registers.read_reg(inst.regb);
        ea   = base + imm_val;
        data_mem.write_mem(ea[15:0], registers.read_reg(inst.rega));
        program_counter = program_counter + 1;
      end

      LW : begin
        base = registers.read_reg(inst.regb);
        ea   = base + imm_val;
        registers.write_reg(inst.rega, data_mem.read_mem(ea[15:0]));
        program_counter = program_counter + 1;
      end

      BEQ : begin
        if (registers.read_reg(inst.rega) == registers.read_reg(inst.regb))
          program_counter = program_counter + imm_val + 1;
        else
          program_counter = program_counter + 1;
      end

      JALR : begin
        temp = registers.read_reg(inst.regb);
        if (inst.rega != 0)
          registers.write_reg(inst.rega, program_counter + 1);
        program_counter = temp;
      end

      default : begin
        // NOP on unknown opcode, advance PC
        program_counter = program_counter + 1;
      end
    endcase

    // Keep PC in 16-bit address space (wrap-around)
    program_counter &= 16'hFFFF;
  endfunction : exec_inst

  // ------------------- Lightweight assertions ----------------
  function void verify_state;
    // PC must always be in range 0..65535
    assert(program_counter >= 0 && program_counter < 65536)
      else $fatal("PC out of range: %0d", program_counter);

    // Registers model enforces r0==0; assert here as well
    assert(registers.read_reg(3'd0) == 16'h0000)
      else $fatal("r0 violated in reference model");
  endfunction

endclass

`endif

