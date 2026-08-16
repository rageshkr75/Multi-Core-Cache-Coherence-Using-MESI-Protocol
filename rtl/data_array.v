`timescale 1ns / 1ps

module data_array #(
    parameter CACHE_DEPTH = 64,
    parameter LINE_WIDTH  = 128,
    parameter INDEX_WIDTH = 6
)(
    input  wire                   clk,
    input  wire                   we,
    input  wire [INDEX_WIDTH-1:0] index,
    input  wire [LINE_WIDTH-1:0]  data_in,
    output wire [LINE_WIDTH-1:0]  data_out,
    
    input  wire [INDEX_WIDTH-1:0] snoop_index,
    output wire [LINE_WIDTH-1:0]  snoop_data_out
);

    reg [LINE_WIDTH-1:0] mem [0:CACHE_DEPTH-1];

    assign data_out = we ? data_in : mem[index];
    assign snoop_data_out = (we && (index == snoop_index)) ? data_in : mem[snoop_index];

    always @(posedge clk) begin
        if (we) begin
            mem[index] <= data_in;
        end
    end

endmodule
