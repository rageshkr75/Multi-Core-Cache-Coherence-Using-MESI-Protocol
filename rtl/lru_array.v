`timescale 1ns / 1ps

module lru_array #(
parameter NUM_SETS = 64,
parameter INDEX_WIDTH = 6
)(
input  wire                   clk,
input  wire                   reset,
input  wire                   we,
input  wire [INDEX_WIDTH-1:0] index,
input  wire                   lru_in,
output wire                   lru_out // Combinational read
);

reg mem [0:NUM_SETS-1];
integer i;

assign lru_out = mem[index];

always @(posedge clk) begin
    if (reset) begin
        for (i = 0; i < NUM_SETS; i = i + 1) begin
            mem[i] <= 1'b0; // Default: Way 0 is Least Recently Used
        end
    end else if (we) begin
        mem[index] <= lru_in;
    end
end


endmodule
