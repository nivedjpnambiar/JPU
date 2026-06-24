#!/usr/bin/env bash
# Build and run the whole-CPU Verilator C++ testbench.
#   ./run_tb.sh            # build + run
#   ./run_tb.sh --trace    # also emit jpu_arith.vcd / jpu_lwsw.vcd / jpu_branch.vcd
set -e
cd "$(dirname "$0")"

verilator --cc --exe --build -j 0 --trace --top-module jpu \
  -Wno-WIDTHTRUNC -Wno-EOFNEWLINE -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL \
  jpu.v CU.v instr_mem.v decoder.v registers.v ALU.v load.v store.v \
  memory.v PC.v regw.v tb_jpu.cpp -o Vjpu_tb

exec ./obj_dir/Vjpu_tb "$@"
