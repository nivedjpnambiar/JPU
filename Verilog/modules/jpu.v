// ============================================================
// jpu.v  —  RiSC-16 Single-Cycle CPU  (top-level integration)
// ============================================================
// Wires together the ten leaf modules into one single-cycle
// datapath.  This module contains NO logic of its own — every
// signal that crosses a module boundary is a wire declared here,
// and the work happens inside the instantiated modules.
//
// Sequential (clocked) state lives in exactly three places:
//   - CU.v            : the architectural PC register
//   - RegisterFile.v  : the register write
//   - memory.v        : the data-memory write
// Everything else is combinational and settles within one cycle.
//
// Dataflow:
//   CU.pc -> imem -> decoder -> RegisterFile -> ALU/load/store/PC
//         -> regw -> RegisterFile (write-back)
//   PC.out / pc_update -> CU (next-PC decision)
// ============================================================

module jpu #(
    parameter INIT_FILE = "program.hex"   // forwarded to imem
)(
    input  wire        clk,
    input  wire        rst,
    output wire [15:0] pc_out             // current PC, for observation/test
);

    // ── Program counter (CU owns the register) ───────────────
    wire [15:0] pc;
    assign pc_out = pc;

    // ── Instruction fetch ────────────────────────────────────
    wire [15:0] instr;

    // ── Decoder outputs ──────────────────────────────────────
    wire [2:0]  rs, rt;
    wire [2:0]  reg_operand;
    wire        reg_write;
    wire [15:0] imm7;          // sign-extended in decoder
    wire [9:0]  imm10;
    wire [1:0]  alu_op;
    wire        mem_write_en;
    wire        load_op;
    wire [1:0]  mux_control;
    wire        pc_op;
    wire        branch_jump;

    // ── Register file read ports ─────────────────────────────
    wire [15:0] read_a;        // port A (regC / regA depending on instr)
    wire [15:0] read_b;        // port B (regB)

    // ── Execute-stage outputs ────────────────────────────────
    wire [15:0] alu_a;         // ALU result
    wire [15:0] load_out;      // LUI value (LUI) OR LW address (LW)
    wire [15:0] store_addr;
    wire [15:0] store_data;
    wire [15:0] mem_read_out;  // LW data from memory

    // ── PC / branch-target calculator outputs ────────────────
    wire [15:0] pc_target;     // PC.v `out`
    wire        pc_update;
    wire [15:0] ret_addr;      // PC+1 (JALR link)

    // ── Write-back ───────────────────────────────────────────
    wire [15:0] regw_out;
    wire [2:0]  reg_operand_out;  // pass-through of reg_operand (unused: we
                                  // drive the regfile from decoder directly)

    // =========================================================
    //  Module instances
    // =========================================================

    // Program-counter register + next-PC decision.
    CU u_cu (
        .clk         (clk),
        .rst         (rst),
        .branch_jump (branch_jump),
        .pc_update   (pc_update),
        .pc_target   (pc_target),
        .pc          (pc)
    );

    // Instruction memory (combinational fetch).
    imem #(.INIT_FILE(INIT_FILE)) u_imem (
        .pc    (pc),
        .instr (instr)
    );

    // Instruction decode.
    decoder u_decoder (
        .instr        (instr),
        .rs           (rs),
        .rt           (rt),
        .reg_operand  (reg_operand),
        .reg_write    (reg_write),
        .imm7         (imm7),
        .imm10        (imm10),
        .alu_op       (alu_op),
        .mem_write_en (mem_write_en),
        .load_op      (load_op),
        .mux_control  (mux_control),
        .pc_op        (pc_op),
        .branch_jump  (branch_jump)
    );

    // Register file (async read, sync write, R0 hardwired 0).
    RegisterFile u_regfile (
        .clk        (clk),
        .rs         (rs),
        .rt         (rt),
        .reg_op     (reg_operand),     // write destination (decoder)
        .write_data (regw_out),        // write-back data
        .reg_write  (reg_write),       // write enable
        .read_a     (read_a),
        .read_b     (read_b)
    );

    // ALU: ADD (c+b) / ADDI (b+imm) / NAND (~(c&b)).
    //   b = regB (read_b), c = regC (read_a for RRR), imm = sign-extended imm7.
    ALU u_alu (
        .b      (read_b),
        .c      (read_a),
        .imm    (imm7),
        .alu_op (alu_op),
        .a      (alu_a)
    );

    // Load unit: LUI value (load_op=0) OR LW address rB+imm7 (load_op=1).
    //   load_out feeds BOTH regw.lui_load and memory.mem_read_addr; which one
    //   is meaningful is selected by the active instruction's control signals.
    load u_load (
        .a       (read_a),
        .b       (read_b),
        .imm7    (imm7),
        .imm10   (imm10),
        .load_op (load_op),
        .out     (load_out)
    );

    // Store unit: addr = rB + imm7, data = rA.
    store u_store (
        .a    (read_a),
        .b    (read_b),
        .imm  (imm7),
        .addr (store_addr),
        .data (store_data)
    );

    // Data memory: async read (LW), sync write (SW).
    //   Read address = load_out (the LW address path; see design notes).
    memory u_memory (
        .clk            (clk),
        .mem_read_addr  (load_out),
        .mem_write_en   (mem_write_en),
        .mem_write_addr (store_addr),
        .mem_write_data (store_data),
        .mem_read_out   (mem_read_out)
    );

    // Branch-target calculator (BEQ / JALR). No storage — feeds CU.
    //   a = regA (read_a), b = regB (read_b) for the rA==rB compare / JALR target.
    PC u_pc (
        .a         (read_a),
        .b         (read_b),
        .pc        (pc),
        .pc_op     (pc_op),
        .imm       (imm7),
        .out       (pc_target),
        .pc_update (pc_update),
        .ret_addr  (ret_addr)
    );

    // Write-back source mux (00=ALU, 01=LUI, 10=LW data, 11=PC+1).
    regw u_regw (
        .mux_control     (mux_control),
        .reg_operand     (reg_operand),
        .alu_out         (alu_a),
        .lui_load        (load_out),
        .lw_load         (mem_read_out),
        .pc_ret_addr     (ret_addr),
        .regw_out        (regw_out),
        .reg_operand_out (reg_operand_out)
    );

endmodule
