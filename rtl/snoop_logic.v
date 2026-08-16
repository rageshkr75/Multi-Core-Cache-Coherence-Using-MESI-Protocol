`timescale 1ns / 1ps

module snoop_logic (
    input  wire       clk,
    input  wire       reset,

    input  wire [3:0] current_mesi,
    input  wire       snoop_bus_req,
    input  wire [2:0] snoop_bus_op,
    input  wire       snoop_tag_match,
    input  wire       bus_grant,
    input  wire       mem_ready,
    
    output reg        snoop_we_mesi,
    output reg  [3:0] snoop_next_mesi,
    output wire       assert_shared,
    output wire       flush_data
);

    localparam I = 4'b0001;
    localparam S = 4'b0010;
    localparam E = 4'b0100;
    localparam M = 4'b1000;

    // We must latch the intent to flush data so combinational glitches on
    // snoop_tag_match don't accidentally pull the data line low mid-cycle!
    reg latched_flush;
    reg latched_shared;
    reg prev_snoop_req;

    always @(posedge clk) begin
        if (reset) begin
            latched_flush  <= 1'b0;
            latched_shared <= 1'b0;
            prev_snoop_req <= 1'b0;
        end else begin
            prev_snoop_req <= snoop_bus_req;

            // When a NEW bus request starts, evaluate if we need to flush
            if (snoop_bus_req && !prev_snoop_req && !bus_grant && snoop_tag_match) begin
                if (current_mesi == M && (snoop_bus_op == 3'b001 || snoop_bus_op == 3'b010)) begin
                    latched_flush <= 1'b1;
                end
                if (current_mesi == M || current_mesi == E || current_mesi == S) begin
                    latched_shared <= 1'b1;
                end
            end 
            // Clear the flush when the transaction completes
            else if (!snoop_bus_req || mem_ready) begin
                latched_flush  <= 1'b0;
                latched_shared <= 1'b0;
            end
        end
    end

    assign flush_data    = latched_flush;
    assign assert_shared = latched_shared;

    // MESI state updates remain combinational as they feed into mesi_fsm
    always @* begin
        snoop_we_mesi   = 1'b0;
        snoop_next_mesi = current_mesi;

        if (snoop_bus_req && !bus_grant && snoop_tag_match) begin
            case (current_mesi)
                M: begin
                    if (snoop_bus_op == 3'b001) begin // BusRd
                        snoop_we_mesi   = 1'b1;
                        snoop_next_mesi = S; 
                    end else if (snoop_bus_op == 3'b010) begin // BusRdX
                        snoop_we_mesi   = 1'b1;
                        snoop_next_mesi = I; 
                    end
                end
                E: begin
                    if (snoop_bus_op == 3'b001) begin // BusRd
                        snoop_we_mesi   = 1'b1;
                        snoop_next_mesi = S; 
                    end else if (snoop_bus_op == 3'b010) begin // BusRdX
                        snoop_we_mesi   = 1'b1;
                        snoop_next_mesi = I; 
                    end
                end
                S: begin
                    if (snoop_bus_op == 3'b010 || snoop_bus_op == 3'b011) begin // BusRdX or BusUpgr
                        snoop_we_mesi   = 1'b1;
                        snoop_next_mesi = I; 
                    end
                end
                default: ; 
            endcase
        end
    end

endmodule
