`timescale 1ns / 1ps

module cpu_emulator #(
    parameter CORE_ID    = 0,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 128,
    parameter SEED       = 0 
)(
    input  wire                   clk,
    input  wire                   reset,

    // Interface to Cache Controller
    input  wire                   cache_ready,
    input  wire [DATA_WIDTH-1:0]  cpu_data_in,

    output reg                    cpu_req,
    output reg                    cpu_rw,
    output reg  [ADDR_WIDTH-1:0]  cpu_addr,
    output reg  [DATA_WIDTH-1:0]  cpu_data_out
);

    // ------------------------------------------------------------------------
    // Trace ROM Loading
    // ------------------------------------------------------------------------
    reg [166:0] instruction_rom [0:1999];
    integer total_instructions = 0;
    integer i;

    initial begin
        $readmemh("cpu_trace.txt", instruction_rom);
        
        for(i = 0; i < 2000; i = i + 1) begin
            if (instruction_rom[i][3:0] !== 4'hF) begin
                total_instructions = i;
                i = 2000; 
            end
        end
        $display("[CORE %0d] Loaded %0d trace instructions from Python.", CORE_ID, total_instructions);
    end

    // ------------------------------------------------------------------------
    // CPU State Machine (AXI-Style Valid/Ready Handshake)
    // ------------------------------------------------------------------------
    reg [31:0] pc;
    reg        state;

    localparam S_IDLE  = 1'b0;
    localparam S_ISSUE = 1'b1;

    always @(posedge clk) begin
        if (reset) begin
            pc           <= 0;
            state        <= S_IDLE;
            cpu_req      <= 1'b0;
            cpu_rw       <= 1'b0;
            cpu_addr     <= 0;
            cpu_data_out <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (pc < total_instructions) begin
                        // Is this instruction meant for this specific core?
                        if (instruction_rom[pc][166:165] == CORE_ID) begin
                            cpu_rw       <= instruction_rom[pc][164];
                            cpu_addr     <= instruction_rom[pc][163:132];
                            cpu_data_out <= instruction_rom[pc][131:4];
                            cpu_req      <= 1'b1;
                            state        <= S_ISSUE;
                        end else begin
                            // Instruction belongs to another core, skip to the next
                            pc <= pc + 1'b1;
                        end
                    end
                end
                
                S_ISSUE: begin
                    // --------------------------------------------------------
                    // THE HANDSHAKE
                    // A transaction officially completes on the rising clock edge 
                    // where BOTH cpu_req (Valid) AND cache_ready (Ready) are High.
                    // --------------------------------------------------------
                    if (cpu_req && cache_ready) begin
                        cpu_req <= 1'b0;     // Drop the request line
                        pc      <= pc + 1'b1; // Advance the Program Counter
                        state   <= S_IDLE;    // Return to fetch the next instruction
                    end
                end
            endcase
        end
    end

endmodule
