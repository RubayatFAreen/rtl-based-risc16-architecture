# RiSC-16 — Single-Cycle CPU (SystemVerilog)

A modern, self-checking, single-cycle implementation of a 16-bit RiSC-16-style processor. This project features clean, parameterized SystemVerilog RTL, a golden software simulator, and advanced randomized testbenches with functional coverage and formal verification hooks. Designed for both education and research, it provides a robust platform for exploring RISC architectures, CPU design, and hardware verification.

---

![Single-Cycle Datapath](Single%20Cycle.png)

---

## 🚀 Table of Contents
- [Features](#features)
- [Architecture Overview](#architecture-overview)
- [ISA Snapshot](#isa-snapshot)
- [Directory Layout](#directory-layout)
- [Quick Start](#quick-start)
- [Building a Program ROM](#building-a-program-rom-codedata)
- [RTL Modules](#rtl-modules)
- [Reference Models](#reference-models)
- [Testbenches](#testbenches)
- [Verification Strategy](#verification-strategy)
- [Formal Notes](#formal-notes)
- [Synthesis & FPGA Tips](#synthesis--fpga-tips)
- [Roadmap](#roadmap)
- [License](#license)

## ✨ Features
- **One-cycle datapath:** fetch → decode → execute → memory → writeback in a single clock
- **8 registers (r0..r7):** 16-bit words, r0 hard-wired to zero
- **Harvard architecture:** separate instruction ROM and data RAM
- **Modern SystemVerilog style:** logic, always_ff/always_comb, enums, packed types
- **Self-checking verification:** randomized stimulus, functional coverage, golden software simulator
- **Formal hooks:** SymbiYosys-friendly memory/register file assertions
- **Educational clarity:** readable, modular code and extensive documentation

## 🖥️ Architecture Overview
The RiSC-16 single-cycle CPU implements a classic RISC datapath, executing each instruction in one clock. The design is modular, with clear separation between the core, register file, and data memory. The project includes:
- Parameterized RTL for easy scaling/modification
- Golden ISS (Instruction Set Simulator) for architectural reference
- Randomized, self-checking testbenches for robust verification

## 🧮 ISA Snapshot
| Opcode | Format | Fields | Semantics (brief) |
|--------|--------|--------|-------------------|
| ADD    | RRR    | rega, regb, regc | rega ← regb + regc |
| ADDI   | RRI    | rega, regb, imm7(signed) | rega ← regb + signext(imm7) |
| NAND   | RRR    | rega, regb, regc | rega ← ~(regb & regc) |
| LUI    | RI     | rega, imm10 | rega ← {imm10, 6'b0} (imm10 << 6) |
| SW     | RRI    | rega, regb, imm7(signed) | MEM[regb + signext(imm7)] ← rega |
| LW     | RRI    | rega, regb, imm7(signed) | rega ← MEM[regb + signext(imm7)] |
| BEQ    | RRI    | rega, regb, imm7(signed) | if rega==regb then PC ← PC+1+signext(imm7) else PC ← PC+1 |
| JALR   | RRI    | rega, regb, imm7=0 | rega ← PC+1; PC ← regb (write to r0 ignored) |

## 📁 Directory Layout
```
rtl/           # RTL modules (core, regfile, memory, toplevel)
tb/            # Testbenches (randomized, self-checking)
tb_include/    # Testbench includes (instruction model, reference models, simulator)
Single Cycle.png  # Datapath diagram (see above)
README.md      # This file
```

## ⚡ Quick Start
Requires a SystemVerilog simulator with verification support (Questa/ModelSim, VCS, Xcelium, Riviera). Verilator is great for synthesizable RTL but won’t run the class-based testbenches.

**ModelSim/Questa example:**
```tcl
# from single_cycle directory
vlog +acc rtl/*.v tb_include/*.svh tb/*.sv
top_test="core_test" # or inst_test, mem_reg_test, mem_data_test
vsim -c work.$top_test -do "run -all; quit"
```
Wave dumps: `core_tb.vcd`, `inst_tb.vcd`, `mem_reg_tb.vcd`, `mem_data_tb.vcd`.

**EDA Playground:** Paste files, pick Questa/Riviera, set *_test.sv as the top, Run.

## 🏗️ Building a Program ROM (code.data)
Toplevel reads binary lines with `$readmemb("code.data", inst_memory);`.
- One 16-bit instruction per line (e.g., `0000000000000000`)
- Prefer hex? Use `$readmemh` or script generation with `instruction.to_bin()`

## 🛠️ RTL Modules
- **rtl/core.v:** CPU core (no instruction memory)
- **rtl/mem_reg.v:** 8×16 register file (2R/1W, r0=0)
- **rtl/mem_data.v:** Data memory (parametric, async read by default)
- **rtl/design.v:** Toplevel: core + instr ROM + data RAM

## 🧩 Reference Models (tb_include/)
- **instruction.svh:** Randomizable instruction model + coverage
- **mem_reg_ref.svh:** Behavioral regfile reference model
- **mem_data_ref.svh:** Behavioral data memory reference model
- **simulator.svh:** Golden software simulator (ISS)

## 🧪 Testbenches (tb/)
All testbenches are self-checking and print coverage:
- **inst_test.sv:** Encode/decode round-trip, coverage
- **mem_reg_test.sv:** Random regfile ops, async read checks, scoreboard, coverage
- **mem_data_test.sv:** Random memory traffic, reference checks, full address coverage
- **core_test.sv:** Random instructions, step-by-step ISS comparison, state dump on mismatch

## 🔬 Verification Strategy
- Constrained-random generation via instruction.svh (valid immediates, JALR imm=0, value biasing toward corners)
- Functional coverage baked into the instruction class; testbenches just call `inst.cg.sample()`
- Golden model (simulator.svh) ensures architectural equivalence at each step
- Waveforms (VCD) for any failing seed
- Formal hooks prove basic memory/register invariants

## 🧾 Formal Notes
- Proofs targeted at mem_reg.v and mem_data.v (read-after-write, X-safety, r0=0)
- RTL carries small FORMAL blocks suitable for SymbiYosys
- Add your .sby configs/constraints as needed (not included here)

## 🛠️ Synthesis & FPGA Tips
- Async read memories usually infer distributed RAM (LUTs)
- For BRAM inference, set p_ASYNC_READ=0 (registered read → one extra cycle)
- Avoid global, single-cycle memory clears in RTL (huge LUT cost). Prefer simulation-only init or preload files
- Single-cycle cores have a long critical path (often LW). Expect lower Fmax than pipelined designs

## 🗺️ Roadmap
- Pipelined/multicycle CPU (better Fmax, BRAM-friendly)
- Minimal assembler + loader for generating code.data
- More formal properties (ALU equivalence, PC arithmetic, BEQ/JALR invariants)
- Optional halt/exception model

## 📄 License
See the license file or headers in source files for usage terms.