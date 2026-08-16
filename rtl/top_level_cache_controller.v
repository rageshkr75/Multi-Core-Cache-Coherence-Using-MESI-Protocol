`timescale 1ns / 1ps

module cache_controller #(
    parameter ADDR_WIDTH   = 32,
    parameter DATA_WIDTH   = 128,     
    parameter CACHE_DEPTH  = 64,      
    parameter INDEX_WIDTH  = 6,
    parameter TAG_WIDTH    = 22,
    parameter OFFSET_WIDTH = 4
)(
    input  wire                  clk,
    input  wire                  reset,

    // CPU Interface
    input  wire                  cpu_req,
    input  wire                  cpu_rw,         
    input  wire [ADDR_WIDTH-1:0] cpu_addr,
    input  wire [DATA_WIDTH-1:0] cpu_data_in,    
    output wire [DATA_WIDTH-1:0] cpu_data_out,   
    output wire                  cache_ready,    

    // Master Bus Interface
    input  wire                  bus_grant,      
    input  wire                  mem_ready,      
    input  wire                  shared_line_in, 
    input  wire [DATA_WIDTH-1:0] bus_data_in,    
    output wire                  bus_req,
    output wire [2:0]            bus_op,         
    output wire [ADDR_WIDTH-1:0] bus_addr_out,   
    output wire [DATA_WIDTH-1:0] bus_data_out,
    output wire [DATA_WIDTH-1:0] cache_flush_data_out, 

    // Snoop Interface
    input  wire                  snoop_bus_req,  
    input  wire [2:0]            snoop_bus_op,
    input  wire [ADDR_WIDTH-1:0] snoop_bus_addr, 
    output wire                  shared_line_out,
    output wire                  flush_data      
);

    // --- CPU Address Decoding ---
    wire [TAG_WIDTH-1:0]    cpu_tag;
    wire [INDEX_WIDTH-1:0]  cpu_index;
    wire [OFFSET_WIDTH-1:0] cpu_offset;

    address_decoder #(
        .ADDR_WIDTH(ADDR_WIDTH), .TAG_WIDTH(TAG_WIDTH), 
        .INDEX_WIDTH(INDEX_WIDTH), .OFFSET_WIDTH(OFFSET_WIDTH)
    ) u_addr_decoder (
        .cpu_addr(cpu_addr), .tag(cpu_tag), .index(cpu_index), .offset(cpu_offset)
    );

    // --- Snoop Address Decoding ---
    wire [INDEX_WIDTH-1:0] snoop_index = snoop_bus_addr[OFFSET_WIDTH+INDEX_WIDTH-1 : OFFSET_WIDTH];
    wire [TAG_WIDTH-1:0]   snoop_tag   = snoop_bus_addr[ADDR_WIDTH-1 : ADDR_WIDTH-TAG_WIDTH];

    // ========================================================================
    // CPU EVALUATION PATH
    // ========================================================================
    wire [TAG_WIDTH-1:0] cpu_stored_tag_w0, cpu_stored_tag_w1;
    wire [3:0]           cpu_stored_mesi_w0, cpu_stored_mesi_w1;
    wire [DATA_WIDTH-1:0]cpu_data_out_w0, cpu_data_out_w1;
    wire                 cpu_tag_match_w0, cpu_tag_match_w1;
    wire                 lru_bit;

    assign cpu_tag_match_w0 = (cpu_tag == cpu_stored_tag_w0);
    assign cpu_tag_match_w1 = (cpu_tag == cpu_stored_tag_w1);

    wire cpu_is_valid_w0 = (cpu_stored_mesi_w0 != 4'b0001);
    wire cpu_is_valid_w1 = (cpu_stored_mesi_w1 != 4'b0001);
    
    wire cpu_hit_w0 = cpu_tag_match_w0 & cpu_is_valid_w0;
    wire cpu_hit_w1 = cpu_tag_match_w1 & cpu_is_valid_w1;
    wire cpu_overall_tag_match = cpu_hit_w0 | cpu_hit_w1;

    wire invalid_way = !cpu_is_valid_w0 ? 1'b0 : (!cpu_is_valid_w1 ? 1'b1 : lru_bit);
    wire cpu_target_way = cpu_hit_w1 ? 1'b1 : (cpu_hit_w0 ? 1'b0 : invalid_way);

    wire [3:0]           cpu_target_mesi = cpu_target_way ? cpu_stored_mesi_w1 : cpu_stored_mesi_w0;
    wire [TAG_WIDTH-1:0] cpu_target_tag  = cpu_target_way ? cpu_stored_tag_w1  : cpu_stored_tag_w0;
    assign cpu_data_out = cpu_target_way ? cpu_data_out_w1 : cpu_data_out_w0;

    // ========================================================================
    // SNOOP EVALUATION PATH (Completely Decoupled)
    // ========================================================================
    wire [TAG_WIDTH-1:0] snoop_stored_tag_w0, snoop_stored_tag_w1;
    wire [3:0]           snoop_stored_mesi_w0, snoop_stored_mesi_w1;
    wire [DATA_WIDTH-1:0]snoop_data_out_w0, snoop_data_out_w1;
    
    wire snoop_tag_match_w0 = (snoop_tag == snoop_stored_tag_w0);
    wire snoop_tag_match_w1 = (snoop_tag == snoop_stored_tag_w1);
    
    wire snoop_is_valid_w0 = (snoop_stored_mesi_w0 != 4'b0001);
    wire snoop_is_valid_w1 = (snoop_stored_mesi_w1 != 4'b0001);
    
    wire snoop_hit_w0 = snoop_tag_match_w0 & snoop_is_valid_w0;
    wire snoop_hit_w1 = snoop_tag_match_w1 & snoop_is_valid_w1;
    wire snoop_overall_tag_match = snoop_hit_w0 | snoop_hit_w1;
    
    wire snoop_target_way = snoop_hit_w1 ? 1'b1 : 1'b0;
    wire [3:0] snoop_target_mesi = snoop_target_way ? snoop_stored_mesi_w1 : snoop_stored_mesi_w0;
    
    wire [DATA_WIDTH-1:0] flushed_data_to_bus = snoop_target_way ? snoop_data_out_w1 : snoop_data_out_w0;

    // ========================================================================
    // FSMs & Control
    // ========================================================================
    wire cache_hit, cache_miss, read_hit, write_hit, write_upgrade;
    wire trans_cache_ready, we_tag_trans, we_data_trans;
    wire cpu_read_complete, cpu_write_complete;
    wire [3:0] trans_state;
    
    wire evict_dirty = cpu_target_mesi[3];

    hit_miss_logic u_hit_miss_logic (
        .cpu_rw        (cpu_rw),
        .tag_match     (cpu_overall_tag_match), 
        .mesi_state    (cpu_target_mesi),
        .cache_hit     (cache_hit),
        .cache_miss    (cache_miss),
        .read_hit      (read_hit),
        .write_hit     (write_hit),
        .write_upgrade (write_upgrade)
    );

    // CPU is no longer masked by !do_snoop. Unleash concurrency!
    transaction_fsm u_trans_fsm (
        .clk(clk), .reset(reset), .cpu_req(cpu_req), .cpu_rw(cpu_rw),
        .read_hit(read_hit), .write_hit(write_hit), .write_upgrade(write_upgrade),
        .cache_miss(cache_miss), .evict_dirty(evict_dirty), .bus_grant(bus_grant),
        .mem_ready(mem_ready), .cache_ready(trans_cache_ready), .we_tag(we_tag_trans),
        .we_data(we_data_trans), .bus_req(bus_req), .bus_op(bus_op),
        .cpu_read_complete(cpu_read_complete), .cpu_write_complete(cpu_write_complete),
        .trans_state(trans_state)
    );

    assign cache_ready = trans_cache_ready; 

    // ========================================================================
    // Snoop Logic
    // ========================================================================
    wire       snoop_we_mesi_internal;
    wire [3:0] snoop_next_mesi_internal;
    wire       snoop_wants_flush;

    snoop_logic u_snoop_logic (
        .clk             (clk),
        .reset           (reset),
        .current_mesi    (snoop_target_mesi),
        .snoop_bus_req   (snoop_bus_req),
        .snoop_bus_op    (snoop_bus_op),
        .snoop_tag_match (snoop_overall_tag_match), 
        .bus_grant       (bus_grant),
        .mem_ready       (mem_ready),
        .snoop_we_mesi   (snoop_we_mesi_internal),
        .snoop_next_mesi (snoop_next_mesi_internal),
        .assert_shared   (shared_line_out),
        .flush_data      (snoop_wants_flush)
    );
    
    assign flush_data = snoop_wants_flush;

    wire       final_cpu_we_mesi;
    wire [3:0] final_cpu_next_mesi;
    wire       final_snoop_we_mesi;
    wire [3:0] final_snoop_next_mesi;

    mesi_fsm u_mesi_fsm (
        // CPU Port
        .cpu_current_mesi   (cpu_target_mesi),
        .cpu_read_complete  (cpu_read_complete),
        .cpu_write_complete (cpu_write_complete),
        .shared_line_in     (shared_line_in),
        .cpu_we_mesi        (final_cpu_we_mesi),
        .cpu_next_mesi      (final_cpu_next_mesi),
        
        // Snoop Port
        .snoop_current_mesi (snoop_target_mesi),
        .snoop_we_in        (snoop_we_mesi_internal),
        .snoop_next_mesi_in (snoop_next_mesi_internal),
        .snoop_we_mesi      (final_snoop_we_mesi),
        .snoop_next_mesi    (final_snoop_next_mesi)
    );

    // ========================================================================
    // Datapath & Arrays
    // ========================================================================
    wire is_writeback = (bus_op == 3'b100);
    assign bus_addr_out = is_writeback ? {cpu_target_tag, cpu_index, {OFFSET_WIDTH{1'b0}}} 
                                       : {cpu_tag,        cpu_index, {OFFSET_WIDTH{1'b0}}};
                                       
    assign bus_data_out = cpu_data_out; 
    assign cache_flush_data_out = flushed_data_to_bus; 

    wire [DATA_WIDTH-1:0] array_data_in = mem_ready ? bus_data_in : cpu_data_in;

    // Isolate Write Enables per array and per port
    wire we_data_w0 = we_data_trans && (cpu_target_way == 0);
    wire we_data_w1 = we_data_trans && (cpu_target_way == 1);
    wire we_tag_w0  = we_tag_trans  && (cpu_target_way == 0);
    wire we_tag_w1  = we_tag_trans  && (cpu_target_way == 1);
    
    wire cpu_we_mesi_w0   = final_cpu_we_mesi   && (cpu_target_way == 0);
    wire cpu_we_mesi_w1   = final_cpu_we_mesi   && (cpu_target_way == 1);
    wire snoop_we_mesi_w0 = final_snoop_we_mesi && (snoop_target_way == 0);
    wire snoop_we_mesi_w1 = final_snoop_we_mesi && (snoop_target_way == 1);

    // WAY 0 ARRAYS
    data_array #(.CACHE_DEPTH(CACHE_DEPTH), .LINE_WIDTH(DATA_WIDTH), .INDEX_WIDTH(INDEX_WIDTH)) 
        u_data_w0 (.clk(clk), .we(we_data_w0), .index(cpu_index), .data_in(array_data_in), .data_out(cpu_data_out_w0),
                   .snoop_index(snoop_index), .snoop_data_out(snoop_data_out_w0));
                   
    tag_array #(.CACHE_DEPTH(CACHE_DEPTH), .INDEX_WIDTH(INDEX_WIDTH), .TAG_WIDTH(TAG_WIDTH)) 
        u_tag_w0 (.clk(clk), .we(we_tag_w0), .index(cpu_index), .tag_in(cpu_tag), .tag_out(cpu_stored_tag_w0),
                  .snoop_index(snoop_index), .snoop_tag_out(snoop_stored_tag_w0));
                  
    mesi_array #(.CACHE_DEPTH(CACHE_DEPTH), .INDEX_WIDTH(INDEX_WIDTH)) 
        u_mesi_w0 (
            .clk(clk), .reset(reset), 
            .cpu_we(cpu_we_mesi_w0), .cpu_index(cpu_index), .cpu_state_in(final_cpu_next_mesi), .cpu_state_out(cpu_stored_mesi_w0),
            .snoop_we(snoop_we_mesi_w0), .snoop_index(snoop_index), .snoop_state_in(final_snoop_next_mesi), .snoop_state_out(snoop_stored_mesi_w0)
        );

    // WAY 1 ARRAYS
    data_array #(.CACHE_DEPTH(CACHE_DEPTH), .LINE_WIDTH(DATA_WIDTH), .INDEX_WIDTH(INDEX_WIDTH)) 
        u_data_w1 (.clk(clk), .we(we_data_w1), .index(cpu_index), .data_in(array_data_in), .data_out(cpu_data_out_w1),
                   .snoop_index(snoop_index), .snoop_data_out(snoop_data_out_w1));
                   
    tag_array #(.CACHE_DEPTH(CACHE_DEPTH), .INDEX_WIDTH(INDEX_WIDTH), .TAG_WIDTH(TAG_WIDTH)) 
        u_tag_w1 (.clk(clk), .we(we_tag_w1), .index(cpu_index), .tag_in(cpu_tag), .tag_out(cpu_stored_tag_w1),
                  .snoop_index(snoop_index), .snoop_tag_out(snoop_stored_tag_w1));
                  
    mesi_array #(.CACHE_DEPTH(CACHE_DEPTH), .INDEX_WIDTH(INDEX_WIDTH)) 
        u_mesi_w1 (
            .clk(clk), .reset(reset), 
            .cpu_we(cpu_we_mesi_w1), .cpu_index(cpu_index), .cpu_state_in(final_cpu_next_mesi), .cpu_state_out(cpu_stored_mesi_w1),
            .snoop_we(snoop_we_mesi_w1), .snoop_index(snoop_index), .snoop_state_in(final_snoop_next_mesi), .snoop_state_out(snoop_stored_mesi_w1)
        );

    // LRU Array
    wire lru_we = (cpu_read_complete | cpu_write_complete);
    wire lru_next = ~cpu_target_way; 
    
    lru_array #(.NUM_SETS(CACHE_DEPTH), .INDEX_WIDTH(INDEX_WIDTH))
        u_lru (.clk(clk), .reset(reset), .we(lru_we), .index(cpu_index), .lru_in(lru_next), .lru_out(lru_bit));

endmodule
