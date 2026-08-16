`timescale 1ns / 1ps

module memory_controller #(
    parameter ADDR_WIDTH  = 32,
    parameter DATA_WIDTH  = 128,
    parameter MEM_LATENCY = 5
)(
    input  wire                   clk,
    input  wire                   reset,

    // Bus Interface 
    input  wire [2:0]             bus_op,       
    input  wire [ADDR_WIDTH-1:0]  bus_addr,
    input  wire [DATA_WIDTH-1:0]  bus_data_in,  
    
    output reg                    mem_ready,    // Control Output (Combinational)
    output wire [DATA_WIDTH-1:0]  bus_data_out, 

    // Native Memory Interface 
    output reg                    mem_we,       // Control Output (Combinational)
    output wire [ADDR_WIDTH-1:0]  mem_addr,
    output wire [DATA_WIDTH-1:0]  mem_data_out, 
    input  wire [DATA_WIDTH-1:0]  mem_data_in   
);

    // ------------------------------------------------------------------------
    // FSM States: 3-Bit One-Hot Encoding
    // ------------------------------------------------------------------------
    localparam IDLE = 3'b001;
    localparam WAIT = 3'b010;
    localparam DONE = 3'b100;

    reg [2:0] state, next_state;
    
    // Datapath registers
    reg [7:0] delay_cnt;
    reg [2:0] latched_bus_op;

    // Route native memory signals directly (Datapath routing)
    assign mem_addr     = bus_addr;
    assign mem_data_out = bus_data_in;
    assign bus_data_out = mem_data_in;

    // ========================================================================
    // CONTROL PATH: 3-Always Block FSM
    // ========================================================================

    // 1. State Register
    always @(posedge clk) begin
        if (reset) state <= IDLE;
        else       state <= next_state;
    end

    // 2. Next-State Logic (Combinational)
    always @* begin
        next_state = state; // Default

        case (1'b1) // synthesis parallel_case
            state[0]: begin // IDLE
                if (bus_op == 3'b001 || bus_op == 3'b010 || bus_op == 3'b100) begin
                    next_state = WAIT;
                end
            end
            state[1]: begin // WAIT
                if (delay_cnt == 8'd0) begin
                    next_state = DONE;
                end
            end
            state[2]: begin // DONE
                next_state = IDLE;
            end
            default: next_state = IDLE; // Recovery
        endcase
    end

    // 3. Output Logic (Combinational)
    always @* begin
        mem_ready = 1'b0;
        mem_we    = 1'b0;

        case (1'b1) // synthesis parallel_case
            state[0]: begin // IDLE
                // Start writing to RAM immediately if a writeback request arrives
                if (bus_op == 3'b100) mem_we = 1'b1;
            end
            state[1]: begin // WAIT
                // Continue writing based on safely latched operation code
                if (latched_bus_op == 3'b100) mem_we = 1'b1;
            end
            state[2]: begin // DONE
                mem_ready = 1'b1; // Pulse ready to release bus
            end
            default: ;
        endcase
    end

    // ========================================================================
    // DATAPATH: Counter and Latch logic
    // ========================================================================
    always @(posedge clk) begin
        if (reset) begin
            delay_cnt      <= 8'd0;
            latched_bus_op <= 3'b000;
        end else begin
            case (1'b1) // synthesis parallel_case
                state[0]: begin // IDLE
                    if (bus_op == 3'b001 || bus_op == 3'b010 || bus_op == 3'b100) begin
                        delay_cnt      <= MEM_LATENCY;
                        latched_bus_op <= bus_op; // Latch transient bus intent
                    end
                end
                state[1]: begin // WAIT
                    if (delay_cnt != 8'd0) begin
                        delay_cnt <= delay_cnt - 1'b1;
                    end
                end
                state[2]: begin // DONE
                    // Await transition back to IDLE
                end
                default: ;
            endcase
        end
    end

endmodule