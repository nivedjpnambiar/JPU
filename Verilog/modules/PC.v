module PC (
    input  [15:0] a,
    input  [15:0] b,
    input  [15:0] pc,
    input         pc_op,    // 1'b0 = BEQ, 1'b1 = JALR
    input  [15:0] imm,      // 16-bit sign-extended from decoder
    
    output reg  [15:0] out,       // branch target / JALR target sent to CU
    output reg         pc_update, // 1 → CU should latch 'out' into PC next cycle
    output wire [15:0] ret_addr   // PC + 1, written to RegW for JALR (continuous assign → wire)
);

    assign ret_addr = pc + 16'd1;

    wire eq;
    assign eq = (a == b);

    always @* begin
        out       = 16'd0;
        pc_update = 1'b0; //contro signal to be sent to the CU mux

        case (pc_op)
            1'b0: begin // BEQ
                if (eq) begin
                    out       = pc + 16'd1 + imm;
                    pc_update = 1'b1;
                end
                // else: pc_update stays 0 → CU handles default increment
            end

            1'b1: begin // JALR
                out       = b;
                pc_update = 1'b1;
            end
        endcase
    end

endmodule
