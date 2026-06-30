// ============================================================
// imem.v  —  RiSC-16 Instruction Memory
// ============================================================
// Single-cycle, read-only, combinational fetch.
// Separate from data memory (memory.v) — Harvard-style split.
//
// Address space:
//   - 64 words × 16 bits  (fits a typical RiSC-16 test program)
//   - Change MEM_DEPTH to resize (must be power of two)
//   - All addresses are word-addresses (like the ISA specifies:
//     address 0 = bytes [1:0], address 1 = bytes [3:2], etc.)
//
// Loading programs:
//   - $readmemh loads a hex file at simulation time.
//   - For synthesis, replace with an FPGA block-RAM init or
//     hardcode instructions in the `initial` block.
//
// Interface matches the PC.v output:
//   pc [15:0] → imem → instr [15:0] → decoder.v
// ============================================================
 
module imem #(
    parameter MEM_DEPTH = 64,                    // number of 16-bit words
    parameter INIT_FILE = "program.hex"          // hex file loaded at sim time
)(
    input  wire [15:0] pc,                       // word-address from PC
    output wire [15:0] instr                     // 16-bit instruction to decoder
);
 
    // ── Storage ──────────────────────────────────────────────
    reg [15:0] mem [0:MEM_DEPTH-1] /* verilator public_flat_rw */; // public: C++ testbench loads programs here
 
    // ── Initialisation ───────────────────────────────────────
    integer i;
    initial begin
        // Zero-fill first so uninitialised words behave as NOP
        // (ADD r0,r0,r0  ==  16'h0000)
        for (i = 0; i < MEM_DEPTH; i = i + 1)
            mem[i] = 16'h0000;
 
        // Load program from hex file if it exists.
        // $readmemh silently skips missing files in most simulators;
        // remove or guard with `ifdef SIMULATION if needed.
        $readmemh(INIT_FILE, mem);
    end
 
    // ── Combinational read — purely asynchronous ──────────────
    // The ISA defines word-addresses, so pc indexes directly.
    // Programs must stay within MEM_DEPTH; out-of-range PC is
    // the programmer's responsibility, not guarded here.
    assign instr = mem[pc];
 
endmodule
