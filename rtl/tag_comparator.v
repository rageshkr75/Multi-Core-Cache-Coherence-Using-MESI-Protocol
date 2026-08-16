`timescale 1ns / 1ps

module tag_comparator #(
    parameter TAG_WIDTH = 22
)(
    input  wire [TAG_WIDTH-1:0] cpu_tag,    // Tag extracted from the CPU address
    input  wire [TAG_WIDTH-1:0] cache_tag,  // Tag read from the tag_array memory
    
    output wire                 tag_match   // High if tags are identical
);

    // ------------------------------------------------------------------------
    // Purely Combinational Equality Check
    // This synthesizes into a wide XNOR tree followed by an AND gate.
    // ------------------------------------------------------------------------
    assign tag_match = (cpu_tag == cache_tag);

endmodule