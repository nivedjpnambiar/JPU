module tb_registerfile;

    reg         clk;
    reg  [2:0]  rs, rt, reg_op;
    reg  [15:0] write_data;
    reg         reg_write;
    wire [15:0] read_a, read_b;

    integer fails = 0;

    // Device under test — note: reg_op is the WRITE address on your module
    RegisterFile dut (
        .clk        (clk),
        .rs         (rs),
        .rt         (rt),
        .reg_op     (reg_op),
        .write_data (write_data),
        .reg_write  (reg_write),
        .read_a     (read_a),
        .read_b     (read_b)
    );

    // Clock: 10-unit period
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Write one value to a register on the next clock edge
    task do_write (input [2:0] addr, input [15:0] data);
    begin
        @(negedge clk);
        reg_op     = addr;
        write_data = data;
        reg_write  = 1'b1;
        @(negedge clk);     // posedge in between latches the write
        reg_write  = 1'b0;
    end
    endtask

    // Read both ports combinationally and check against expected values
    task check_read (
        input [127:0] name,
        input [2:0]   a_addr, b_addr,
        input [15:0]  exp_a,  exp_b
    );
    begin
        rs = a_addr; rt = b_addr; #1;   // combinational read settles
        if (read_a === exp_a && read_b === exp_b)
            $display("PASS  %0s  (read_a=%0d read_b=%0d)", name, read_a, read_b);
        else begin
            fails = fails + 1;
            $display("FAIL  %0s", name);
            $display("      got read_a=%0d read_b=%0d  expected %0d %0d",
                     read_a, read_b, exp_a, exp_b);
        end
    end
    endtask

    initial begin
        // Init
        rs = 0; rt = 0; reg_op = 0; write_data = 0; reg_write = 0;

        // ── Writes (simulating various instruction write-backs) ──
        do_write(3'd1, 16'd15);                 // ADD result
        do_write(3'd2, 16'd42);                 // ADDI result
        do_write(3'd3, ~(16'd15 & 16'd42));     // NAND result
        do_write(3'd4, 16'h07C0);               // LUI r4, 0x1F → 0x1F<<6
        do_write(3'd5, 16'd5);                  // JALR return addr

        // ── R0 write-protection: attempt to overwrite r0 ──
        do_write(3'd0, 16'hFFFF);               // should be IGNORED

        // ── Self-checking read-backs ──
        check_read("r1 / r2",       3'd1, 3'd2, 16'd15,            16'd42);
        check_read("r3 / r4",       3'd3, 3'd4, ~(16'd15 & 16'd42), 16'h07C0);
        check_read("r5 / r0(prot)", 3'd5, 3'd0, 16'd5,             16'd0);

        // ── reg_write=0 must block a write ──
        @(negedge clk);
        reg_op = 3'd1; write_data = 16'd999; reg_write = 1'b0;  // disabled
        @(negedge clk);
        check_read("r1 unchanged", 3'd1, 3'd0, 16'd15, 16'd0);

        // ── Dual-port: same register on both ports ──
        check_read("r2 on both ports", 3'd2, 3'd2, 16'd42, 16'd42);

        if (fails == 0) $display("\nAll register file tests passed.");
        else            $display("\n%0d test(s) failed.", fails);
        $finish;
    end

endmodule
