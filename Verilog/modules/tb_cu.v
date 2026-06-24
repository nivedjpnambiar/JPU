// Self-checking testbench for CU.v (PC register + next-PC selection)
module tb_cu;
    reg         clk, rst, branch_jump, pc_update;
    reg  [15:0] pc_target;
    wire [15:0] pc;
    integer fails = 0;

    CU dut (
        .clk(clk), .rst(rst),
        .branch_jump(branch_jump),
        .pc_update(pc_update), .pc_target(pc_target),
        .pc(pc)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // Drive inputs at negedge, advance across exactly ONE posedge, then check.
    task step (input [127:0] name, input bj, pu, input [15:0] tgt, input [15:0] exp);
    begin
        @(negedge clk);
        branch_jump = bj; pc_update = pu; pc_target = tgt;
        @(posedge clk); #1;             // exactly one PC update
        if (pc === exp)
            $display("PASS  %0s  pc=%0d", name, pc);
        else begin
            fails = fails + 1;
            $display("FAIL  %0s  got pc=%0d expected %0d", name, pc, exp);
        end
    end
    endtask

    initial begin
        // Synchronous reset
        rst = 1; branch_jump = 0; pc_update = 0; pc_target = 0;
        @(posedge clk); #1;
        if (pc !== 16'd0) begin fails=fails+1; $display("FAIL reset pc=%0d",pc); end
        else $display("PASS  reset  pc=0");
        rst = 0;   // deassert between this posedge and the next negedge (no free increment)

        // default increment 0→1→2→3
        step("inc 0->1", 0, 0, 16'hDEAD, 16'd1);
        step("inc 1->2", 0, 0, 16'hDEAD, 16'd2);
        step("inc 2->3", 0, 0, 16'hDEAD, 16'd3);

        // BEQ taken: branch_jump=1, pc_update=1 → jump to target
        step("beq taken ->100", 1, 1, 16'd100, 16'd100);
        // continue incrementing from 100
        step("inc 100->101", 0, 0, 16'd0, 16'd101);

        // BEQ not taken: branch_jump=1, pc_update=0 → just increment
        step("beq not-taken", 1, 0, 16'd500, 16'd102);

        // JALR: branch_jump=1, pc_update=1 → jump to target (rB value)
        step("jalr ->42", 1, 1, 16'd42, 16'd42);

        // CRITICAL GUARD: non-branch instr (branch_jump=0) but pc_update=1
        // (PC.v spuriously asserting because operands equal). Must NOT branch.
        step("guard: pu=1 bj=0", 0, 1, 16'd999, 16'd43);

        // mid-stream reset
        @(negedge clk); rst = 1;
        @(posedge clk); #1;
        if (pc !== 16'd0) begin fails=fails+1; $display("FAIL mid-reset pc=%0d",pc); end
        else $display("PASS  mid-reset pc=0");

        if (fails == 0) $display("\nAll CU tests passed.");
        else            $display("\n%0d CU test(s) failed.", fails);
        $finish;
    end
endmodule
