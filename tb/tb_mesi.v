`timescale 1ns / 1ps

module tb_system ();

    // ------------------------------------------------------------------------
    // Clock and Reset Generation
    // ------------------------------------------------------------------------
    reg clk;
    reg reset;

    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100 MHz clock
    end

    initial begin
        reset = 1;
        #55 reset = 0; // Release reset out of sync with clock edge
    end

    // ------------------------------------------------------------------------
    // Wires for External Memory Interface
    // ------------------------------------------------------------------------
    wire [127:0] ext_mem_rdata;
    wire         ext_mem_we;
    wire [31:0]  ext_mem_addr;
    wire [127:0] ext_mem_wdata;

    // ------------------------------------------------------------------------
    // DUT Instantiation
    // ------------------------------------------------------------------------
    system_top #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(128),
        .CACHE_DEPTH(8),
        .INDEX_WIDTH(3),
        .TAG_WIDTH(25)
    ) dut (
        .clk           (clk),
        .reset         (reset),
        .ext_mem_rdata (ext_mem_rdata),
        .ext_mem_we    (ext_mem_we),
        .ext_mem_addr  (ext_mem_addr),
        .ext_mem_wdata (ext_mem_wdata)
    );

    // ------------------------------------------------------------------------
    // Connect Main Memory to the new interface
    // ------------------------------------------------------------------------
    main_memory #(
        .ADDR_WIDTH(32), 
        .DATA_WIDTH(128),
        .MEM_DEPTH(1024)
    ) u_main_memory (
        .clk      (clk),
        .we       (ext_mem_we),
        .addr     (ext_mem_addr),
        .data_in  (ext_mem_wdata),
        .data_out (ext_mem_rdata)
    );

    // ========================================================================
    // ELABORATION-TIME PROBES (Verilog-2001 compatible)
    // ========================================================================
    wire         probe_cpu_req_0, probe_cpu_req_1, probe_cpu_req_2, probe_cpu_req_3;
    wire         probe_cache_ready_0, probe_cache_ready_1, probe_cache_ready_2, probe_cache_ready_3;
    wire         probe_cpu_rw_0, probe_cpu_rw_1, probe_cpu_rw_2, probe_cpu_rw_3;
    wire [31:0]  probe_cpu_addr_0, probe_cpu_addr_1, probe_cpu_addr_2, probe_cpu_addr_3;
    wire [127:0] probe_cpu_data_out_0, probe_cpu_data_out_1, probe_cpu_data_out_2, probe_cpu_data_out_3;
    wire [127:0] probe_cpu_data_in_0, probe_cpu_data_in_1, probe_cpu_data_in_2, probe_cpu_data_in_3;

    assign probe_cpu_req_0      = dut.CORE_COMPLEX[0].u_cpu.cpu_req;
    assign probe_cache_ready_0  = dut.CORE_COMPLEX[0].u_cpu.cache_ready;
    assign probe_cpu_rw_0       = dut.CORE_COMPLEX[0].u_cpu.cpu_rw;
    assign probe_cpu_addr_0     = dut.CORE_COMPLEX[0].u_cpu.cpu_addr;
    assign probe_cpu_data_out_0 = dut.CORE_COMPLEX[0].u_cpu.cpu_data_out;
    assign probe_cpu_data_in_0  = dut.CORE_COMPLEX[0].u_cpu.cpu_data_in;

    assign probe_cpu_req_1      = dut.CORE_COMPLEX[1].u_cpu.cpu_req;
    assign probe_cache_ready_1  = dut.CORE_COMPLEX[1].u_cpu.cache_ready;
    assign probe_cpu_rw_1       = dut.CORE_COMPLEX[1].u_cpu.cpu_rw;
    assign probe_cpu_addr_1     = dut.CORE_COMPLEX[1].u_cpu.cpu_addr;
    assign probe_cpu_data_out_1 = dut.CORE_COMPLEX[1].u_cpu.cpu_data_out;
    assign probe_cpu_data_in_1  = dut.CORE_COMPLEX[1].u_cpu.cpu_data_in;

    assign probe_cpu_req_2      = dut.CORE_COMPLEX[2].u_cpu.cpu_req;
    assign probe_cache_ready_2  = dut.CORE_COMPLEX[2].u_cpu.cache_ready;
    assign probe_cpu_rw_2       = dut.CORE_COMPLEX[2].u_cpu.cpu_rw;
    assign probe_cpu_addr_2     = dut.CORE_COMPLEX[2].u_cpu.cpu_addr;
    assign probe_cpu_data_out_2 = dut.CORE_COMPLEX[2].u_cpu.cpu_data_out;
    assign probe_cpu_data_in_2  = dut.CORE_COMPLEX[2].u_cpu.cpu_data_in;

    assign probe_cpu_req_3      = dut.CORE_COMPLEX[3].u_cpu.cpu_req;
    assign probe_cache_ready_3  = dut.CORE_COMPLEX[3].u_cpu.cache_ready;
    assign probe_cpu_rw_3       = dut.CORE_COMPLEX[3].u_cpu.cpu_rw;
    assign probe_cpu_addr_3     = dut.CORE_COMPLEX[3].u_cpu.cpu_addr;
    assign probe_cpu_data_out_3 = dut.CORE_COMPLEX[3].u_cpu.cpu_data_out;
    assign probe_cpu_data_in_3  = dut.CORE_COMPLEX[3].u_cpu.cpu_data_in;

    wire probe_cache_hit_0 = dut.CORE_COMPLEX[0].u_cache.cache_hit;
    wire probe_cache_hit_1 = dut.CORE_COMPLEX[1].u_cache.cache_hit;
    wire probe_cache_hit_2 = dut.CORE_COMPLEX[2].u_cache.cache_hit;
    wire probe_cache_hit_3 = dut.CORE_COMPLEX[3].u_cache.cache_hit;

    // ========================================================================
    // CHECKPOINT LOGGER (The Event Trace)
    // ========================================================================
    reg [3:0] prev_grant;
    integer master;
    reg [55:0] op_str; // 7 characters * 8 bits
    integer snooper;

    always @(posedge clk) begin
        if (!reset) begin
            // 1. Log Bus Acquisitions
            if (dut.bus_grant_vec != 0 && prev_grant == 0) begin
                master = 0;
                if(dut.bus_grant_vec[0]) master = 0;
                if(dut.bus_grant_vec[1]) master = 1;
                if(dut.bus_grant_vec[2]) master = 2;
                if(dut.bus_grant_vec[3]) master = 3;
                
                case(dut.active_bus_op)
                    3'b001: op_str = "BusRd  ";
                    3'b010: op_str = "BusRdX ";
                    3'b011: op_str = "BusUpgr";
                    3'b100: op_str = "BusWB  ";
                    default: op_str = "UNKNOWN";
                endcase
                $display("[CHKPT %0t] BUS   | Core %0d Acquired Bus | Op: %s | Addr: %0h", 
                         $time, master, op_str, dut.active_bus_addr);
            end
            prev_grant <= dut.bus_grant_vec;

            // 2. Log Memory Responses
            if (dut.mem_ready) begin
                $display("[CHKPT %0t] MEM   | Memory Ready Pulse | Data: %h", $time, dut.mem_data_out);
            end

            // 3. Log Snoop Flushes
            if (dut.any_flush) begin
                snooper = 0;
                if(dut.flush_vec[0]) snooper = 0;
                if(dut.flush_vec[1]) snooper = 1;
                if(dut.flush_vec[2]) snooper = 2;
                if(dut.flush_vec[3]) snooper = 3;
                $display("[CHKPT %0t] SNOOP | Core %0d FLUSHED Dirty Data | Data: %h", 
                         $time, snooper, dut.flushed_bus_data);
            end

            // 4. Log CPU Completions 
            if (probe_cpu_req_0 && probe_cache_ready_0) begin
                $display("[CHKPT %0t] CPU   | Core 0 Completed %s | Block %0d | Data: %h", 
                         $time, probe_cpu_rw_0 ? "WRITE" : "READ ", (probe_cpu_addr_0[31:4])%1024, probe_cpu_rw_0 ? probe_cpu_data_out_0 : probe_cpu_data_in_0);
            end
            if (probe_cpu_req_1 && probe_cache_ready_1) begin
                $display("[CHKPT %0t] CPU   | Core 1 Completed %s | Block %0d | Data: %h", 
                         $time, probe_cpu_rw_1 ? "WRITE" : "READ ", (probe_cpu_addr_1[31:4])%1024, probe_cpu_rw_1 ? probe_cpu_data_out_1 : probe_cpu_data_in_1);
            end
            if (probe_cpu_req_2 && probe_cache_ready_2) begin
                $display("[CHKPT %0t] CPU   | Core 2 Completed %s | Block %0d | Data: %h", 
                         $time, probe_cpu_rw_2 ? "WRITE" : "READ ", (probe_cpu_addr_2[31:4])%1024, probe_cpu_rw_2 ? probe_cpu_data_out_2 : probe_cpu_data_in_2);
            end
            if (probe_cpu_req_3 && probe_cache_ready_3) begin
                $display("[CHKPT %0t] CPU   | Core 3 Completed %s | Block %0d | Data: %h", 
                         $time, probe_cpu_rw_3 ? "WRITE" : "READ ", (probe_cpu_addr_3[31:4])%1024, probe_cpu_rw_3 ? probe_cpu_data_out_3 : probe_cpu_data_in_3);
            end
        end
    end

    // ------------------------------------------------------------------------
    // Verification Architecture: Golden Scoreboard
    // ------------------------------------------------------------------------
    reg [127:0] golden_mem [0:1023];
    integer i;

    initial begin
        for (i = 0; i < 1024; i = i + 1) golden_mem[i] = 128'd0;
    end

    integer total_reads  = 0;
    integer total_writes = 0;
    integer total_cycles = 0;

    // --- HIT RATE COUNTERS ---
    integer core_hits_0 = 0, core_misses_0 = 0;
    integer core_hits_1 = 0, core_misses_1 = 0;
    integer core_hits_2 = 0, core_misses_2 = 0;
    integer core_hits_3 = 0, core_misses_3 = 0;

    reg prev_cpu_req_0 = 0, prev_cpu_req_1 = 0, prev_cpu_req_2 = 0, prev_cpu_req_3 = 0;

    integer block_addr_0, block_addr_1, block_addr_2, block_addr_3;

    // ------------------------------------------------------------------------
    // Data Integrity Checker & Hit Tracking (Instant Validation)
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!reset) begin
            total_cycles = total_cycles + 1;
            
            // --- HIT RATE TRACKING ---
            if (probe_cpu_req_0 && !prev_cpu_req_0) begin
                if (probe_cache_hit_0) core_hits_0 = core_hits_0 + 1;
                else                   core_misses_0 = core_misses_0 + 1;
            end
            if (probe_cpu_req_1 && !prev_cpu_req_1) begin
                if (probe_cache_hit_1) core_hits_1 = core_hits_1 + 1;
                else                   core_misses_1 = core_misses_1 + 1;
            end
            if (probe_cpu_req_2 && !prev_cpu_req_2) begin
                if (probe_cache_hit_2) core_hits_2 = core_hits_2 + 1;
                else                   core_misses_2 = core_misses_2 + 1;
            end
            if (probe_cpu_req_3 && !prev_cpu_req_3) begin
                if (probe_cache_hit_3) core_hits_3 = core_hits_3 + 1;
                else                   core_misses_3 = core_misses_3 + 1;
            end
            
            prev_cpu_req_0 <= probe_cpu_req_0;
            prev_cpu_req_1 <= probe_cpu_req_1;
            prev_cpu_req_2 <= probe_cpu_req_2;
            prev_cpu_req_3 <= probe_cpu_req_3;

            // --- INSTANT VALIDATION ---
            // CORE 0
            if (probe_cpu_req_0 && probe_cache_ready_0) begin
                block_addr_0 = (probe_cpu_addr_0[31:4]) % 1024;
                if (probe_cpu_rw_0 == 1'b1) begin
                    golden_mem[block_addr_0] = probe_cpu_data_out_0;
                    total_writes = total_writes + 1;
                end else begin
                    if (probe_cpu_data_in_0 !== golden_mem[block_addr_0]) begin
                        $display("==================================================");
                        $display("[Time %0t] DATA INTEGRITY FAILURE! Core 0 read corrupted data at Block %0d.\nExpected: %h\nReceived: %h", 
                                  $time, block_addr_0, golden_mem[block_addr_0], probe_cpu_data_in_0);
                        $finish;
                    end else begin
                        total_reads = total_reads + 1;
                    end
                end
            end
            
            // CORE 1
            if (probe_cpu_req_1 && probe_cache_ready_1) begin
                block_addr_1 = (probe_cpu_addr_1[31:4]) % 1024;
                if (probe_cpu_rw_1 == 1'b1) begin
                    golden_mem[block_addr_1] = probe_cpu_data_out_1;
                    total_writes = total_writes + 1;
                end else begin
                    if (probe_cpu_data_in_1 !== golden_mem[block_addr_1]) begin
                        $display("==================================================");
                        $display("[Time %0t] DATA INTEGRITY FAILURE! Core 1 read corrupted data at Block %0d.\nExpected: %h\nReceived: %h", 
                                  $time, block_addr_1, golden_mem[block_addr_1], probe_cpu_data_in_1);
                        $finish;
                    end else begin
                        total_reads = total_reads + 1;
                    end
                end
            end
            
            // CORE 2
            if (probe_cpu_req_2 && probe_cache_ready_2) begin
                block_addr_2 = (probe_cpu_addr_2[31:4]) % 1024;
                if (probe_cpu_rw_2 == 1'b1) begin
                    golden_mem[block_addr_2] = probe_cpu_data_out_2;
                    total_writes = total_writes + 1;
                end else begin
                    if (probe_cpu_data_in_2 !== golden_mem[block_addr_2]) begin
                        $display("==================================================");
                        $display("[Time %0t] DATA INTEGRITY FAILURE! Core 2 read corrupted data at Block %0d.\nExpected: %h\nReceived: %h", 
                                  $time, block_addr_2, golden_mem[block_addr_2], probe_cpu_data_in_2);
                        $finish;
                    end else begin
                        total_reads = total_reads + 1;
                    end
                end
            end
            
            // CORE 3
            if (probe_cpu_req_3 && probe_cache_ready_3) begin
                block_addr_3 = (probe_cpu_addr_3[31:4]) % 1024;
                if (probe_cpu_rw_3 == 1'b1) begin
                    golden_mem[block_addr_3] = probe_cpu_data_out_3;
                    total_writes = total_writes + 1;
                end else begin
                    if (probe_cpu_data_in_3 !== golden_mem[block_addr_3]) begin
                        $display("==================================================");
                        $display("[Time %0t] DATA INTEGRITY FAILURE! Core 3 read corrupted data at Block %0d.\nExpected: %h\nReceived: %h", 
                                  $time, block_addr_3, golden_mem[block_addr_3], probe_cpu_data_in_3);
                        $finish;
                    end else begin
                        total_reads = total_reads + 1;
                    end
                end
            end
        end
    end

    // ------------------------------------------------------------------------
    // The MESI Protocol Police (2-Way Set Associative Version)
    // ------------------------------------------------------------------------
    integer idx;
    integer c1, c2;
    reg [3:0]  state_arr [0:7];
    reg [31:0] tag_arr   [0:7];

    always @(negedge clk) begin
        if (!reset) begin
            // Loop through all 8 indices in the Cache Depth
            for (idx = 0; idx < 8; idx = idx + 1) begin
                
                // Extract all 8 possible states and tags for this index (4 Cores x 2 Ways)
                // Core 0
                state_arr[0] = dut.CORE_COMPLEX[0].u_cache.u_mesi_w0.mem[idx];
                tag_arr[0]   = dut.CORE_COMPLEX[0].u_cache.u_tag_w0.mem[idx];
                state_arr[1] = dut.CORE_COMPLEX[0].u_cache.u_mesi_w1.mem[idx];
                tag_arr[1]   = dut.CORE_COMPLEX[0].u_cache.u_tag_w1.mem[idx];
                
                // Core 1
                state_arr[2] = dut.CORE_COMPLEX[1].u_cache.u_mesi_w0.mem[idx];
                tag_arr[2]   = dut.CORE_COMPLEX[1].u_cache.u_tag_w0.mem[idx];
                state_arr[3] = dut.CORE_COMPLEX[1].u_cache.u_mesi_w1.mem[idx];
                tag_arr[3]   = dut.CORE_COMPLEX[1].u_cache.u_tag_w1.mem[idx];
                
                // Core 2
                state_arr[4] = dut.CORE_COMPLEX[2].u_cache.u_mesi_w0.mem[idx];
                tag_arr[4]   = dut.CORE_COMPLEX[2].u_cache.u_tag_w0.mem[idx];
                state_arr[5] = dut.CORE_COMPLEX[2].u_cache.u_mesi_w1.mem[idx];
                tag_arr[5]   = dut.CORE_COMPLEX[2].u_cache.u_tag_w1.mem[idx];
                
                // Core 3
                state_arr[6] = dut.CORE_COMPLEX[3].u_cache.u_mesi_w0.mem[idx];
                tag_arr[6]   = dut.CORE_COMPLEX[3].u_cache.u_tag_w0.mem[idx];
                state_arr[7] = dut.CORE_COMPLEX[3].u_cache.u_mesi_w1.mem[idx];
                tag_arr[7]   = dut.CORE_COMPLEX[3].u_cache.u_tag_w1.mem[idx];

                // Compare every valid line against every other valid line across the entire set
                for (c1 = 0; c1 < 8; c1 = c1 + 1) begin
                    if (state_arr[c1] != 4'b0001) begin 
                        
                        for (c2 = c1 + 1; c2 < 8; c2 = c2 + 1) begin
                            if ((state_arr[c2] != 4'b0001) && (tag_arr[c1] == tag_arr[c2])) begin
                                
                                // 1. Associativity Verification: Check if a core allocated the same tag in both its ways
                                if ((c1 / 2) == (c2 / 2)) begin
                                    $display("[Time %0t] ASSOCIATIVITY VIOLATION! Core %0d allocated the same tag in both ways.", $time, (c1/2));
                                    $finish;
                                end
                                
                                // 2. Coherence Verification: Ensure MESI rules are upheld across different cores
                                if (state_arr[c1] == 4'b1000 || state_arr[c2] == 4'b1000) begin
                                    $display("[Time %0t] MESI VIOLATION! Core %0d and Core %0d hold the same block, but one is in MODIFIED state.", $time, (c1/2), (c2/2));
                                    $finish;
                                end
                                
                                if (state_arr[c1] == 4'b0100 || state_arr[c2] == 4'b0100) begin
                                    $display("[Time %0t] MESI VIOLATION! Core %0d and Core %0d hold the same block, but one is in EXCLUSIVE state.", $time, (c1/2), (c2/2));
                                    $finish;
                                end
                                
                                if (state_arr[c1] != 4'b0010 || state_arr[c2] != 4'b0010) begin
                                    $display("[Time %0t] MESI VIOLATION! Core %0d and Core %0d hold the same block, but are not both in SHARED state.", $time, (c1/2), (c2/2));
                                    $finish;
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    // ------------------------------------------------------------------------
    // Simulation Control
    // ------------------------------------------------------------------------
    integer sys_hits, sys_misses, sys_accesses;

    initial begin
        $display("==================================================");
        $display("Starting Kamikaze MESI 2-Way Verification");
        $display("==================================================");
        
        #500000; 

        $display("==================================================");
        $display("              SIMULATION COMPLETE                 ");
        $display("==================================================");
        $display("Total Clock Cycles Run : %0d", total_cycles);
        $display("Total Read Operations  : %0d", total_reads);
        $display("Total Write Operations : %0d", total_writes);
        $display("Status                 : ZERO MESI VIOLATIONS.");
        $display("Status                 : ZERO DATA CORRUPTIONS.");
        
        // --- PRINT HIT RATES ---
        $display("==================================================");
        $display(" CACHE PERFORMANCE STATISTICS (HIT RATE) ");
        $display("==================================================");
        
        sys_hits = core_hits_0 + core_hits_1 + core_hits_2 + core_hits_3;
        sys_misses = core_misses_0 + core_misses_1 + core_misses_2 + core_misses_3;
        sys_accesses = sys_hits + sys_misses;
        
        $display(" CORE 0: %0d Hits, %0d Misses", core_hits_0, core_misses_0);
        $display(" CORE 1: %0d Hits, %0d Misses", core_hits_1, core_misses_1);
        $display(" CORE 2: %0d Hits, %0d Misses", core_hits_2, core_misses_2);
        $display(" CORE 3: %0d Hits, %0d Misses", core_hits_3, core_misses_3);
        $display("--------------------------------------------------");
        $display(" SYSTEM : %0d Hits, %0d Misses | GLOBAL HIT RATE: %0d%%", sys_hits, sys_misses, (sys_accesses > 0) ? (sys_hits * 100 / sys_accesses) : 0);
        $display("==================================================");
        
        $finish;
    end
endmodule
