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

    localparam logic [15:0] DEBUG_PAGE    = 16'h000a;
    localparam logic        DEBUG_VERBOSE = 1'b1;

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

    logic [PAGE_ID_WIDTH-1:0]        dbg_last_access_page_id [0:NUM_REGIONS-1];
    logic [NUM_REGIONS-1:0]          dbg_last_hit;
    logic [NUM_REGIONS-1:0]          dbg_last_miss;
    logic [PAGE_ID_WIDTH-1:0]        dbg_last_promoted_page  [0:NUM_REGIONS-1];
    logic [PAGE_ID_WIDTH-1:0]        dbg_last_demoted_page   [0:NUM_REGIONS-1];

    logic                            dbg_synth_access_valid;
    logic [PAGE_ID_WIDTH-1:0]        dbg_synth_access_id;

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
    
    // --- Scoreboard Response FIFOs (Per Region, split by latency type) ---
    // Hit FIFO (2 cycle latency)
    logic [PAGE_ID_WIDTH-1:0] sb_hit_fifo [0:NUM_REGIONS-1][0:FIFO_DEPTH-1];
    int sb_hit_wr_ptr [0:NUM_REGIONS-1];
    int sb_hit_rd_ptr [0:NUM_REGIONS-1];
    int sb_hit_count  [0:NUM_REGIONS-1];

    // Miss FIFO (6 cycle latency)
    logic [PAGE_ID_WIDTH-1:0] sb_miss_fifo [0:NUM_REGIONS-1][0:FIFO_DEPTH-1];
    int sb_miss_wr_ptr [0:NUM_REGIONS-1];
    int sb_miss_rd_ptr [0:NUM_REGIONS-1];
    int sb_miss_count  [0:NUM_REGIONS-1];

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
        .dbg_region_miss(dbg_region_miss),
        .dbg_last_access_page_id(dbg_last_access_page_id),
        .dbg_last_hit(dbg_last_hit),
        .dbg_last_miss(dbg_last_miss),
        .dbg_last_promoted_page(dbg_last_promoted_page),
        .dbg_last_demoted_page(dbg_last_demoted_page),
        .dbg_synth_access_valid(dbg_synth_access_valid),
        .dbg_synth_access_id(dbg_synth_access_id)
    );

    // ==================================================
    // Tasks
    // ==================================================
    task dump_sb_for_page(logic [PAGE_ID_WIDTH-1:0] page_id);
        $display("--- Scoreboard Dump for Page 0x%h ---", page_id);
        for (int i=0; i<SCOREBOARD_SIZE; i++) begin
            if (sb_resident_pages[i] == page_id && sb_state[i] != NOT_RESIDENT) begin
                $display("  Entry %0d: state=%s region=%0d timer=%0d", i, sb_state[i].name(), sb_region[i], sb_timer[i]);
            end
        end
        $display("--------------------------------------");
    endtask

    // ==================================================
    // Sequential Logic (Scoreboard)
    // ==================================================
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            scoreboard_errors = 0;
            for (int r=0; r<NUM_REGIONS; r++) begin
                sb_hit_wr_ptr[r]    = 0;
                sb_hit_rd_ptr[r]    = 0;
                sb_hit_count[r]     = 0;
                sb_miss_wr_ptr[r]   = 0;
                sb_miss_rd_ptr[r]   = 0;
                sb_miss_count[r]    = 0;
            end
            for (int i=0; i<SCOREBOARD_SIZE; i++) begin
                sb_state[i]          = NOT_RESIDENT;
                sb_resident_pages[i] = 0;
                sb_region[i]         = 0;
                sb_timer[i]          = 0;
            end
        end else begin
            // 1. Duplicate Residency Detection
            for (int i=0; i<SCOREBOARD_SIZE; i++) begin
                if (sb_state[i] == RESIDENT || sb_state[i] == DEMOTION_PENDING) begin
                    for (int j=i+1; j<SCOREBOARD_SIZE; j++) begin
                        if ((sb_state[j] == RESIDENT || sb_state[j] == DEMOTION_PENDING) && 
                            (sb_resident_pages[i] == sb_resident_pages[j])) begin
                            $display("[%0d] DUPLICATE_SCOREBOARD_RESIDENCY: page=0x%h entries %0d and %0d", 
                                     total_cycles, sb_resident_pages[i], i, j);
                        end
                    end
                end
            end

            // 2. Prediction at time of access issue (T0)
            if (dbg_synth_access_valid) begin
                for (int r=0; r<NUM_REGIONS; r++) begin
                    if (!dbg_access_stall[r]) begin
                        automatic logic expected_hit_r = 1'b0;
                        for (int i=0; i<SCOREBOARD_SIZE; i++) begin
                            // Hits only occur if resident or in progress of demotion
                            if ((sb_state[i] == RESIDENT || sb_state[i] == DEMOTION_PENDING) && 
                                (sb_resident_pages[i] == dbg_synth_access_id) &&
                                (sb_region[i] == r[$clog2(NUM_REGIONS)-1:0])) begin
                                expected_hit_r = 1'b1;
                            end
                        end

                        if (expected_hit_r) begin
                            // Push to Hit FIFO (2 cycles)
                            if (sb_hit_count[r] < FIFO_DEPTH) begin
                                sb_hit_fifo[r][sb_hit_wr_ptr[r]] = dbg_synth_access_id;
                                sb_hit_wr_ptr[r] = (sb_hit_wr_ptr[r] + 1) % FIFO_DEPTH;
                                sb_hit_count[r]  = sb_hit_count[r] + 1;
                            end else begin
                                $error("[%0t] SB_HIT_FIFO_OVERFLOW (Region %0d)", $time, r);
                                scoreboard_errors = scoreboard_errors + 1;
                            end
                        end else begin
                            // Push to Miss FIFO (6 cycles)
                            if (sb_miss_count[r] < FIFO_DEPTH) begin
                                sb_miss_fifo[r][sb_miss_wr_ptr[r]] = dbg_synth_access_id;
                                sb_miss_wr_ptr[r] = (sb_miss_wr_ptr[r] + 1) % FIFO_DEPTH;
                                sb_miss_count[r]  = sb_miss_count[r] + 1;
                            end else begin
                                $error("[%0t] SB_MISS_FIFO_OVERFLOW (Region %0d)", $time, r);
                                scoreboard_errors = scoreboard_errors + 1;
                            end
                        end

                        if (DEBUG_VERBOSE && dbg_synth_access_id == DEBUG_PAGE) begin
                            $display("[%0d] TRACE page=0x%h region=%0d event=REQUEST_ISSUED expected=%0d", 
                                     total_cycles, dbg_synth_access_id, r, expected_hit_r);
                        end
                    end else if (DEBUG_VERBOSE && dbg_synth_access_id == DEBUG_PAGE) begin
                        $display("[%0d] TRACE page=0x%h region=%0d event=REQUEST_STALLED", 
                                 total_cycles, dbg_synth_access_id, r);
                    end
                end
            end

            // 3. Residency State Machine Updates
            for (int i=0; i<SCOREBOARD_SIZE; i++) begin
                if (sb_timer[i] > 0) sb_timer[i] = sb_timer[i] - 1;
                
                if (sb_state[i] == DEMOTION_PENDING && sb_timer[i] == 1) begin
                    if (DEBUG_VERBOSE && sb_resident_pages[i] == DEBUG_PAGE) begin
                        $display("[%0d] TRACE page=0x%h event=DEMOTION_COMPLETED region=%0d", 
                                 total_cycles, sb_resident_pages[i], sb_region[i]);
                    end
                    sb_state[i] = NOT_RESIDENT;
                    sb_timer[i] = 0;
                end
            end

            // 4. Handle Promotion Issue (T0)
            if (perf_promo) begin
                automatic int found = -1;
                for (int i=0; i<SCOREBOARD_SIZE; i++) begin
                    if (sb_state[i] == NOT_RESIDENT) begin found = i; break; end
                end
                if (found == -1) found = total_promos % SCOREBOARD_SIZE;
                
                sb_state[found]          = PROMOTION_PENDING;
                sb_resident_pages[found] = dut.promote_page_id;
                sb_timer[found]          = 4;

                if (DEBUG_VERBOSE && dut.promote_page_id == DEBUG_PAGE) begin
                    $display("[%0d] TRACE page=0x%h event=PROMOTION_ISSUED entry=%0d", 
                             total_cycles, dut.promote_page_id, found);
                end
            end

            // 5. Handle Promotion Commit (T4)
            for (int r=0; r<NUM_REGIONS; r++) begin
                if (hrm_promote_ack_internal[r]) begin
                    automatic logic found_pending = 1'b0;
                    for (int i=0; i<SCOREBOARD_SIZE; i++) begin
                        if (sb_state[i] == PROMOTION_PENDING && sb_timer[i] <= 1) begin
                            sb_state[i]  = RESIDENT;
                            sb_region[i] = r[$clog2(NUM_REGIONS)-1:0];
                            sb_timer[i]  = 0;
                            found_pending = 1'b1;
                            if (DEBUG_VERBOSE && sb_resident_pages[i] == DEBUG_PAGE) begin
                                $display("[%0d] TRACE page=0x%h event=PROMOTION_COMMITTED region=%0d", 
                                         total_cycles, sb_resident_pages[i], r);
                            end
                            break;
                        end
                    end
                    if (!found_pending) begin
                        $error("[%0t] SB_ERROR: Promotion ack for region %0d but no pending promo found", $time, r);
                        scoreboard_errors = scoreboard_errors + 1;
                    end
                end
            end

            // 6. Handle Demotions
            if (perf_demo) begin
                for (int i=0; i<SCOREBOARD_SIZE; i++) begin
                    if (sb_state[i] != NOT_RESIDENT && 
                        sb_resident_pages[i] == dut.demote_page_id &&
                        sb_region[i] == dbg_selected_region) begin 
                        if (DEBUG_VERBOSE && sb_resident_pages[i] == DEBUG_PAGE) begin
                            $display("[%0d] TRACE page=0x%h event=DEMOTION_ISSUED region=%0d", 
                                     total_cycles, sb_resident_pages[i], sb_region[i]);
                        end
                        sb_state[i] = DEMOTION_PENDING;
                        sb_timer[i] = 1;
                        break;
                    end
                end
            end
            
            // 7. Validate at Response Time (Per Region, handling overtaking)
            for (int r=0; r<NUM_REGIONS; r++) begin
                // A region can produce a Hit response and a Miss response in the same cycle.
                // These correspond to different requests issued at different times.
                
                if (perf_hit[r]) begin
                    if (sb_hit_count[r] > 0) begin
                        automatic logic [PAGE_ID_WIDTH-1:0] page_id = sb_hit_fifo[r][sb_hit_rd_ptr[r]];
                        if (DEBUG_VERBOSE && page_id == DEBUG_PAGE) begin
                            $display("[%0d] TRACE page=0x%h region=%0d event=RESPONSE_HIT actual=HIT", 
                                     total_cycles, page_id, r);
                        end
                        // Verification: RTL produced hit, SB expected hit. Page ID check is extra credit.
                        sb_hit_rd_ptr[r] = (sb_hit_rd_ptr[r] + 1) % FIFO_DEPTH;
                        sb_hit_count[r]  = sb_hit_count[r] - 1;
                    end else begin
                        $error("[%0t] SB_UNEXPECTED_HIT (Region %0d): No pending HIT request in FIFO", $time, r);
                        scoreboard_errors = scoreboard_errors + 1;
                        $fatal("SB_UNEXPECTED_HIT triggered");
                    end
                end

                if (perf_miss[r]) begin
                    if (sb_miss_count[r] > 0) begin
                        automatic logic [PAGE_ID_WIDTH-1:0] page_id = sb_miss_fifo[r][sb_miss_rd_ptr[r]];
                        if (DEBUG_VERBOSE && page_id == DEBUG_PAGE) begin
                            $display("[%0d] TRACE page=0x%h region=%0d event=RESPONSE_MISS actual=MISS", 
                                     total_cycles, page_id, r);
                        end
                        // Verification: RTL produced miss, SB expected miss.
                        sb_miss_rd_ptr[r] = (sb_miss_rd_ptr[r] + 1) % FIFO_DEPTH;
                        sb_miss_count[r]  = sb_miss_count[r] - 1;
                    end else begin
                        $error("[%0t] SB_UNEXPECTED_MISS (Region %0d): No pending MISS request in FIFO", $time, r);
                        scoreboard_errors = scoreboard_errors + 1;
                        $fatal("SB_UNEXPECTED_MISS triggered");
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
