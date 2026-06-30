module tb_imem;
    reg  [15:0] pc;
    wire [15:0] instr;
    integer fails = 0;

    imem #(.MEM_DEPTH(64), .INIT_FILE("")) dut (.pc(pc), .instr(instr));

    task check (input [127:0] name, input [15:0] addr, exp);
    begin
        pc = addr; #1;
        if (instr === exp)
            $display("PASS  %0s  (instr=%h)", name, instr);
        else begin
            fails = fails + 1;
            $display("FAIL  %0s  got %h expected %h", name, instr, exp);
        end
    end
    endtask

//    initial begin
//        check("addr 0 = addi r1",  16'd0, 16'b001_001_000_0000101);
//        check("addr 1 = addi r2",  16'd1, 16'b001_010_000_0000011);
//        check("addr 2 = add r3",   16'd2, 16'b000_011_001_0000_010);
//        check("addr 3 = NOP",      16'd3, 16'h0000);
//        check("wrap 64->0", 16'd64, 16'b001_001_000_0000101);
//        if (fails == 0) $display("\nAll imem tests passed.");
//        else            $display("\n%0d test(s) failed.", fails);
//        $finish;
//    end

    initial begin
        for (i = 0; i < MEM_DEPTH; i = i + 1)
        mem[i] = 16'h0000;

    // hardcoded test program (Option B)
        mem[0] = 16'b001_001_000_0000101;  // addi r1, r0, 5   = 0x2405
        mem[1] = 16'b001_010_000_0000011;  // addi r2, r0, 3   = 0x2803
        mem[2] = 16'b000_011_001_0000_010; // add  r3, r1, r2  = 0x0C82

    // $readmemh(INIT_FILE, mem);   // disabled for self-contained test
    end
endmodule
