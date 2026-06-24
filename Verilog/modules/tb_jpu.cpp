// ============================================================
// tb_jpu.cpp  —  Verilator C++ testbench for the whole RiSC-16 CPU
// ============================================================
// Why C++ instead of a .v testbench:
//   * Verilator compiles the RTL to native code -> fast, especially
//     for multi-cycle / looping programs.
//   * Test programs are plain C++ arrays of 16-bit instruction words,
//     loaded straight into instruction memory at run time. No hex
//     files, no per-program rebuild.
//   * Each test gets a FRESH cpu (new Vjpu) so register file and data
//     memory start zeroed (the modules' `initial` blocks) -> tests are
//     isolated, no state bleed between programs.
//   * Results are checked in C++ against hand-computed values.
//
// Internal visibility: registers.v `regs`, memory.v `mems`, and
// instr_mem.v `mem` are tagged /* verilator public_flat_rw */ so this
// harness can load programs and read back architectural state.
//
// Build & run (from this directory):
//   verilator --cc --exe --build -j 0 --top-module jpu \
//     -Wno-WIDTHTRUNC -Wno-EOFNEWLINE -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL \
//     jpu.v CU.v instr_mem.v decoder.v registers.v ALU.v load.v store.v \
//     memory.v PC.v regw.v tb_jpu.cpp -o Vjpu_tb
//   ./obj_dir/Vjpu_tb            # add --trace for a .vcd per test
// ============================================================

#include "Vjpu.h"
#include "Vjpu___024root.h"     // internal (public_flat) signal access
#include "verilated.h"
#include "verilated_vcd_c.h"

#include <cstdint>
#include <cstdio>
#include <vector>

double sc_time_stamp() { return 0; }   // legacy hook; per-context time is used

static bool g_trace   = false;
static int  g_errors  = 0;
static int  g_checks  = 0;

// ── A self-contained CPU instance with optional waveform tracing ──
// Each Cpu owns its own VerilatedContext so multiple models can be
// created back-to-back (the default global context refuses a second
// model once simulated time is non-zero).
struct Cpu {
    VerilatedContext* ctx;
    Vjpu*             dut;
    VerilatedVcdC*    tfp = nullptr;
    vluint64_t        t   = 0;

    explicit Cpu(const char* vcd_name) {
        ctx = new VerilatedContext;
        ctx->traceEverOn(g_trace);
        dut = new Vjpu(ctx);
        if (g_trace) {
            tfp = new VerilatedVcdC;
            dut->trace(tfp, 99);
            tfp->open(vcd_name);
        }
    }
    ~Cpu() {
        if (tfp) { tfp->close(); delete tfp; }
        dut->final();
        delete dut;
        delete ctx;
    }

    // One full clock period: low phase, then rising edge (state updates).
    void tick() {
        dut->clk = 0; dut->eval(); t++; if (tfp) tfp->dump(t);
        dut->clk = 1; dut->eval(); t++; if (tfp) tfp->dump(t);
    }

    // Architectural-state accessors (public_flat arrays via the root).
    uint16_t reg(int i)  const { return dut->rootp->jpu__DOT__u_regfile__DOT__regs[i]; }
    uint16_t mem(int i)  const { return dut->rootp->jpu__DOT__u_memory__DOT__mems[i]; }
    uint16_t pc()        const { return dut->pc_out; }

    void load(const std::vector<uint16_t>& prog) {
        for (size_t i = 0; i < prog.size(); ++i)
            dut->rootp->jpu__DOT__u_imem__DOT__mem[i] = prog[i];
    }

    // Reset, load program, run `cycles` clocks (settles into a halt loop).
    void run(const std::vector<uint16_t>& prog, int cycles) {
        dut->rst = 1; dut->clk = 0;
        dut->eval();           // run initial blocks (zero-fill regs/mem/imem)
        if (tfp) tfp->dump(t);
        load(prog);            // overwrite imem with our test program
        tick();                // two reset cycles: PC held at 0
        tick();
        dut->rst = 0;
        for (int i = 0; i < cycles; ++i) tick();
    }
};

static void check(const char* name, uint16_t got, uint16_t exp) {
    g_checks++;
    if (got != exp) {
        printf("  FAIL: %-6s = 0x%04X  (expected 0x%04X)\n", name, got, exp);
        g_errors++;
    } else {
        printf("  PASS: %-6s = 0x%04X\n", name, got);
    }
}

// ─────────────────────────────────────────────────────────────
//  Test 1 — arithmetic smoke test
//    lui/addi (incl. NEGATIVE imm), add (RRR routing), nand, beq self-loop
// ─────────────────────────────────────────────────────────────
static void test_arith() {
    printf("\n[test_arith] ADD/ADDI/NAND/LUI + signed immediate\n");
    Cpu c("jpu_arith.vcd");
    c.run({
        0x6401, // 0: lui  r1, 1       r1 = 0x0040
        0x2485, // 1: addi r1, r1, 5   r1 = 0x0045
        0x287D, // 2: addi r2, r0, -3  r2 = 0xFFFD   (signed immediate)
        0x0C82, // 3: add  r3, r1, r2  r3 = 0x0042
        0x5081, // 4: nand r4, r1, r1  r4 = 0xFFBA
        0xC07F  // 5: beq  r0, r0, -1  self-loop halt
    }, 20);
    check("r0", c.reg(0), 0x0000);
    check("r1", c.reg(1), 0x0045);
    check("r2", c.reg(2), 0xFFFD);
    check("r3", c.reg(3), 0x0042);
    check("r4", c.reg(4), 0xFFBA);
    check("pc", c.pc(),   0x0005);
}

// ─────────────────────────────────────────────────────────────
//  Test 2 — LW/SW round trip (store -> load), signed offset, no aliasing
// ─────────────────────────────────────────────────────────────
static void test_lwsw() {
    printf("\n[test_lwsw] store/load round trip + signed offset\n");
    Cpu c("jpu_lwsw.vcd");
    c.run({
        0x2432, // 0: addi r1, r0, 50   r1 = 50
        0xA405, // 1: sw   r1, r0, 5     Mem[5] = 50
        0x8C05, // 2: lw   r3, r0, 5     r3 = Mem[5]
        0x300A, // 3: addi r4, r0, 10    r4 = 10
        0xA67D, // 4: sw   r1, r4, -3    Mem[7] = 50   (signed offset)
        0x967D, // 5: lw   r5, r4, -3    r5 = Mem[7]   (signed offset)
        0x3819, // 6: addi r6, r0, 25    r6 = 25
        0xB806, // 7: sw   r6, r0, 6     Mem[6] = 25
        0x9C06, // 8: lw   r7, r0, 6     r7 = Mem[6]   (distinct addr)
        0xC07F  // 9: beq  r0, r0, -1    self-loop halt
    }, 24);
    check("r1",   c.reg(1), 0x0032);
    check("r3",   c.reg(3), 0x0032);
    check("r4",   c.reg(4), 0x000A);
    check("r5",   c.reg(5), 0x0032);
    check("r6",   c.reg(6), 0x0019);
    check("r7",   c.reg(7), 0x0019);
    check("M[5]", c.mem(5), 0x0032);
    check("M[6]", c.mem(6), 0x0019);
    check("M[7]", c.mem(7), 0x0032);
    check("pc",   c.pc(),   0x0009);
}

// ─────────────────────────────────────────────────────────────
//  Test 3 — control flow: BEQ not-taken, BEQ taken (forward), JALR
// ─────────────────────────────────────────────────────────────
static void test_branch_jalr() {
    printf("\n[test_branch_jalr] BEQ not-taken/taken + JALR link & jump\n");
    Cpu c("jpu_branch.vcd");
    c.run({
        0x2401, // 0:  addi r1, r0, 1    r1 = 1
        0x2802, // 1:  addi r2, r0, 2    r2 = 2
        0xC502, // 2:  beq  r1, r2, 2    1!=2 -> NOT taken, fall through
        0x2C07, // 3:  addi r3, r0, 7    r3 = 7   (proves fall-through)
        0xC481, // 4:  beq  r1, r1, 1    1==1 -> taken, target = 6 (skip 5)
        0x2C41, // 5:  addi r3, r0, 33   SKIPPED (r3 stays 7)
        0x380A, // 6:  addi r6, r0, 10   r6 = 10  (JALR target addr)
        0xF700, // 7:  jalr r5, r6       r5 = PC+1 = 8; PC = r6 = 10
        0x3C37, // 8:  addi r7, r0, 55   SKIPPED (r7 stays 0)
        0x3C2C, // 9:  addi r7, r0, 44   SKIPPED
        0xC07F  // 10: beq  r0, r0, -1   self-loop halt at 10
    }, 24);
    check("r1", c.reg(1), 0x0001);
    check("r2", c.reg(2), 0x0002);
    check("r3", c.reg(3), 0x0007); // not 33: not-taken fell through, taken skipped 5
    check("r5", c.reg(5), 0x0008); // JALR link = PC+1
    check("r6", c.reg(6), 0x000A);
    check("r7", c.reg(7), 0x0000); // JALR jumped over 8 and 9
    check("pc", c.pc(),   0x000A); // landed at target, self-loop
}

// ─────────────────────────────────────────────────────────────
//  Test 4 — r0 is hardwired to 0 (writes to it are discarded)
// ─────────────────────────────────────────────────────────────
static void test_r0_hardwired() {
    printf("\n[test_r0_hardwired] writes to r0 must be ignored\n");
    Cpu c("jpu_r0.vcd");
    c.run({
        0x2005, // 0: addi r0, r0, 5   try to write 5 into r0
        0x2407, // 1: addi r1, r0, 7   r1 = r0 + 7 = 7  (proves r0 still 0)
        0x6003, // 2: lui  r0, 3        try to write via LUI
        0x0800, // 3: add  r2, r0, r0   r2 = 0 + 0 = 0   (proves r0 still 0)
        0xC07F  // 4: beq  r0, r0, -1   self-loop halt
    }, 16);
    check("r0", c.reg(0), 0x0000); // never written despite addi/lui targeting it
    check("r1", c.reg(1), 0x0007);
    check("r2", c.reg(2), 0x0000);
    check("pc", c.pc(),   0x0004);
}

// ─────────────────────────────────────────────────────────────
//  Test 5 — 16-bit arithmetic wraps modulo 2^16 (no overflow trap)
// ─────────────────────────────────────────────────────────────
static void test_overflow_wrap() {
    printf("\n[test_overflow_wrap] add past 0xFFFF wraps to 0\n");
    Cpu c("jpu_wrap.vcd");
    c.run({
        0x67FF, // 0: lui  r1, 0x3FF    r1 = 0x3FF << 6 = 0xFFC0
        0x24BF, // 1: addi r1, r1, 63    r1 = 0xFFC0 + 0x3F = 0xFFFF
        0x2881, // 2: addi r2, r1, 1     r2 = 0xFFFF + 1 = 0x0000  (wrap)
        0x2C82, // 3: addi r3, r1, 2     r3 = 0xFFFF + 2 = 0x0001  (wrap)
        0xC07F  // 4: beq  r0, r0, -1    self-loop halt
    }, 16);
    check("r1", c.reg(1), 0xFFFF);
    check("r2", c.reg(2), 0x0000); // wrapped
    check("r3", c.reg(3), 0x0001); // wrapped
    check("pc", c.pc(),   0x0004);
}

// ─────────────────────────────────────────────────────────────
//  Test 6 — a real loop: sum 1..5 = 15  (proves modules cooperate
//  over many cycles, with a backward branch driving iteration)
// ─────────────────────────────────────────────────────────────
static void test_loop_sum() {
    printf("\n[test_loop_sum] for(i=1; i<=5; i++) sum += i  ->  15\n");
    Cpu c("jpu_loop.vcd");
    c.run({
        0x3001, // 0: addi r4, r0, 1     step  = 1   (unused, doc)
        0x3406, // 1: addi r5, r0, 6     limit = N+1 = 6
        0x2401, // 2: addi r1, r0, 1     i     = 1
        0x2C00, // 3: addi r3, r0, 0     sum   = 0
        0x0D81, // 4: add  r3, r3, r1    sum  += i        <-- loop top
        0x2481, // 5: addi r1, r1, 1     i++
        0xC681, // 6: beq  r1, r5, 1     if i==6 -> goto 8 (exit)
        0xC07C, // 7: beq  r0, r0, -4    unconditional -> goto 4 (loop)
        0xC07F  // 8: beq  r0, r0, -1    self-loop halt
    }, 60);
    check("r1",  c.reg(1), 0x0006); // i stops at N+1
    check("r3",  c.reg(3), 0x000F); // 1+2+3+4+5 = 15
    check("r5",  c.reg(5), 0x0006);
    check("pc",  c.pc(),   0x0008);
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    for (int i = 1; i < argc; ++i)
        if (std::string(argv[i]) == "--trace") g_trace = true;
    if (g_trace) Verilated::traceEverOn(true);

    printf("==== JPU whole-CPU C++ testbench ====\n");
    test_arith();
    test_lwsw();
    test_branch_jalr();
    test_r0_hardwired();
    test_overflow_wrap();
    test_loop_sum();

    printf("\n==== %d/%d checks passed ====\n", g_checks - g_errors, g_checks);
    if (g_errors == 0) printf("ALL PASS\n");
    else               printf("%d FAILURE(S)\n", g_errors);
    return g_errors ? 1 : 0;
}
