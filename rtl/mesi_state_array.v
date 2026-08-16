`timescale 1ns / 1ps

module mesi_array #(
    parameter CACHE_DEPTH = 64,
    parameter INDEX_WIDTH = 6
)(
    input  wire                   clk,
    input  wire                   reset,
    
    // ------------------------------------------------------------------------
    // Port A: CPU Datapath
    // ------------------------------------------------------------------------
    input  wire                   cpu_we,
    input  wire [INDEX_WIDTH-1:0] cpu_index,
    input  wire [3:0]             cpu_state_in,
    output wire [3:0]             cpu_state_out,
    
    // ------------------------------------------------------------------------
    // Port B: Snoop Datapath
    // ------------------------------------------------------------------------
    input  wire                   snoop_we,
    input  wire [INDEX_WIDTH-1:0] snoop_index,
    input  wire [3:0]             snoop_state_in,
    output wire [3:0]             snoop_state_out
);

    localparam INVALID = 4'b0001;
    reg [3:0] mem [0:CACHE_DEPTH-1];
    integer i;

    // Independent Combinational Reads
    assign cpu_state_out   = mem[cpu_index];
    assign snoop_state_out = mem[snoop_index];

    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < CACHE_DEPTH; i = i + 1) begin
                mem[i] <= INVALID;
            end
        end else begin
            // Structural Collision Resolution: Snoop strictly overrides the CPU
            if (snoop_we && cpu_we && (snoop_index == cpu_index)) begin
                mem[snoop_index] <= snoop_state_in;
            end else begin
                // Parallel Independent Writes
                if (snoop_we) mem[snoop_index] <= snoop_state_in;
                if (cpu_we)   mem[cpu_index]   <= cpu_state_in;
            end
        end
    end

endmodule
