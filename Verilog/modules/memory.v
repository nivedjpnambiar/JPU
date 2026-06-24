// mem read (load) has to be comibnational and mem_write (store) has to be sequential

module memory (
    input  wire         clk,
    input  wire [15:0]  mem_read_addr,  
    input  wire         mem_write_en,
    input  wire [15:0]  mem_write_addr,   
    input  wire [15:0]  mem_write_data,
    output wire [15:0]  mem_read_out                               
);
    reg [15:0] mems [15:0] /* verilator public_flat_rw */; // Memory (public: read by C++ testbench)

    integer i;
    initial for (i = 0; i < 16; i = i + 1) mems[i] = 16'd0;

    
    always @(posedge clk) 
        if (mem_write_en)
            mems[mem_write_addr] <= mem_write_data;

    assign mem_read_out = mems[mem_read_addr]; // reading memory mem_read

endmodule
