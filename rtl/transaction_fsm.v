`timescale 1ns / 1ps

module transaction_fsm (
input  wire       clk,
input  wire       reset,

// CPU Events & Hit/Miss (Combinational)
input  wire       cpu_req,
input  wire       cpu_rw,
input  wire       read_hit,
input  wire       write_hit,
input  wire       write_upgrade,
input  wire       cache_miss,
input  wire       evict_dirty,

// Bus Arbitration & Memory (Latency)
input  wire       bus_grant,
input  wire       mem_ready,

// Outputs to CPU & Datapath
output reg        cache_ready,
output reg        we_tag,
output reg        we_data,

// Outputs to Bus
output reg        bus_req,
output reg  [2:0] bus_op,

// Protocol Events (Handshake to MESI FSM)
output reg        cpu_read_complete, 
output reg        cpu_write_complete,

output reg  [3:0] trans_state  


);

localparam IDLE      = 4'b0001;
localparam WAIT_BUS  = 4'b0010;
localparam WAIT_DATA = 4'b0100;
localparam WRITEBACK = 4'b1000;

reg [3:0] state, next_state;

// ------------------------------------------------------------------------
// Latch Registers: Capture transient info to preserve state during waits
// ------------------------------------------------------------------------
reg latched_rw;
reg latched_upgrade;
reg latched_evict_dirty;

always @(posedge clk) begin
    if (reset) begin
        latched_rw          <= 1'b0;
        latched_upgrade     <= 1'b0;
        latched_evict_dirty <= 1'b0;
    end else if (state[0] && cpu_req) begin // Latch when leaving IDLE
        latched_rw          <= cpu_rw;
        latched_upgrade     <= write_upgrade;
        latched_evict_dirty <= evict_dirty;
    end else if (state[3]) begin 
        // Clear the dirty latch once we enter writeback 
        // so we don't enter an infinite writeback loop when returning to WAIT_BUS
        latched_evict_dirty <= 1'b0;
    end
end

// ------------------------------------------------------------------------
// 1. State Register
// ------------------------------------------------------------------------
always @(posedge clk) begin
    if (reset) state <= IDLE;
    else       state <= next_state;
end

// ------------------------------------------------------------------------
// 2. Next-State Logic (Answers: "What am I waiting for?")
// ------------------------------------------------------------------------
always @* begin
    next_state = state; 

    case (1'b1) // synthesis parallel_case
        state[0]: begin // IDLE
            if (cpu_req) begin
                if (cache_miss && evict_dirty) next_state = WRITEBACK;
                else if (cache_miss || write_upgrade) next_state = WAIT_BUS;
            end
        end
        state[1]: begin // WAIT_BUS
            if (bus_grant) begin
                // Combines the latched intent with the LIVE combinational state.
                // If a snoop invalidated our line while we were waiting, evict_dirty/write_upgrade 
                // will instantly go low, aborting the illegal writeback/upgrade and falling back to WAIT_DATA
                if (cache_miss && latched_evict_dirty && evict_dirty) next_state = WRITEBACK;
                else if (latched_upgrade && write_upgrade)            next_state = IDLE; 
                else                                                  next_state = WAIT_DATA;
            end
        end
        state[2]: begin // WAIT_DATA
            if (mem_ready) next_state = IDLE;
        end
        state[3]: begin // WRITEBACK
            if (mem_ready) next_state = WAIT_BUS; 
        end
        default: next_state = IDLE;
    endcase
end

// ------------------------------------------------------------------------
// 3. Output Logic (Combinational Actions)
// ------------------------------------------------------------------------
always @* begin
    // Defaults
    cache_ready        = 1'b0;
    bus_req            = 1'b0;
    bus_op             = 3'b000;
    we_tag             = 1'b0;
    we_data            = 1'b0;
    cpu_read_complete  = 1'b0;
    cpu_write_complete = 1'b0;
    trans_state        = state; 

    case (1'b1) // synthesis parallel_case
        state[0]: begin // IDLE
            if (cpu_req) begin
                if (read_hit) begin
                    cache_ready = 1'b1;
                    cpu_read_complete = 1'b1;
                end 
                else if (write_hit) begin
                    cache_ready = 1'b1;
                    we_data     = 1'b1;
                    cpu_write_complete = 1'b1;
                end 
            end else begin
                cache_ready = 1'b1;
            end
        end
        state[1]: begin // WAIT_BUS
            bus_req = 1'b1;
            
            // Only broadcast Upgrade if we survived the wait without being snooped
            if (latched_upgrade && write_upgrade) bus_op = 3'b011; // Upgr
            else if (latched_rw)                  bus_op = 3'b010; // RdX
            else                                  bus_op = 3'b001; // Rd

            // Bypass WAIT_DATA only if the Upgrade survived
            if (bus_grant && latched_upgrade && write_upgrade) begin
                we_data            = 1'b1;
                cache_ready        = 1'b1;
                cpu_write_complete = 1'b1; 
            end
        end
        state[2]: begin // WAIT_DATA
            bus_req = 1'b1;
            // HOLD the bus operation active so snooping caches don't drop their flush!
            // Since Upgrade bypasses this state, we are definitely doing a Read or ReadX
            if (latched_rw) bus_op = 3'b010; // RdX
            else            bus_op = 3'b001; // Rd
            
            if (mem_ready) begin
                we_tag      = 1'b1;
                we_data     = 1'b1;
                cache_ready = 1'b1;
                if (latched_rw) cpu_write_complete = 1'b1;
                else            cpu_read_complete  = 1'b1;
            end
        end
        state[3]: begin // WRITEBACK
            bus_req = 1'b1; 
            bus_op  = 3'b100; // Bus Writeback
        end
        default: ;
    endcase
end


endmodule
