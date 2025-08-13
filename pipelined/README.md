# RiSC-16 — Pipelined CPU (SystemVerilog)

A high-performance, self-checking pipelined implementation of a 16-bit RiSC-16-style processor. This project features a classic 5-stage pipeline, advanced data forwarding, hazard detection, and robust verification infrastructure. Designed for both learning and research, it demonstrates the practical tradeoffs and optimizations of pipelined RISC CPU design.

---

<!-- If you have a pipeline diagram, add it here! -->

---

## 🚀 Table of Contents
- [Features](#features)
- [Pipeline Architecture](#pipeline-architecture)
- [ISA Summary](#isa-summary)
- [Pipeline Hazards & Forwarding](#pipeline-hazards--forwarding)
- [Directory Layout](#directory-layout)
- [Quick Start](#quick-start)
- [RTL Modules](#rtl-modules)
- [Reference Models](#reference-models)
- [Testbenches](#testbenches)
- [Verification](#verification)
- [Synthesis Results](#synthesis-results)
- [Roadmap](#roadmap)
- [License](#license)

## ✨ Features
- Classic 5-stage pipeline: Fetch, Decode, Execute, Memory, Writeback
- Data forwarding and hazard detection for high throughput
- Automatic pipeline stalling and bubble (NOP) insertion
- Parameterized, modular SystemVerilog RTL
- Golden software simulator and reference models
- Randomized, self-checking testbenches
- Synthesis- and FPGA-friendly design

## 🏗️ Pipeline Architecture
The RiSC-16 pipelined CPU implements a classic RISC pipeline:
- **Fetch**: Instruction fetch, branch/jump handling, bubble insertion
- **Decode**: Register read, immediate extraction, operand forwarding
- **Execute**: ALU operations, branch condition evaluation, forwarding
- **Memory**: Data memory access (LW/SW), address calculation
- **Writeback**: Register file update (with r0 always zero)

Pipeline registers separate each stage, and results are forwarded as needed to resolve data hazards. Stalls and bubbles are inserted for load-use hazards and control hazards (branches/jumps).

## 🧮 ISA Summary
| Instruction | Description |
|-------------|-------------|
| ADD         | rega = regb + regc |
| ADDI        | rega = regb + imm |
| NAND        | rega = ~(regb & regc) |
| LUI         | rega = imm |
| SW          | mem[regb + imm] = rega |
| LW          | rega = mem[regb + imm] |
| BEQ         | pc = rega == regb ? pc + 1 + imm : pc + 1 |
| JALR        | rega = pc + 1; pc = regb |

## ⚡ Pipeline Hazards & Forwarding
- **Data hazards**: Results needed by following instructions are forwarded from later pipeline stages (EX/MEM/WB) to the execute stage as needed.
- **Load-use hazard**: If a LW is followed by an instruction using its result, a bubble (NOP) is inserted.
- **Control hazards**: Branches (BEQ) and jumps (JALR) insert bubbles until the target is known (2 for BEQ, 1 for JALR).
- **Stall logic**: Pipeline registers and control logic automatically insert bubbles and forward data to maximize throughput.

## 📁 Directory Layout
```
rtl/           # RTL modules (core, ALU, regfile, memory, toplevel)
tb/            # Testbenches (randomized, self-checking)
tb_include/    # Testbench includes (instruction model, reference models, simulator)
README.md      # This file
```

## ⚡ Quick Start
Requires a SystemVerilog simulator with verification support (Questa/ModelSim, VCS, Xcelium, Riviera).

**ModelSim/Questa example:**
```tcl
# from pipelined directory
vlog +acc rtl/*.v tb_include/*.svh tb/*.sv
top_test="core_test" # or inst_test, mem_reg_test, mem_data_test
vsim -c work.$top_test -do "run -all; quit"
```
Wave dumps: `core_tb.vcd`, `inst_tb.vcd`, `mem_reg_tb.vcd`, `mem_data_tb.vcd`.

**EDA Playground:** Paste files, pick Questa/Riviera, set *_test.sv as the top, Run.

## 🛠️ RTL Modules
- **rtl/core.v:** Pipelined CPU core
- **rtl/alu.v:** ALU for arithmetic/logic ops
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

## 🔬 Verification
- Queue-based instruction tracking to match pipeline flow
- Extensive logging of pipeline registers for debug
- Randomized, self-checking testbenches (100,000+ instructions verified)
- IPC (Instructions Per Cycle) ~0.72, CPI ~1.39 (no branch prediction)

## 🏭 Synthesis Results (Xilinx example)
- **Register file:** Uses distributed RAM (LUTs), highly optimized for dual-read
- **Data memory:** 2KB fits in half a BRAM
- **Whole design:** ~0.4% LUTs, ~0.7% BRAM, 150MHz Fmax (double single-cycle)
- **Resource usage:**
  - 265 LUTs, 224 registers, 2 BRAMs (1 for data, 1 for instructions)
- **Performance:**
  - IPC < 1 due to stalls/bubbles, but higher Fmax and lower resource use than single-cycle

## 🗺️ Roadmap
- Branch prediction (static/dynamic)
- More formal properties (pipeline invariants, forwarding correctness)
- Minimal assembler + loader for generating code.data
- Optional halt/exception model

## 📄 License
See the license file or headers in source files for usage terms.
