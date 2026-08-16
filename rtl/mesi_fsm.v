`timescale 1ns / 1ps

module mesi_fsm (
    // ------------------------------------------------------------------------
    // CPU Evaluation Path (Processor Induced)
    // ------------------------------------------------------------------------
    input  wire [3:0] cpu_current_mesi,
    input  wire       cpu_read_complete,
    input  wire       cpu_write_complete,
    input  wire       shared_line_in,
    
    output reg        cpu_we_mesi,
    output reg  [3:0] cpu_next_mesi,

    // ------------------------------------------------------------------------
    // Snoop Evaluation Path (Bus Intervention)
    // ------------------------------------------------------------------------
    input  wire [3:0] snoop_current_mesi,
    input  wire       snoop_we_in,
    input  wire [3:0] snoop_next_mesi_in,
    
    output reg        snoop_we_mesi,
    output reg  [3:0] snoop_next_mesi
);

    localparam I = 4'b0001;
    localparam S = 4'b0010;
    localparam E = 4'b0100;
    localparam M = 4'b1000;

    // ========================================================================
    // SNOOP PATH (Direct Passthrough mapping)
    // ========================================================================
    always @* begin
        snoop_we_mesi   = snoop_we_in;
        snoop_next_mesi = snoop_next_mesi_in;
    end
    
    // ========================================================================
    // CPU PATH (Pure Ownership Transitions)
    // ========================================================================
    always @* begin
        // Default: Hold state
        cpu_we_mesi   = 1'b0;
        cpu_next_mesi = cpu_current_mesi;

        if (cpu_read_complete || cpu_write_complete) begin
            cpu_we_mesi = 1'b1;

            case (cpu_current_mesi) 
                
                I: begin 
                    if (cpu_write_complete)      cpu_next_mesi = M;
                    else if (cpu_read_complete)  cpu_next_mesi = (shared_line_in) ? S : E;
                end

                S: begin 
                    if (cpu_write_complete)      cpu_next_mesi = M;
                end

                E: begin 
                    if (cpu_write_complete)      cpu_next_mesi = M;
                end

                M: begin 
                    // Write hits in Modified stay Modified
                    cpu_next_mesi = M;
                end
                
                default: cpu_next_mesi = I; 
            endcase
        end
    end

endmodule
