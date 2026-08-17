`timescale 1ns / 1ps

module system_top #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 128,
    parameter CACHE_DEPTH = 8,  
    parameter INDEX_WIDTH = 3,   
    parameter TAG_WIDTH   = 25,  
    parameter MEM_DEPTH   = 1024 
)(
    input wire clk,
    input wire reset,
    
    input  wire [DATA_WIDTH-1:0]  ext_mem_rdata,  
    output wire                   ext_mem_we,     
    output wire [ADDR_WIDTH-1:0]  ext_mem_addr,   
    output wire [DATA_WIDTH-1:0]  ext_mem_wdata   
);

    wire [3:0]              bus_req_vec;
    wire [3:0]              bus_grant_vec;
    
    wire [2:0]              active_bus_op;
    wire [ADDR_WIDTH-1:0]   active_bus_addr;
    wire [DATA_WIDTH-1:0]   active_bus_data; 
    
    wire [3:0]              flush_vec;
    wire [3:0]              shared_vec;
    wire                    global_shared;
    wire                    snoop_bus_req;   

    wire                    mem_ready;
    wire [DATA_WIDTH-1:0]   mem_data_out;    
    
    bus_arbiter #(.N(4)) u_arbiter (
        .clk       (clk),
        .reset     (reset),
        .bus_req   (bus_req_vec),
        .bus_grant (bus_grant_vec)
    );

    assign snoop_bus_req = |bus_grant_vec;
    assign global_shared = |shared_vec;

    wire [2:0]            c_bus_op   [0:3];
    wire [ADDR_WIDTH-1:0] c_bus_addr [0:3];
    wire [DATA_WIDTH-1:0] c_bus_data [0:3];
    wire [DATA_WIDTH-1:0] c_flush_data [0:3]; 
    
    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : CORE_COMPLEX
            
            wire                  cpu_req;
            wire                  cpu_rw;
            wire [ADDR_WIDTH-1:0] cpu_addr;
            wire [DATA_WIDTH-1:0] cpu_data_to_cache;
            wire [DATA_WIDTH-1:0] cpu_data_from_cache;
            wire                  cache_ready;

            wire [DATA_WIDTH-1:0] cache_bus_in = cpu_rw ? cpu_data_to_cache : mem_data_out;

            cpu_emulator #(
                .CORE_ID(i),
                .SEED(32'hABCD_0000 + (i * 32'h1111))
            ) u_cpu (
                .clk          (clk),
                .reset        (reset),
                .cache_ready  (cache_ready),
                .cpu_data_in  (cpu_data_from_cache),
                .cpu_req      (cpu_req),
                .cpu_rw       (cpu_rw),
                .cpu_addr     (cpu_addr),
                .cpu_data_out (cpu_data_to_cache)
            );

            cache_controller #(
                .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
                .CACHE_DEPTH(CACHE_DEPTH), .INDEX_WIDTH(INDEX_WIDTH), .TAG_WIDTH(TAG_WIDTH)
            ) u_cache (
                .clk             (clk),
                .reset           (reset),
                
                .cpu_req         (cpu_req),
                .cpu_rw          (cpu_rw),
                .cpu_addr        (cpu_addr),
                .cpu_data_in     (cpu_data_to_cache),
                .cpu_data_out    (cpu_data_from_cache),
                .cache_ready     (cache_ready),

                .bus_grant       (bus_grant_vec[i]),
                .mem_ready       (mem_ready),
                .shared_line_in  (global_shared),
                .bus_data_in     (cache_bus_in),  
                .bus_req         (bus_req_vec[i]),
                .bus_op          (c_bus_op[i]),
                .bus_addr_out    (c_bus_addr[i]),
                .bus_data_out    (c_bus_data[i]),
                .cache_flush_data_out (c_flush_data[i]),                

                .snoop_bus_req   (snoop_bus_req),
                .snoop_bus_op    (active_bus_op),
                .snoop_bus_addr  (active_bus_addr),
                .shared_line_out (shared_vec[i]),
                .flush_data      (flush_vec[i])
            );
            
        end
    endgenerate

    assign active_bus_op   = bus_grant_vec[0] ? c_bus_op[0] :
                             bus_grant_vec[1] ? c_bus_op[1] :
                             bus_grant_vec[2] ? c_bus_op[2] :
                             bus_grant_vec[3] ? c_bus_op[3] : 3'b000;

    assign active_bus_addr = bus_grant_vec[0] ? c_bus_addr[0] :
                             bus_grant_vec[1] ? c_bus_addr[1] :
                             bus_grant_vec[2] ? c_bus_addr[2] :
                             bus_grant_vec[3] ? c_bus_addr[3] : {ADDR_WIDTH{1'b0}};

    wire [DATA_WIDTH-1:0] master_bus_data = 
                             bus_grant_vec[0] ? c_bus_data[0] :
                             bus_grant_vec[1] ? c_bus_data[1] :
                             bus_grant_vec[2] ? c_bus_data[2] :
                             bus_grant_vec[3] ? c_bus_data[3] : {DATA_WIDTH{1'b0}};

    // SNOOP OVERRIDE: Exactly as it was in the working 1-Way Model!
    wire any_flush = |flush_vec;
    wire [DATA_WIDTH-1:0] flushed_bus_data = 
                             flush_vec[0] ? c_flush_data[0] :
                             flush_vec[1] ? c_flush_data[1] :
                             flush_vec[2] ? c_flush_data[2] :
                             flush_vec[3] ? c_flush_data[3] : {DATA_WIDTH{1'b0}};

    assign active_bus_data = any_flush ? flushed_bus_data : master_bus_data;

    wire                  ctrl_mem_we;
    wire [ADDR_WIDTH-1:0] mem_addr;
    wire [DATA_WIDTH-1:0] mem_write_data;
    wire [DATA_WIDTH-1:0] mem_read_data;

    memory_controller #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)
    ) u_mem_ctrl (
        .clk          (clk),
        .reset        (reset),
        
        // Bus Interface
        .bus_op       (active_bus_op),
        .bus_addr     (active_bus_addr),
        .bus_data_in  (active_bus_data), // Master write OR Snoop flush
        .mem_ready    (mem_ready),
        .bus_data_out (mem_data_out),    // Sent to all caches
        
        // Native Interface
        .mem_we       (ctrl_mem_we),
        .mem_addr     (mem_addr),
        .mem_data_out (mem_write_data),
        .mem_data_in  (mem_read_data)
    );

   
    wire final_mem_we = ctrl_mem_we | any_flush;

    assign ext_mem_we    = final_mem_we;
    assign ext_mem_addr  = mem_addr;
    assign ext_mem_wdata = mem_write_data;
    
    assign mem_read_data = ext_mem_rdata;

endmodule

