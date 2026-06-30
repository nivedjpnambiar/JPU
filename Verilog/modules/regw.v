module regw(

    // ===== Control signals from DEC =====
    input [1:0] mux_control, // control signal from decoder to REGW for output mux; 00 = ALU, 01 = LUI, 10 = LW, 11 = JALR
    input [2:0] reg_operand, // control signal from decoder to REGW for selecting the register to write back to

    // ===== Input sources =====
    // ALU
    input [15:0] alu_out, // ADD,ADDI, or NAND output from ALU
    // LOAD
    input [15:0] lui_load, // LUI output from LOAD
    input [15:0] lw_load,  // LW: Data from memory being loaded to register
    // PC
    input [15:0] pc_ret_addr, // PC + 1 for JALR

    // ===== Outputs =====
    output reg [15:0] regw_out, // output of REGW to be written back to register file
    output reg [2:0] reg_operand_out // control signal from REGW to register file for selecting the register to write back to
);


    always @* begin
        case (mux_control)
            2'b00: regw_out = alu_out; // ALU output (ADD, ADDI, NAND)
            2'b01: regw_out = lui_load; // LUI output from LOAD
            2'b10: regw_out = lw_load;  // LW: Data from memory being loaded to register
            2'b11: regw_out = pc_ret_addr; // PC + 1 for JALR
            default: regw_out = 16'h0000; // default case for safety
        endcase

        reg_operand_out = reg_operand; // pass through the control signal for register selection
    end


endmodule
