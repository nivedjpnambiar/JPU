# JPU — A RiSC-16 Single-Cycle CPU in Verilog

A complete, working **RiSC-16** processor written in Verilog and verified with a
self-checking [Verilator](https://www.veripool.org/verilator/) C++ testbench.
The whole CPU is built from ten small leaf modules wired together in
[`jpu.v`](Verilog/modules/jpu.v) — fetch, decode, register file, ALU, load/store,
data memory, branch/JALR logic, and the PC control unit.

> Status: functionally complete. **35/35** whole-CPU checks pass, covering all 8
> RiSC-16 opcodes plus edge cases (r0-hardwiring, 16-bit overflow wrap, and a
> real summation loop).

See [`Verilog/modules/DATAPATH.md`](Verilog/modules/DATAPATH.md) for the full
datapath block diagram (Mermaid + ASCII).

---

## Prerequisites

You need **Verilator** (compiles the RTL + C++ testbench) and, optionally,
**GTKWave** (to view waveforms). The easiest way to get both is the
[OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build), which bundles
them:

```bash
# Download a release for your OS from:
#   https://github.com/YosysHQ/oss-cad-suite-build/releases
# then add it to your PATH, e.g.:
export PATH="$HOME/oss-cad-suite/bin:$PATH"
```

Verify the tools are visible:

```bash
verilator --version
gtkwave --version
```

(Alternatively, install `verilator` and `gtkwave` from your distro's package
manager — e.g. `sudo apt install verilator gtkwave`.)

---

## Build & run the tests

All commands run from the `Verilog/modules` directory:

```bash
cd Verilog/modules
./run_tb.sh
```

`run_tb.sh` invokes Verilator to translate the Verilog into C++, compiles it
together with the testbench (`tb_jpu.cpp`) into a native binary
(`obj_dir/Vjpu_tb`), then runs it. You should see:

```
==== JPU whole-CPU C++ testbench ====
[test_arith] ...
  PASS: r1     = 0x0045
  ...
==== 35/35 checks passed ====
ALL PASS
```

The script rebuilds automatically whenever a source file changes, so
`./run_tb.sh` is the only command you ever need.

---

## Generate and view waveforms (GTKWave)

Pass `--trace` to also dump a `.vcd` (Value Change Dump) file per test:

```bash
cd Verilog/modules
./run_tb.sh --trace
```

This writes one VCD per test case into `Verilog/modules/`:

| File | Test program |
|------|--------------|
| `jpu_arith.vcd`  | ADD / ADDI (incl. negative immediate) / NAND / LUI |
| `jpu_lwsw.vcd`   | SW → LW round trip, signed offsets, no aliasing |
| `jpu_branch.vcd` | BEQ not-taken / taken, JALR link & jump |
| `jpu_r0.vcd`     | writes to `r0` are discarded (hardwired 0) |
| `jpu_wrap.vcd`   | arithmetic wraps mod 2¹⁶ |
| `jpu_loop.vcd`   | `for(i=1..5) sum += i` → 15 (backward branch loop) |

Open any of them in GTKWave:

```bash
gtkwave jpu_arith.vcd
```

In GTKWave: expand `TOP → jpu` in the left panel, drag signals (e.g. `clk`,
`pc_out`, and `u_regfile.regs`) into the wave window, then **Zoom Fit**
(`Ctrl+0`). Tip: right-click a bus → *Data Format → Decimal* if you'd rather
read values in base-10 than hex.

---

## Instruction set (RiSC-16)

16-bit instructions, 8 registers (`r0`–`r7`, `r0` hardwired to 0).

| Opcode | Mnemonic | Format | Operation |
|:------:|----------|--------|-----------|
| 000 | `add`  | RRR | `rA = rB + rC` |
| 001 | `addi` | RRI | `rA = rB + signext(imm7)` |
| 010 | `nand` | RRR | `rA = ~(rB & rC)` |
| 011 | `lui`  | RI  | `rA = imm10 << 6` |
| 100 | `sw`   | RRI | `mem[rB + signext(imm7)] = rA` |
| 101 | `lw`   | RRI | `rA = mem[rB + signext(imm7)]` |
| 110 | `beq`  | RRI | `if (rA == rB) PC = PC + 1 + signext(imm7)` |
| 111 | `jalr` | RRI | `rA = PC + 1; PC = rB` |

The ISA reference (green card) is in
[`Verilog/modules/ISA/`](Verilog/modules/ISA/).

---

## Repository layout

```
Verilog/modules/
  jpu.v          top-level CPU (wires the 10 modules together; no logic of its own)
  CU.v           control unit — owns the PC register, picks next PC
  instr_mem.v    instruction memory (combinational fetch)
  decoder.v      instruction decode → control signals
  registers.v    register file (async read, sync write, r0 = 0)
  ALU.v          add / addi / nand
  load.v         LUI value or LW address
  store.v        SW address + data
  memory.v       data memory (async read, sync write)
  PC.v           branch / JALR target calculator
  regw.v         write-back source mux
  tb_jpu.cpp     Verilator whole-CPU self-checking testbench
  run_tb.sh      build + run script
  DATAPATH.md    datapath block diagram
  program.hex    default instruction-memory init file
  tb_*.v         per-module unit testbenches
```

---

## How the testbench works

Each test creates a fresh CPU instance (new `VerilatedContext` + `Vjpu`) so the
register file and memories start zeroed and tests don't bleed state. A test
program is just a C++ array of 16-bit instruction words loaded straight into
instruction memory — no hex files, no per-program rebuild. Every program ends in
`beq r0, r0, -1` (a self-loop "halt") so the CPU settles into a known state, and
results are then checked against hand-computed values. Internal architectural
state (registers, data memory) is read back through signals tagged
`/* verilator public_flat_rw */`.
