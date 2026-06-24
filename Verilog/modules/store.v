module store (
    input  [15:0] a,
    input  [15:0] b,
    input  [15:0] imm,      // 16-bit sign-extended from decoder
    output [15:0] addr,
    output [15:0] data
);

    // address to store the data at = b + signed immediate
    assign addr = b + imm;

    // Data to store into memory
    assign data = a;

endmodule
