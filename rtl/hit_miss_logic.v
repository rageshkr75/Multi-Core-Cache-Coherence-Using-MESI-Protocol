`timescale 1ns / 1ps

module hit_miss_logic (
    input  wire       cpu_rw,       // 0 = Read, 1 = Write
    input  wire       tag_match,    // From tag_comparator
    input  wire [3:0] mesi_state,   // From mesi_array (One-Hot: M=Bit 3, E=Bit 2, S=Bit 1, I=Bit 0)

    output wire       cache_hit,    // General hit (valid data present)
    output wire       cache_miss,   // General miss (data not present or invalid)
    output wire       read_hit,     // Valid read hit
    output wire       write_hit,    // Valid write hit (can write immediately)
    output wire       write_upgrade // Hit in Shared, needs Bus Upgrade before writing
);

    // ------------------------------------------------------------------------
    // MESI State Decoding (based on 4-bit One-Hot encoding)
    // INVALID   = 4'b0001 (Bit 0)
    // SHARED    = 4'b0010 (Bit 1)
    // EXCLUSIVE = 4'b0100 (Bit 2)
    // MODIFIED  = 4'b1000 (Bit 3)
    // ------------------------------------------------------------------------
    wire is_valid = ~mesi_state[0]; // Valid if NOT Invalid
    wire is_shared = mesi_state[1];

    // ------------------------------------------------------------------------
    // Base Hit/Miss Logic
    // A cache line is a hit if the tags match and the state is not Invalid.
    // ------------------------------------------------------------------------
    assign cache_hit  = tag_match & is_valid;
    assign cache_miss = ~cache_hit;

    // ------------------------------------------------------------------------
    // Specific Hit Types for the FSM
    // ------------------------------------------------------------------------
    
    // Read Hit: We want to read (cpu_rw == 0) and we have a cache hit.
    assign read_hit = (~cpu_rw) & cache_hit;

    // Write Hit: We want to write (cpu_rw == 1), we have a cache hit, 
    // AND the state is M or E. (We have exclusive ownership).
    assign write_hit = cpu_rw & cache_hit & (~is_shared);

    // Write Upgrade: We want to write, we have a cache hit, but the state is S.
    // We cannot write yet; the FSM must issue a Bus Upgrade.
    assign write_upgrade = cpu_rw & cache_hit & is_shared;

endmodule