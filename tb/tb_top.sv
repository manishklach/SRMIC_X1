// ============================================================================
// Module: tb_top
// Project: SRMIC-X1
// Description: Main system-level testbench for SRMIC architecture bring-up.
//              Includes scoreboard self-checking and metric logging.
// ============================================================================

`timescale 1ns/1ps

module tb_top;

    // ==================================================
    // Parameters
    // ==================================================
    localparam CLK_PERIOD      = 1.0; // 1GHz
    localparam NUM_REGIONS     = 4;
    localparam PAGE_ID_WIDTH   = 16;
    localparam SCOREBOARD_SIZE = 256;
    localparam RUN_CYCLES      = 20000;
    localparam FIFO_DEPTH      = 32; // Increased to handle stalls

    // ==================================================
    // Ports / Signals
    // ==================================================
    logic clk, rst_n;
    logic [NUM_REGIONS-1:0] perf_hit, perf_miss;
    logic perf_promo, perf_demo;
    logic [31:0] perf_bank_conflicts;
    logic [31:0] perf_router_stalls;

    // Debug Observability Signals (for connection and waveform)
    logic [2:0]                      dbg_ric_state;
    logic [4:0]                      dbg_fifo_count;
    logic [3:0]                      dbg_credit_counter;
    logic [$clog2(NUM_REGIONS)-1:0]  dbg_selected_region;
    logic [6:0]                      dbg_occupancy [0:NUM_REGIONS-1];
    logic [31:0]                     dbg_bank_conflicts [0:NUM_REGIONS-1];
    logic [1:0]                      dbg_router_grant_port;
    logic                            dbg_router_active_vc;

    logic [NUM_REGIONS-1:0]          dbg_access_stall;
    logic [NUM_REGIONS-1:0]          dbg_response_valid;
    logic [NUM_REGIONS-1:0]          dbg_region_hit;
    logic [NUM_REGIONS-1:0]          dbg_region_miss;

    // Region-local promotion commit signals (captured via hierarchical paths)
    logic [NUM_REGIONS-1:0] hrm_promote_ack_internal;
    generate
        for (genvar r=0; r<NUM_REGIONS; r++) begin : gen_promo_ack
            assign hrm_promote_ack_internal[r] = dut.gen_regions[r].i_hrm.promote_ack;
        end
    endgenerate

    // ==================================================
    // Local state (Scoreboard & Metrics)
    // ==================================================
    longint total_cycles;
    longint total_requests;
    longint total_hits;
    longint total_misses;
    longint total_promos;
    longint total_demos;
    longint total_latency;
    
    real    avg_latency;
    real    hit_rate;
    real    miss_rate;

    int     scoreboard_errors;
    int     seed;
    int     fd;

    // --- Scoreboard Residency State ---
    typedef enum logic [1:0] { 
        NOT_RESIDENT      = 2'b00, 
        PROMOTION_PENDING = 2'b01, 
        RESIDENT          = 2'b10, 
        DEMOTION_PENDING  = 2'b11 
    } res_state_t;

    res_state_t sb_state [0:SCOREBOARD_SIZE-1];
    logic [PAGE_ID_WIDTH-1:0] sb_resident_pages [0:SCOREBOARD_SIZE-1];
    logic [$clog2(NUM_REGIONS)-1:0] sb_region [0:SCOREBOARD_SIZE-1];
    int sb_timer [0:SCOREBOARD_SIZE-1];
    
    // --- Scoreboard Response FIFOs (Per Region) ---
    typedef struct packed {
        logic [PAGE_ID_WIDTH-1:0] page_id;
        logic                     expected_hit;
    } sb_req_t;

    sb_req_t sb_fifo [0:NUM_REGIONS-1][0:FIFO_DEPTH-1];
    int sb_fifo_wr_ptr [0:NUM_REGIONS-1];
    int sb_fifo_rd_ptr [0:NUM_REGIONS-1];
    int sb_fifo_count  [0:NUM_REGIONS-1];

    // ==================================================
    // DUT Instantiation
    // ==================================================
    srmic_top #(
        .PAGE_ID_WIDTH(PAGE_ID_WIDTH),
        .NUM_REGIONS(NUM_REGIONS)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .perf_hit(perf_hit),
        .perf_miss(perf_miss),
        .perf_promo(perf_promo),
        .perf_demo(perf_demo),
        .perf_bank_conflicts(perf_bank_conflicts),
        .perf_router_stalls(perf_router_stalls),
        // Debug Connections
        .dbg_ric_state(dbg_ric_state),
        .dbg_fifo_count(dbg_fifo_count),
        .dbg_credit_counter(dbg_credit_counter),
        .dbg_selected_region(dbg_selected_region),
        .dbg_occupancy(dbg_occupancy),
        .dbg_bank_conflicts(dbg_bank_conflicts),
        .dbg_router_grant_port(dbg_router_grant_port),
        .dbg_router_active_vc(dbg_router_active_vc),
        .dbg_access_stall(dbg_access_stall),
        .dbg_response_valid(dbg_response_valid),
        .dbg_region_hit(dbg_region_hit),
        .dbg_region_miss(dbg_region_miss)
    );

    // ==================================================
    // Combinational Logic
    // ==================================================
    // (None)

    // ==================================================
    // Sequential Logic (Scoreboard)
    // ==================================================
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            scoreboard_errors <= 0;
            for (int r=0; r<NUM_REGIONS; r++) begin
                sb_fifo_wr_ptr[r]    <= 0;
                sb_fifo_rd_ptr[r]    <= 0;
                sb_fifo_count[r]     <= 0;
            end
            for (int i=0; i<SCOREBOARD_SIZE; i++) begin
                sb_state[i]          <= NOT_RESIDENT;
                sb_resident_pages[i] <= 0;
                sb_region[i]         <= 0;
                sb_timer[i]          <= 0;
            end
        end else begin
            // 1. Prediction at time of access issue (T0)
            // Access is broadcast to all regions; each determines its own expected_hit locally.
            if (dut.synth_access_valid) begin
                for (int r=0; r<NUM_REGIONS; r++) begin
                    if (!dbg_access_stall[r]) begin
                        automatic logic expected_hit_r = 1'b0;
                        for (int i=0; i<SCOREBOARD_SIZE; i++) begin
                            // A hit occurs in region 'r' only if the page is architecturally resident.
                            // PROMOTION_PENDING is NOT resident.
                            // DEMOTION_PENDING IS still resident until the demotion clears.
                            if ((sb_state[i] == RESIDENT || sb_state[i] == DEMOTION_PENDING) && 
                                (sb_resident_pages[i] == dut.synth_access_id) &&
                                (sb_region[i] == r[$clog2(NUM_REGIONS)-1:0])) begin
                                expected_hit_r = 1'b1;
                            end
                        end

                        if (sb_fifo_count[r] < FIFO_DEPTH) begin
                            sb_fifo[r][sb_fifo_wr_ptr[r]].page_id      <= dut.synth_access_id;
                            sb_fifo[r][sb_fifo_wr_ptr[r]].expected_hit <= expected_hit_r;
                            sb_fifo_wr_ptr[r] <= (sb_fifo_wr_ptr[r] + 1) % FIFO_DEPTH;
                            sb_fifo_count[r]  <= sb_fifo_count[r] + 1;
                        end else begin
                            $error("[%0t] SB_FIFO_OVERFLOW (Region %0d): Increase FIFO_DEPTH", $time, r);
                            scoreboard_errors++;
                        end
                    end
                end
            end

            // 2. Residency State Machine Updates (Aging and Demotion Commit)
            for (int i=0; i<SCOREBOARD_SIZE; i++) begin
                if (sb_timer[i] > 0) sb_timer[i] <= sb_timer[i] - 1;
                
                // Demotion transition is timer-based (1 cycle)
                if (sb_state[i] == DEMOTION_PENDING && sb_timer[i] == 1) begin
                    sb_state[i] <= NOT_RESIDENT;
                    sb_timer[i] <= 0;
                end
            end

            // 3. Handle Promotion Issue (T0)
            if (perf_promo) begin
                automatic int found = -1;
                for (int i=0; i<SCOREBOARD_SIZE; i++) begin
                    if (sb_state[i] == NOT_RESIDENT) begin 
                        found = i; 
                        break; 
                    end
                end
                if (found == -1) found = total_promos % SCOREBOARD_SIZE;
                
                sb_state[found]          <= PROMOTION_PENDING;
                sb_resident_pages[found] <= dut.promote_page_id;
                // Region ownership is NOT assigned yet; wait for commit (T4).
                sb_timer[found]          <= 4;
            end

            // 4. Handle Promotion Commit (T4 - Region Ownership Assigned)
            for (int r=0; r<NUM_REGIONS; r++) begin
                if (hrm_promote_ack_internal[r]) begin
                    automatic logic found_pending = 1'b0;
                    for (int i=0; i<SCOREBOARD_SIZE; i++) begin
                        // Find the oldest pending promotion that is ready to commit
                        if (sb_state[i] == PROMOTION_PENDING && sb_timer[i] <= 1) begin
                            sb_state[i]  <= RESIDENT;
                            sb_region[i] <= r[$clog2(NUM_REGIONS)-1:0];
                            sb_timer[i]  <= 0;
                            found_pending = 1'b1;
                            break;
                        end
                    end
                    if (!found_pending) begin
                        $error("[%0t] SB_ERROR: Promotion ack for region %0d but no pending promo found in scoreboard", $time, r);
                        scoreboard_errors++;
                    end
                end
            end

            // 5. Handle Demotions (1 cycle latency)
            if (perf_demo) begin
                for (int i=0; i<SCOREBOARD_SIZE; i++) begin
                    if (sb_state[i] != NOT_RESIDENT && 
                        sb_resident_pages[i] == dut.demote_page_id &&
                        sb_region[i] == dbg_selected_region) begin 
                        sb_state[i] <= DEMOTION_PENDING;
                        sb_timer[i] <= 1;
                        break;
                    end
                end
            end
            
            // 6. Validate at Response Time (Per Region)
            for (int r=0; r<NUM_REGIONS; r++) begin
                if (dbg_response_valid[r]) begin
                    if (sb_fifo_count[r] > 0) begin
                        automatic sb_req_t req = sb_fifo[r][sb_fifo_rd_ptr[r]];
                        automatic logic actual_hit = perf_hit[r];
                        
                        if (actual_hit != req.expected_hit) begin
                            $error("[%0t] SB_MISMATCH (Region %0d): Page 0x%h, Expected %s, Got %s", 
                                   $time, r, req.page_id, 
                                   req.expected_hit ? "HIT" : "MISS",
                                   actual_hit ? "HIT" : "MISS");
                            scoreboard_errors++;
                        end
                        
                        sb_fifo_rd_ptr[r] <= (sb_fifo_rd_ptr[r] + 1) % FIFO_DEPTH;
                        sb_fifo_count[r]  <= sb_fifo_count[r] - 1;
                    end else begin
                        $error("[%0t] SB_UNEXPECTED_RESPONSE (Region %0d): No pending request in FIFO", $time, r);
                        scoreboard_errors++;
                    end
                end
            end
        end
    end

    // ==================================================
    // Clock Generation
    // ==================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // ==================================================
    // Main Control
    // ==================================================
    initial begin
        // Seed handling
        if (!$value$plusargs("seed=%d", seed)) seed = 1234;
        $display("[%0t] SIM SEED: %0d", $time, seed);

        // Waveform Dump
        $dumpfile("srmic_trace.vcd");
        $dumpvars(0, tb_top);

        // Initial State
        total_cycles   = 0;
        total_requests = 0;
        total_hits     = 0;
        total_misses   = 0;
        total_promos   = 0;
        total_demos    = 0;
        total_latency  = 0;

        // Reset Pulse
        rst_n = 0;
        #(CLK_PERIOD * 20);
        rst_n = 1;

        $display("[%0t] Starting SRMIC bring-up simulation (%0d cycles)...", $time, RUN_CYCLES);

        repeat (RUN_CYCLES) begin
            @(posedge clk);
            total_cycles++;
            
            for (int i=0; i<NUM_REGIONS; i++) begin
                if (perf_hit[i]) begin
                    total_hits++; 
                    total_requests++; 
                    total_latency += 2; // Modeled hit cost
                end
                if (perf_miss[i]) begin
                    total_misses++; 
                    total_requests++; 
                    total_latency += 6; // Modeled miss cost
                end
            end
            if (perf_promo) total_promos++;
            if (perf_demo)  total_demos++;
        end

        // Computation
        if (total_requests > 0) begin
            avg_latency = real'(total_latency) / total_requests;
            hit_rate    = (real'(total_hits) / total_requests) * 100.0;
            miss_rate   = (real'(total_misses) / total_requests) * 100.0;
        end

        // Summary Printout
        $display("\n============================================================");
        $display("SRMIC RTL SIM SUMMARY");
        $display("============================================================");
        $display("Total cycles:       %0d", total_cycles);
        $display("Total requests:     %0d", total_requests);
        $display("Hits:               %0d", total_hits);
        $display("Misses:             %0d", total_misses);
        $display("Promotions:         %0d", total_promos);
        $display("Demotions:          %0d", total_demos);
        $display("Bank conflicts:     %0d", perf_bank_conflicts);
        $display("Router stalls:      %0d", perf_router_stalls);
        $display("Average latency:    %2.2f cycles", avg_latency);
        $display("Hit rate:           %2.2f%%", hit_rate);
        $display("Miss rate:          %2.2f%%", miss_rate);
        $display("------------------------------------------------------------");
        if (scoreboard_errors == 0) $display("SRMIC RTL TEST: PASS");
        else                        $display("SRMIC RTL TEST: FAIL (%0d errors)", scoreboard_errors);
        $display("============================================================\n");

        // Logging
        fd = $fopen("sim_results.log", "w");
        if (fd) begin
            $fdisplay(fd, "cycles=%0d", total_cycles);
            $fdisplay(fd, "requests=%0d", total_requests);
            $fdisplay(fd, "hits=%0d", total_hits);
            $fdisplay(fd, "misses=%0d", total_misses);
            $fdisplay(fd, "promotions=%0d", total_promos);
            $fdisplay(fd, "demotions=%0d", total_demos);
            $fdisplay(fd, "latency=%2.2f", avg_latency);
            $fdisplay(fd, "hit_rate=%2.2f", hit_rate);
            $fdisplay(fd, "status=%s", (scoreboard_errors == 0) ? "PASS" : "FAIL");
            $fclose(fd);
        end

        $finish;
    end

    // ==================================================
    // Assertions
    // ==================================================
`ifndef SYNTHESIS
    // Check for obvious simulation hangs or deadlocks
    assert property (@(posedge clk) total_cycles < 100000);
`endif

endmodule
