module load (
    input  [15:0] a,
    input  [15:0] b,
    input  [15:0] imm7,      // 16-bit sign-extended from decoder
    input  [9:0]  imm10,
    input         load_op,
    output reg [15:0] out
);

    always @* begin
        case (load_op)
            1'b0: out = {imm10, 6'b000000};  // LUI: imm10 << 6 (upper 10 bits, lower 6 bits zeroed)
            1'b1: out = imm7 + b ;           // LW: address = rB + imm7 (imm7 is sign-extended from decoder)
        endcase
    end

endmodule