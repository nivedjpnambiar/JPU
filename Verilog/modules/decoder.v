// ============================================================
// decoder.v  —  RiSC-16 Single-Cycle Instruction Decoder
// ============================================================
// Instruction formats:
//   RRR-type  [15:13]=opcode [12:10]=regA [9:7]=regB [6:3]=0 [2:0]=regC
//   RRI-type  [15:13]=opcode [12:10]=regA [9:7]=regB [6:0]=imm7 (signed)
//   RI-type   [15:13]=opcode [12:10]=regA [9:0]=imm10
//
// Opcodes (3-bit):
//   000 = ADD   (RRR)
//   001 = ADDI  (RRI)
//   010 = NAND  (RRR)
//   011 = LUI   (RI)
//   100 = LW    (RRI)
//   101 = SW    (RRI)
//   110 = BEQ   (RRI)
//   111 = JALR  (RRI — regB only, imm must be 0 for normal JALR)
//
// Control signal conventions (must match existing modules):
//
//   alu_op [1:0]   — to ALU.v
//     2'b00 = ADD  (c + b)
//     2'b01 = ADDI (b + imm)
//     2'b10 = NAND (~(c & b))
//
//   mux_control [1:0]  — to regw.v (write-back source)
//     2'b00 = ALU output  (ADD, ADDI, NAND)
//     2'b01 = LUI output  (from load.v)
//     2'b10 = LW data     (from memory)
//     2'b11 = PC+1        (JALR return address)
//
//   pc_op [0]  — to PC.v
//     1'b0 = BEQ
//     1'b1 = JALR
//
//   load_op [0]  — to load.v
//     1'b0 = LUI
//     1'b1 = LW address  (regB + imm → memory)
//
// ============================================================

module decoder (
    input  wire [15:0] instr,          // 16-bit instruction word from memory

    // ── Register file read ports ──────────────────────────────
    output wire [2:0]  rs,             // read port A  (muxed: regC/regA/regB)
    output wire [2:0]  rt,             // read port B  → regB field  [9:7]

    // ── Register file write-back ──────────────────────────────
    output reg  [2:0]  reg_operand,    // dest register (→ regw.v / RegisterFile)
    output reg         reg_write,      // 1 = write result back to register file

    // ── Immediate values ──────────────────────────────────────
    output wire [15:0] imm7,           // 7-bit signed immediate (RRI-type), sign-extended to 16 bits
    output wire [9:0]  imm10,          // 10-bit immediate (RI-type, LUI)

    // ── ALU control ───────────────────────────────────────────
    output reg  [1:0]  alu_op,         // → ALU.v

    // ── Load/store control ────────────────────────────────────
    output reg         mem_write_en,   // → memory.v  (1 = SW)
    output reg         load_op,        // → load.v    (0=LUI, 1=LW)

    // ── Write-back mux ────────────────────────────────────────
    output reg  [1:0]  mux_control,    // → regw.v

    // ── PC control ────────────────────────────────────────────
    output reg         pc_op,          // → PC.v  (0=BEQ, 1=JALR)
    output reg         branch_jump     // 1 = this instruction may alter PC
);

    // ── Field extraction ─────────────────────────────────────
    wire [2:0] opcode = instr[15:13];
    wire [2:0] regA   = instr[12:10];
    wire [2:0] regB   = instr[9:7];
    wire [2:0] regC   = instr[2:0];    // RRR-type only

    // ── Register read port selection ─────────────────────────
    // Port B always carries the regB source.
    assign rt = regB;

    // Port A depends on the instruction:
    //   ADD/NAND  → regC (third operand: rA = rB op rC)
    //   SW/BEQ    → regA (data to store / first compare operand)
    //   else      → regB (don't-care for LUI/JALR, harmless default)
    assign rs = (opcode == 3'b000 || opcode == 3'b010) ? regC :  // ADD, NAND
                (opcode == 3'b101 || opcode == 3'b110) ? regA :  // SW, BEQ
                                                         regB;

    // ── Immediates wired directly from instruction bits ──────
    assign imm7  = {{9{instr[6]}}, instr[6:0]};  // 7-bit signed immediate (RRI-type) sign-extended to 16 bits
    assign imm10 = instr[9:0];         // 10-bit immediate (RI-type)

    // ── Combinational decode ──────────────────────────────────
    always @* begin
        // Safe defaults — prevent latch inference
        reg_operand  = 3'b000;
        reg_write    = 1'b0;
        alu_op       = 2'b00;
        mem_write_en = 1'b0;
        load_op      = 1'b0;
        mux_control  = 2'b00;
        pc_op        = 1'b0;
        branch_jump  = 1'b0;

        case (opcode)

            3'b000: begin   // ── ADD  rA, rB, rC  →  rA = rB + rC ──────────
                alu_op      = 2'b00;   // ADD
                mux_control = 2'b00;   // write-back from ALU
                reg_operand = regA;
                reg_write   = 1'b1;
            end

            3'b001: begin   // ── ADDI  rA, rB, imm  →  rA = rB + imm7 ──────
                alu_op      = 2'b01;   // ADDI
                mux_control = 2'b00;   // write-back from ALU
                reg_operand = regA;
                reg_write   = 1'b1;
            end

            3'b010: begin   // ── NAND  rA, rB, rC  →  rA = ~(rB & rC) ──────
                alu_op      = 2'b10;   // NAND
                mux_control = 2'b00;   // write-back from ALU
                reg_operand = regA;
                reg_write   = 1'b1;
            end

            3'b011: begin   // ── LUI  rA, imm10  →  rA = {imm10, 6'b0} ─────
                load_op     = 1'b0;    // LUI path in load.v
                mux_control = 2'b01;   // write-back from LOAD (lui_load)
                reg_operand = regA;
                reg_write   = 1'b1;
            end

            3'b100: begin   // ── LW  rA, rB, imm  →  rA = Mem[rB + imm7] ──
                alu_op      = 2'b01;   // use ALU add for address (rB + imm)
                load_op     = 1'b1;    // LW path in load.v
                mux_control = 2'b10;   // write-back from memory (lw_load)
                reg_operand = regA;
                reg_write   = 1'b1;
            end

            3'b101: begin   // ── SW  rA, rB, imm  →  Mem[rB + imm7] = rA ──
                // address = rB + imm7 (handled in store.v: addr = b + imm)
                // data    = rA        (store.v: data = a)
                mem_write_en = 1'b1;
                reg_write    = 1'b0;   // SW does NOT write back to reg file
            end

            3'b110: begin   // ── BEQ  rA, rB, imm  →  if rA==rB: PC=PC+1+imm
                pc_op       = 1'b0;    // BEQ mode in PC.v
                branch_jump = 1'b1;    // tell CU to evaluate pc_update
                reg_write   = 1'b0;
            end

            3'b111: begin   // ── JALR  rA, rB  →  PC=rB, rA=PC+1 ───────────
                // Note: JALR with non-zero imm7 = syscall/halt (ISA §4)
                // For normal JALR: imm7 must be zero
                pc_op       = 1'b1;    // JALR mode in PC.v
                branch_jump = 1'b1;
                mux_control = 2'b11;   // write-back PC+1 (ret_addr from PC.v)
                reg_operand = regA;
                reg_write   = 1'b1;    // rA <- PC+1
            end

            default: begin  // undefined opcode — all disabled, safe state
                reg_write    = 1'b0;
                mem_write_en = 1'b0;
                branch_jump  = 1'b0;
            end

        endcase
    end

endmodule
