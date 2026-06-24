
//  8 registers, each 16 bits wide, R0 to R7. R0 is hardwired to 0.

module RegisterFile (
    input  wire        clk,
    input  wire [2:0]  rs,            // read operand A → regA, 3 bits wide coz we have 8 registers
    input  wire [2:0]  rt,            // read operand B → regB/regC, 3 bits wide
    input  wire [2:0]  reg_op,        // write operand
    input  wire [15:0] write_data,
    input  wire        reg_write,     // IT IS A WRITE ENABLE YOU AUTISTIC RETARD, splits registers into registers that have to write back to them and those that don't, comes from decoder                                
    output wire [15:0] read_a,        // port A output → goes to regA input of ALU and LOAD , PC
    output wire [15:0] read_b         // port B output → goes to regB input of ALU and LOAD , PC  
);
    reg [15:0] regs [7:0] /* verilator public_flat_rw */; // register storage (public: read by C++ testbench)

    integer i;
    initial for (i = 0; i < 8; i = i + 1) regs[i] = 16'd0;

    // R0 to 0 coz it says so in ISA 
    always @(posedge clk) // has memory that's why always @
        if (reg_write && reg_op != 3'b000)
            regs[reg_op] <= write_data;

    assign read_a = regs[rs]; // reading register rs 
    assign read_b = regs[rt]; // reading register rt

endmodule
