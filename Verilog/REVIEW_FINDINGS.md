# JPU RiSC-16 Verilog — Comprehensive Signal Flow & Bug Review
*Systematic analysis vs. ISA spec, 2026-06-17*

## Summary
The modular building blocks are mostly correct in isolation, but **critical bugs prevent correct execution**: missing sign-extension, compile errors, design ambiguities in address routing, and missing latch-inference safeguards. This document traces signal flow, identifies each issue, and proposes fixes.

---

## 1. CRITICAL BUG: Missing Signed Immediate Extension

**Issue:** Immediates in RiSC-16 are **signed** (7-bit in RRI format: -64 to +63). The decoder extracts `imm7 = instr[6:0]` as a plain 7-bit wire with NO sign-extension. When this wire is used in 16-bit arithmetic, Verilog zero-extends it, treating negative immediates as large unsigned values.

**Affected instructions:** ADDI, LW, SW, BEQ (any instruction using imm7).

**Example:** `addi r1, r2, -5`
- Instruction bits: opcode=001, regA=001, regB=010, imm7=0111011 (binary -5 in 7-bit two's complement)
- decoder.v extracts: `imm7 = instr[6:0] = 7'b0111011 = 7'd59` (as unsigned 7-bit)
- ALU receives: `alu_op=01, b=r2_value, imm=59`
- ALU computes: `a = b + 59` (WRONG — should be `b + (-5)` = `b - 5`)
- Similar errors in PC.v BEQ calculation, load.v LW address, store.v SW address.

**Affected modules:**
- `decoder.v` — must sign-extend imm7 from 7→16 bits in its output
- `ALU.v` — receives sign-extended imm from decoder, no change needed (but remove the deceitful comment "ADDI: add immediate" that lies about what the immediate value is)
- `load.v` — receives sign-extended imm from decoder
- `store.v` — receives sign-extended imm from decoder
- `PC.v` — receives sign-extended imm from decoder

**Fix:** In decoder.v, change `assign imm7 = instr[6:0];` to `assign imm7 = {{9{instr[6]}}, instr[6:0]};` to sign-extend to 16 bits. All downstream consumers can then safely use it as a 16-bit signed value.

---

## 2. COMPILE ERROR: Output Type Mismatch in PC.v

**Issue:** PC.v declares outputs `out` and `pc_update` as plain `output` (which are wires), but assigns them inside an `always @*` block. Verilog requires `output reg` for procedural assignment.

**Code (PC.v, lines 8-10):**
```verilog
output [15:0] out,       // these are wire by default
output        pc_update, // but assigned inside always @*
output [15:0] ret_addr   // this one is fine (assigned with assign)
```

**Fix:** Change to `output reg [15:0] out;` and `output reg pc_update;`.

---

## 3. COMPILE ERROR: Output Type Mismatch in load.v

**Issue:** load.v declares `out` as plain `output`, but assigns it inside an `always @*` block.

**Code (load.v, line 6):**
```verilog
output [15:0] out  // wire by default, but assigned inside always @*
```

**Fix:** Change to `output reg [15:0] out;`.

---

## 4. COMPILE ERROR: Output Type Mismatch in memory.v

**Issue:** memory.v declares `mem_read_out` as `output reg`, but drives it with a continuous `assign` statement (line 21). Verilog requires `wire` for combinational assignment.

**Code (memory.v, lines 9, 21):**
```verilog
output reg  [15:0]  mem_read_out   // declared as reg
...
assign mem_read_out = mems[mem_read_addr]; // driven by assign
```

**Fix:** Change to `output wire [15:0] mem_read_out;`.

---

## 5. INCOMPLETE: Missing Default Case in load.v

**Issue:** load.v's `case` statement only handles `load_op == 0` (LUI) and `load_op == 1` (LW). If `load_op` is ever X or undefined, `out` will infer a latch.

**Code (load.v, lines 9–13):**
```verilog
always @* begin
    case (load_op) 
        1'b0: out = {imm, 6'b000000};
        1'b1: out = imm + b ;
        // no default → latch inference if load_op is X
    endcase
end
```

**Fix:** Add `default: out = 16'h0000;` after the case statement.

---

## 6. DESIGN AMBIGUITY: Duplicate LW Address Calculation

**Issue:** For LW (opcode 100), the decoder simultaneously enables:
- `alu_op = 2'b01` (ADDI mode: ALU computes `a = b + imm`)
- `load_op = 1'b1` (LW mode: load.v computes `out = imm + b`)

Both modules compute the address `rB + imm7`. In the integrated CPU, **which one supplies the address to memory's read port?** The design is unclear.

**Possible resolution:**
- Option A: Use only ALU's output for all address generation (LW + SW). Then load.v is used only for LUI.
- Option B: Use load.v's output for LW addressing. Then ALU's `alu_op=01` for LW is wasteful/unused.
- Option C: Pipeline or multiplex the address somehow (unlikely for single-cycle).

**Current status:** Unknown. The top-level integration (`jpu.v`) will clarify this, but the design should document it.

---

## 7. DESIGN AMBIGUITY: load.v Immediate Width Mismatch

**Issue:** decoder.v outputs `imm7 [6:0]` and `imm10 [9:0]`. The load.v module's input is declared as `[9:0] imm`:

```verilog
module load (
    input  [9:0]  imm,  // always 10-bit
    input         load_op,
    output [15:0] out
);
    case (load_op)
        1'b0: out = {imm, 6'b000000}; // LUI: imm10 << 6 (correct)
        1'b1: out = imm + b ;         // LW: rB + imm7, but imm is 10-bit!
    endcase
end
```

For LUI, `imm10` (10 bits) is the right input.
For LW, the immediate should be a **signed 7-bit** value (imm7), but load.v expects 10-bit.

**Current status:** The top-level integration must route either `imm7` (zero-extended or sign-extended to 10-bit) or `imm10` to load.v. This mismatch must be resolved at integration time, but it's a potential source of errors.

---

## 8. REGISTER FILE: Write Protection Correct

**Module:** registers.v (RegisterFile)
- Correctly protects R0: `if (reg_write && reg_op != 3'b000)`
- Async dual-port reads, sync write ✓
- All 8 registers initialized to 0 ✓

**Status:** No issues found.

---

## 9. ALU: Arithmetic Correctness (with sign-ext caveat)

**Module:** ALU.v
- ADD (alu_op=00): `a = c + b` ✓
- ADDI (alu_op=01): `a = b + imm` ✓ (but imm must be sign-extended from decoder)
- NAND (alu_op=10): `a = ~(c & b)` ✓
- Default case prevents latch inference ✓

**Status:** Correct in principle; depends on sign-extended imm from decoder.

---

## 10. DECODER: Instruction Decoding Logic (Correct, but incomplete integration)

**Opcode table verification vs. ISA:**
| Op   | Mnemonic | Decoder logic                               | ISA compliance |
|------|----------|---------------------------------------------|-----------------|
| 000  | ADD      | alu_op=00, mux=00, rw=1, regA←ALU         | ✓ Correct       |
| 001  | ADDI     | alu_op=01, mux=00, rw=1, regA←ALU         | ✓ Correct       |
| 010  | NAND     | alu_op=10, mux=00, rw=1, regA←ALU         | ✓ Correct       |
| 011  | LUI      | load_op=0, mux=01, rw=1, regA←LUI         | ✓ Correct       |
| 100  | LW       | alu_op=01, load_op=1, mux=10, rw=1, regA←Mem | ✓ Correct       |
| 101  | SW       | mem_write_en=1, rw=0                      | ✓ Correct       |
| 110  | BEQ      | pc_op=0, branch_jump=1, rw=0              | ✓ Correct       |
| 111  | JALR     | pc_op=1, branch_jump=1, mux=11, rw=1, regA←PC+1 | ✓ Correct |

**Register read port selection verification:**
- ADD/NAND: rs=regC, rt=regB → reads rB, rC ✓
- ADDI: rs=regB, rt=regB → reads rB ✓
- LUI: rs=regB, rt=regB → harmless (imm is used, not operands) ✓
- LW: rs=regB, rt=regB → reads rB (for addr calc) ✓
- SW: rs=regA, rt=regB → reads rA (data), rB (addr base) ✓
- BEQ: rs=regA, rt=regB → reads rA, rB (for comparison) ✓
- JALR: rs=regB, rt=regB → reads rB (for PC target) ✓

**Status:** All decode logic is correct and matches the ISA. The misleading comment on imm7 ("sign-extended") should be fixed to say "7-bit signed (requires sign-extension)".

---

## 11. PC MODULE: Branch Logic Correctness (with sign-ext caveat)

**Module:** PC.v

```verilog
assign ret_addr = pc + 16'd1;  // PC+1 for JALR ✓

wire eq;
assign eq = (a == b);          // Equality check ✓

always @* begin
    out       = 16'd0;
    pc_update = 1'b0;
    case (pc_op)
        1'b0: begin // BEQ
            if (eq) begin
                out       = pc + 16'd1 + imm;  // PC+1+imm (depends on signed imm)
                pc_update = 1'b1;
            end
        end
        1'b1: begin // JALR
            out       = b;  // Branch to rB ✓
            pc_update = 1'b1;
        end
    endcase
end
```

**Issues:**
- BEQ target calculation depends on sign-extended imm (see bug #1).
- `out` and `pc_update` must be `output reg` (see error #2).

**Status:** Logic is correct once sign-extension is fixed and output types are corrected.

---

## 12. STORE MODULE: Address and Data Routing Correct

**Module:** store.v
```verilog
assign addr = b + imm;  // addr = rB + imm7 ✓
assign data = a;        // data = rA ✓
```

**Status:** Correct (depends on sign-extended imm from decoder).

---

## 13. MEMORY MODULE: Async Read, Sync Write (but output type error)

**Module:** memory.v
- Combinational read via `assign mem_read_out = mems[mem_read_addr];` ✓
- Synchronous write on posedge clk ✓
- 16-word depth (no out-of-range guard, per user preference) ✓
- All memory initialized to 0 ✓

**Issue:** `mem_read_out` declared as `output reg` but driven by `assign` (see error #4).

**Status:** Correct once output type is fixed.

---

## 14. REGISTER WRITE MULTIPLEXER: Source Selection Correct

**Module:** regw.v
```verilog
case (mux_control)
    2'b00: regw_out = alu_out;      // ADD, ADDI, NAND ✓
    2'b01: regw_out = lui_load;     // LUI ✓
    2'b10: regw_out = lw_load;      // LW (from memory) ✓
    2'b11: regw_out = pc_ret_addr;  // JALR (PC+1) ✓
endcase
```

**Status:** Logic is correct. Assumes mux_control is always valid (no default case, but all 4 cases are defined, so no latch risk).

---

## 15. INSTRUCTION MEMORY: Combinational Read, No Guard (User Preference)

**Module:** instr_mem.v
- Removed masking per user decision (2026-06-17): `assign instr = mem[pc];`
- Programmer responsible for keeping PC within 64-word range ✓

**Status:** Correct per specification.

---

## 16. IMMEDIATE ROUTING IN TOP LEVEL: UNRESOLVED

The decoder outputs:
- `imm7 [6:0]` — used by ADDI/LW/SW/BEQ
- `imm10 [9:0]` — used by LUI

But downstream modules expect:
- ALU: `[6:0] imm` (or 16-bit if sign-extended)
- load.v: `[9:0] imm` (but LW path needs 7-bit signed)
- store.v: `[6:0] imm` (or 16-bit if sign-extended)
- PC: `[6:0] imm` (or 16-bit if sign-extended)

**Current status:** The top-level `jpu.v` must wire these correctly, including sign-extension of imm7 to 16 bits. This is not yet implemented.

---

## 17. CONTROL UNIT: MISSING ENTIRELY

**Module:** CU.v is empty (just a comment).

The control unit should:
- Decide whether to update PC with the branch/jump target or with default PC+1
- Hold the next PC value during synchronous write
- Coordinate between decoder's `branch_jump` / `pc_update` signals and the actual PC register

**Status:** Critical missing piece. No integration yet.

---

## Signal Flow: Expected Datapath (Single-Cycle)

Assuming standard single-cycle RiSC-16 design:
1. **Fetch:** `PC → imem.pc → imem.instr`
2. **Decode:** `instr → decoder.instr` → extract opcode, regA/B/C, immediates
3. **Reg Read:** `decoder.rs/rt → regfile → read_a (regA or regC), read_b (regB)`
4. **Immediate:** `decoder.imm7 → sign-extend to 16-bit → ALU/load/store/PC`
5. **Execute (varies by opcode):**
   - **ADD/ADDI/NAND:** ALU computes result
   - **LUI:** load.v computes (imm10<<6)
   - **LW:** ALU/load.v computes address, memory reads data
   - **SW:** store.v computes address & data, memory writes
   - **BEQ:** PC.v evaluates equality, computes target
   - **JALR:** PC.v sets target to regB
6. **Write-Back:** `regw mux selects source → regfile.write_data`
7. **PC Update:** `CU selects (PC+1 vs. branch target) → PC register`

**Currently missing:** CU, sign-extension, proper top-level wiring.

---

## Summary of Issues by Severity

### CRITICAL (prevent correct execution)
1. ✗ Sign-extension of imm7 (affects ADDI, LW, SW, BEQ)
2. ✗ CU.v missing entirely
3. ✗ No top-level integration in jpu.v

### HIGH (compile errors / won't synthesize)
4. ✗ PC.v: `out`, `pc_update` must be `output reg`
5. ✗ load.v: `out` must be `output reg`
6. ✗ memory.v: `mem_read_out` must be `output wire`

### MEDIUM (design ambiguities / functional issues)
7. ~ LW address routing (ALU vs. load.v, unclear which is used)
8. ~ load.v immediate width mismatch (receives 10-bit, LW path needs 7-bit signed)
9. ✗ load.v missing default case (latch inference risk)

### LOW (documentation / clarity)
10. ~ decoder.v imm7 comment is misleading ("sign-extended" but it's not)

---

## Recommended Fix Order

1. **Fix sign-extension in decoder.v** — prerequisite for all downstream correctness
2. **Fix output types** (PC.v, load.v, memory.v) — prerequisite for synthesis
3. **Add default case to load.v** — safety
4. **Implement CU.v** — prerequisite for integration
5. **Wire up jpu.v properly** — integrate all blocks
6. **Resolve design ambiguity on LW address routing** — clarify ALU vs. load.v usage
7. **Add integration testbench** — verify end-to-end correctness
