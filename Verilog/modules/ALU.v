module ALU (
    input  [15:0] b,       // bit 15 thru to bit 0 so 16 bits
    input  [15:0] c,       // bit 15 thru to bit 0 so 16 bits
    input  [15:0] imm,     // sign-extended immediate from decoder (decoder.v already extends imm7 to 16 bits); used by ADDI / address calc
    input  [1:0]  alu_op,  // control signal, comes from control unit which decodes the instruction opcode , Instruction → Control Unit → alu_op → ALU behavior // 0 = ADD, 1 = NAND

    output reg [15:0] a        // output 16 bits
);

    // Combinational logic
    always @* begin
        case (alu_op) 
            2'b00:   a = c + b;       // ADD: add/addi/lw/sw/PC+1(+imm), 2 means two bits wide, ´b means binary , 0 means value
            2'b01:   a = b + imm;     // ADDI: add immediate, 2 means two bits wide, ´b means binary, 0 means value
            2'b10:   a = ~(c & b);    // NAND: nand ~(a & b) , 2 means two bits wide, ´b means binary, 1 means value
            default: a = 16'h0000;  // is there to prevent latch inference**, ´h means hexadecimal, 0000 is a value, this is there for safety , latch inference explained 
        endcase
    end

endmodule


// Latch inference** definition 

// Now imagine you forget to tell the machine what to do in one situation.
// Example:
// If button is 0 → output = 5
// If button is 1 → … you forgot to say anything
// So what should it do when button = 1?
// The hardware says:
// “I guess I should just remember the last output.”
// Boom.
// Now it needs memory.
// That memory element is called a latch. 
