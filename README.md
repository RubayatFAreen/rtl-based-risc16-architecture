# RiSC-16 Project

A collection of SystemVerilog modules, reference models, and testbenches for the RiSC-16 architecture, including fully self-checking single-cycle and pipelined CPU implementations.

## Project Structure

```
.
├── single_cycle/         # Main single-cycle CPU implementation and documentation
│   ├── rtl/              # RTL for single-cycle core
│   │   ├── core.v
│   │   ├── design.v
│   │   ├── mem_data.v
│   │   └── mem_reg.v
│   ├── tb/               # Testbenches for single-cycle core
│   │   ├── core_test.sv
│   │   ├── inst_test.sv
│   │   ├── mem_data_test.sv
│   │   └── mem_reg_test.sv
│   ├── tb_include/       # Testbench includes
│   │   ├── instruction.svh
│   │   ├── mem_data_ref.svh
│   │   ├── mem_reg_ref.svh
│   │   └── simulator.svh
│   └── README.md         # Detailed documentation for single-cycle core
├── pipelined/            # Pipelined CPU implementation and documentation
│   ├── rtl/              # RTL for pipelined core
│   │   ├── alu.v
│   │   ├── core.v
│   │   ├── design.v
│   │   ├── mem_data.v
│   │   └── mem_reg.v
│   ├── tb/               # Testbenches for pipelined core
│   │   ├── core_test.sv
│   │   ├── inst_test.sv
│   │   ├── mem_data_test.sv
│   │   └── mem_reg_test.sv
│   ├── tb_include/       # Testbench includes
│   │   ├── instruction.svh
│   │   ├── mem_data_ref.svh
│   │   ├── mem_reg_ref.svh
│   │   └── simulator.svh
│   └── README.md         # Documentation for pipelined core
├── RiSC-isa.pdf         # RiSC-16 ISA reference
```

## Quick Start

See the [single_cycle/README.md](single_cycle/README.md) and [pipelined/README.md](pipelined/README.md) for detailed build and simulation instructions, including supported tools and testbench usage.

## Features
- 16-bit RiSC-16 single-cycle CPU (SystemVerilog)
- 16-bit RiSC-16 pipelined CPU (SystemVerilog)
- Parameterized register file and data memory
- Golden software simulator and reference models
- Randomized, self-checking testbenches with functional coverage
- Formal verification hooks

## Documentation
- [Single-cycle CPU documentation](single_cycle/README.md)
- [Pipelined CPU documentation](pipelined/README.md)
- [RiSC-16 ISA reference](RiSC-isa.pdf)

## License
See the license file or headers in source files for usage terms.
