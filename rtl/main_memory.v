`timescale 1ns / 1ps

module main_memory #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 128,
    parameter MEM_DEPTH  = 1024  // Number of cache lines in Main Memory
)(
    input  wire                   clk,
    input  wire                   we,
    input  wire [ADDR_WIDTH-1:0]  addr,
    input  wire [DATA_WIDTH-1:0]  data_in,
    output reg  [DATA_WIDTH-1:0]  data_out
);

    // ------------------------------------------------------------------------
    // Memory Array
    // ------------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

    // Block Address Calculation
    // We ignore the 4-bit offset because we read/write entire 128-bit blocks
    wire [27:0] block_addr = addr[ADDR_WIDTH-1 : 4];

    // Modulo limits the address so simulation doesn't crash if we exceed depth
    wire [31:0] safe_index = block_addr % MEM_DEPTH;

    // ------------------------------------------------------------------------
    // Synchronous Read/Write
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        if (we) begin
            mem[safe_index] <= data_in;
        end
        data_out <= mem[safe_index];
    end

    // Simulation initialization (Optional: pre-load with zeros)
    integer i;
    initial begin
        for (i = 0; i < MEM_DEPTH; i = i + 1) begin
            mem[i] = {DATA_WIDTH{1'b0}};
        end
    end

endmodule