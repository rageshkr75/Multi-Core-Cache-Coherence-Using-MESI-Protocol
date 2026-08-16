`timescale 1ns / 1ps

module bus_arbiter #(
    parameter N = 4 // Number of requesters (fully parameterizable!)
)(
    input  wire         clk,
    input  wire         reset,

    // Bus Requests from the N Cache Controllers
    input  wire [N-1:0] bus_req,

    // Bus Grants back to the N Cache Controllers (One-Hot)
    output reg  [N-1:0] bus_grant
);

    // ------------------------------------------------------------------------
    // FSM States for Multi-Cycle Holding
    // ------------------------------------------------------------------------
    localparam IDLE = 1'b0;
    localparam BUSY = 1'b1;

    reg state, next_state;

    // The "mask" acting as the round-robin pointer (Thermometer encoding)
    reg [N-1:0] pointer_reg, next_pointer;
    reg [N-1:0] next_grant;

    // ========================================================================
    // PAPER IMPLEMENTATION: "mask_expand" Round-Robin Combinational Logic
    // Reference: SNUG "Arbiters: Design Ideas and Coding Styles" - Listing 12
    // ========================================================================

    // 1. Masked Priority Arbiter
    // Uses the "Three-Assign" coding style for maximum synthesis optimization
    wire [N-1:0] req_masked = bus_req & pointer_reg;
   wire [N-1:0] mask_higher_pri_reqs;

assign mask_higher_pri_reqs[0] = 1'b0;

genvar i;
generate
    for(i=1;i<N;i=i+1) begin : MASK_CHAIN
        assign mask_higher_pri_reqs[i] =
               mask_higher_pri_reqs[i-1] | req_masked[i-1];
    end
endgenerate

    wire [N-1:0] grant_masked = req_masked & ~mask_higher_pri_reqs;

    // 2. Unmasked Priority Arbiter
    // Evaluates all requests as a fallback if no masked requests are active
wire [N-1:0] unmask_higher_pri_reqs;

assign unmask_higher_pri_reqs[0] = 1'b0;

genvar j;
generate
    for(j=1;j<N;j=j+1) begin : UNMASK_CHAIN
        assign unmask_higher_pri_reqs[j] =
               unmask_higher_pri_reqs[j-1] | bus_req[j-1];
    end
endgenerate
    
    wire [N-1:0] grant_unmasked = bus_req & ~unmask_higher_pri_reqs;

    // 3. Final Combinational Selection
    wire no_req_masked = (req_masked == {N{1'b0}});
    wire [N-1:0] comb_grant = no_req_masked ? grant_unmasked : grant_masked;

    // ========================================================================
    // STATE MACHINE: Holding the grant for multi-cycle bus transactions
    // ========================================================================

    always @(posedge clk) begin
        if (reset) begin
            state       <= IDLE;
            pointer_reg <= {N{1'b1}}; // Initialize mask to all 1s (everyone eligible)
            bus_grant   <= {N{1'b0}};
        end else begin
            state       <= next_state;
            pointer_reg <= next_pointer;
            bus_grant   <= next_grant;
        end
    end

    always @* begin
        // Default assignments to prevent latches
        next_state   = state;
        next_pointer = pointer_reg;
        next_grant   = bus_grant;

        case (state)
            IDLE: begin
                // If any cache is requesting the bus...
                if (bus_req != {N{1'b0}}) begin
                    next_state = BUSY;
                    next_grant = comb_grant; // Snap the optimal mask_expand grant
                end
            end

            BUSY: begin
                // Wait until the currently granted cache drops its request line
                if ((bus_grant & bus_req) == {N{1'b0}}) begin
                    next_state = IDLE;
                    next_grant = {N{1'b0}};

                    // Pointer Update Logic: 
                    // Update the mask so that all requesters strictly HIGHER than 
                    // the current grant have priority next.
                    // We utilize the exact same "Three-Assign" logic on the grant itself!
                    next_pointer[0]     = 1'b0;
                    next_pointer[N-1:1] = next_pointer[N-2:0] | bus_grant[N-2:0];
                end
            end
        endcase
    end

endmodule