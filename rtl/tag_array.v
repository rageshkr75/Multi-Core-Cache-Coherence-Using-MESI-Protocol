`timescale 1ns / 1ps

module tag_array #(
    parameter CACHE_DEPTH = 64,
    parameter INDEX_WIDTH = 6,
    parameter TAG_WIDTH   = 22
)(
    input  wire                   clk,
    input  wire                   we,
    input  wire [INDEX_WIDTH-1:0] index,
    input  wire [TAG_WIDTH-1:0]   tag_in,
    output wire [TAG_WIDTH-1:0]   tag_out,
    
    input  wire [INDEX_WIDTH-1:0] snoop_index,
    output wire [TAG_WIDTH-1:0]   snoop_tag_out
);

    reg [TAG_WIDTH-1:0] mem [0:CACHE_DEPTH-1];

    assign tag_out = mem[index];
    assign snoop_tag_out = mem[snoop_index];

    always @(posedge clk) begin
        if (we) begin
            mem[index] <= tag_in;
        end
    end

endmodule
