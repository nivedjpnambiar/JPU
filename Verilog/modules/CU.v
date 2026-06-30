// ============================================================
// CU.v  —  RiSC-16 Control Unit / Program-Counter register
// ============================================================
// This module owns the architectural Program Counter.
//
// Despite its name, PC.v is only the *branch-target calculator*:
// it combinationally computes a candidate target (`out`) and a
// `pc_update` flag from the current pc, the register operands,
// and the immediate.  PC.v has no memory.  CU.v is where the
// actual PC register lives and where the next-PC decision is made.
//
// Next-PC selection each cycle:
//   reset            → pc <= 0
//   branch taken     → pc <= pc_target          (from PC.v `out`)
//   otherwise        → pc <= pc + 1             (default increment)
//
// IMPORTANT — why `branch_jump` gates `pc_update`:
//   PC.v defaults to BEQ mode (pc_op = 0) and raises `pc_update`
//   whenever its two operand inputs are equal.  For a NON-branch
//   instruction (e.g. ADD) the decoder still drives PC.v's operand
//   ports, so if those two source registers happen to hold equal
//   values, PC.v would raise `pc_update` and we'd branch by
//   accident.  The decoder therefore emits `branch_jump` = 1 only
//   for real BEQ/JALR instructions.  The CU takes the branch only
//   when BOTH are asserted:
//
//       take_branch = branch_jump & pc_update
//
// Interface:
//   CU.pc → imem.pc  and  → PC.v.pc
//   PC.v.out       → CU.pc_target
//   PC.v.pc_update → CU.pc_update
//   decoder.branch_jump → CU.branch_jump
// ============================================================


module CU (
    input  wire        clk,
    input  wire        rst,          // synchronous reset → pc = 0

    // ── From decoder ─────────────────────────────────────────
    input  wire        branch_jump,  // 1 = this instr may alter PC (BEQ/JALR)

    // ── From PC.v (branch-target calculator) ─────────────────
    input  wire        pc_update,    // 1 = PC.v says "take the branch/jump"
    input  wire [15:0] pc_target,    // branch / JALR target (PC.v `out`)

    // ── Program counter output ───────────────────────────────
    output reg  [15:0] pc            // current PC → imem.pc and PC.v.pc
);

    // Take the branch only when the decoder confirms this is a
    // branch/jump instruction AND PC.v says the condition is met.
    wire take_branch = branch_jump & pc_update;

    // Sim-time init so pc is never X before the first reset.
    initial pc = 16'd0;

    // ── Sequential PC register ───────────────────────────────
    always @(posedge clk) begin
        if (rst)
            pc <= 16'd0;
        else if (take_branch)
            pc <= pc_target;     // redirect to branch / JALR target
        else
            pc <= pc + 16'd1;    // default increment
    end

endmodule
