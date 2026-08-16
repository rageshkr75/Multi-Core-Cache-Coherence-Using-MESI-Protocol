`timescale 1ns / 1ps

module address_decoder #(
    parameter ADDR_WIDTH   = 32,
    parameter TAG_WIDTH    = 22,
    parameter INDEX_WIDTH  = 6,
    parameter OFFSET_WIDTH = 4
)(
    input  wire [ADDR_WIDTH-1:0]   cpu_addr,

    output wire [TAG_WIDTH-1:0]    tag,
    output wire [INDEX_WIDTH-1:0]  index,
    output wire [OFFSET_WIDTH-1:0] offset
);


    
    // Offset: The lowest OFFSET_WIDTH bits
    assign offset = cpu_addr[OFFSET_WIDTH-1 : 0];
    
    // Index: The next INDEX_WIDTH bits
    assign index  = cpu_addr[OFFSET_WIDTH + INDEX_WIDTH - 1 : OFFSET_WIDTH];
    
    // Tag: The remaining upper TAG_WIDTH bits
    assign tag    = cpu_addr[ADDR_WIDTH-1 : ADDR_WIDTH - TAG_WIDTH];

endmodule