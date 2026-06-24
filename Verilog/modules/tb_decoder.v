module tb_decoder;
    reg  [15:0] instr;
    wire [2:0]  rs, rt, reg_operand;
    wire        reg_write, mem_write_en, load_op, pc_op, branch_jump;
    wire [1:0]  alu_op, mux_control;
    wire [15:0] imm7;   // sign-extended to 16 bits
    wire [9:0]  imm10;

    decoder dut (
        .instr(instr), .rs(rs), .rt(rt), .reg_operand(reg_operand),
        .reg_write(reg_write), .imm7(imm7), .imm10(imm10),
        .alu_op(alu_op), .mem_write_en(mem_write_en), .load_op(load_op),
        .mux_control(mux_control), .pc_op(pc_op), .branch_jump(branch_jump)
    );

    integer fails = 0;

    // check the signals that distinguish each opcode
    task check (
        input [127:0] name,
        input [15:0]  i,
        input [1:0]   e_alu, e_mux,
        input         e_lop, e_mwe, e_rw, e_pcop, e_bj,
        input [2:0]   e_rs, e_rt, e_ro
    );
    begin
        instr = i; #1;
        if (alu_op===e_alu && mux_control===e_mux && load_op===e_lop &&
            mem_write_en===e_mwe && reg_write===e_rw && pc_op===e_pcop &&
            branch_jump===e_bj && rs===e_rs && rt===e_rt && reg_operand===e_ro)
            $display("PASS  %0s", name);
        else begin
            fails = fails + 1;
            $display("FAIL  %0s", name);
            $display("      got alu=%b mux=%b lop=%b mwe=%b rw=%b pcop=%b bj=%b rs=%0d rt=%0d ro=%0d",
                     alu_op, mux_control, load_op, mem_write_en, reg_write,
                     pc_op, branch_jump, rs, rt, reg_operand);
        end
    end
    endtask

    initial begin
        //                       instr                       alu  mux  lop mwe rw pcop bj  rs rt ro
        check("ADD  r3,r1,r2", 16'b000_011_001_0000_010,     2'b00,2'b00, 0,  0, 1,  0,  0,  2, 1, 3);
        check("ADDI r3,r1,5",  16'b001_011_001_0000101,      2'b01,2'b00, 0,  0, 1,  0,  0,  1, 1, 3);
        check("NAND r4,r5,r6", 16'b010_100_101_0000_110,     2'b10,2'b00, 0,  0, 1,  0,  0,  6, 5, 4);
        check("LUI  r2,0x3FF", 16'b011_010_1111111111,       2'b00,2'b01, 0,  0, 1,  0,  0,  7, 7, 2);
        check("LW   r1,r2,4",  16'b100_001_010_0000100,       2'b01,2'b10, 1,  0, 1,  0,  0,  2, 2, 1);
        check("SW   r1,r2,4",  16'b101_001_010_0000100,       2'b00,2'b00, 0,  1, 0,  0,  0,  1, 2, 0);
        check("BEQ  r1,r2,3",  16'b110_001_010_0000011,       2'b00,2'b00, 0,  0, 0,  0,  1,  1, 2, 0);
        check("JALR r1,r2",    16'b111_001_010_0000000,       2'b00,2'b11, 0,  0, 1,  1,  1,  2, 2, 1);

        if (fails == 0) $display("\nAll decoder tests passed.");
        else            $display("\n%0d test(s) failed.", fails);
        $finish;
    end
endmodule
