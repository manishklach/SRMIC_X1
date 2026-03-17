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

    // ==================================================
    // Ports / Signals
    // ==================================================
    logic clk, rst_n;
    logic [NUM_REGIONS-1:0] perf_hit, perf_miss;
    logic perf_promo, perf_demo;
    logic [31:0] perf_bank_conflicts;
    logic [31:0] perf_router_stalls;

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

    // --- Scoreboard State ---
    typedef enum logic [1:0] { 
        NOT_RESIDENT      = 2'b00, 
        PROMOTION_PENDING = 2'b01, 
        RESIDENT          = 2'b10, 
        DEMOTION_PENDING  = 2'b11 
    } res_state_t;

    res_state_t sb_state [0:SCOREBOARD_SIZE-1];
    logic [PAGE_ID_WIDTH-1:0] sb_resident_pages [0:SCOREBOARD_SIZE-1];
    int sb_timer [0:SCOREBOARD_SIZE-1];
    
    // Latency matching pipe for access IDs and expected hit status
    // Align with: Access Issue (T0) -> RTL Hit (T3) -> TB Capture (T4)
    logic [PAGE_ID_WIDTH-1:0] access_id_pipe [0:3];
    logic                     expected_hit_pipe [0:3];

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
        .perf_router_stalls(perf_router_stalls)
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
            for (int i=0; i<SCOREBOARD_SIZE; i++) begin
                sb_state[i]          <= NOT_RESIDENT;
                sb_resident_pages[i] <= 0;
                sb_timer[i]          <= 0;
            end
            for (int i=0; i<4; i++) begin
                access_id_pipe[i]    <= 0;
                expected_hit_pipe[i] <= 0;
            end
        end else begin
            // 1. Prediction at time of access issue (T0)
            automatic logic current_hit = 1'b0;
            for (int i=0; i<SCOREBOARD_SIZE; i++) begin
                // A page is considered resident if it is already RESIDENT, 
                // or if its promotion is completing in the current cycle.
                if ((sb_state[i] == RESIDENT || (sb_state[i] == PROMOTION_PENDING && sb_timer[i] == 1)) && 
                    (sb_resident_pages[i] == dut.synth_access_id)) begin
                    current_hit = 1'b1;
                end
            end

            access_id_pipe[0]    <= dut.synth_access_id;
            expected_hit_pipe[0] <= current_hit && dut.synth_access_valid;

            // 2. Delay Pipeline (4 stages to match T4 capture)
            for (int i=1; i<4; i++) begin
                access_id_pipe[i]    <= access_id_pipe[i-1];
                expected_hit_pipe[i] <= expected_hit_pipe[i-1];
            end

            // 3. Residency State Machine Updates
            for (int i=0; i<SCOREBOARD_SIZE; i++) begin
                if (sb_timer[i] > 1) begin
                    sb_timer[i] <= sb_timer[i] - 1;
                end else if (sb_timer[i] == 1) begin
                    sb_timer[i] <= 0;
                    if (sb_state[i] == PROMOTION_PENDING) sb_state[i] <= RESIDENT;
                    if (sb_state[i] == DEMOTION_PENDING)  sb_state[i] <= NOT_RESIDENT;
                end
            end

            // 4. Handle Promotions (4 cycle latency)
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
                sb_timer[found]          <= 4;
            end

            // 5. Handle Demotions (1 cycle latency)
            if (perf_demo) begin
                for (int i=0; i<SCOREBOARD_SIZE; i++) begin
                    if (sb_state[i] != NOT_RESIDENT && sb_resident_pages[i] == dut.demote_page_id) begin
                        sb_state[i] <= DEMOTION_PENDING;
                        sb_timer[i] <= 1;
                        break;
                    end
                end
            end
            
            // 6. Validate Hits against prediction from 4 cycles ago
            if (|perf_hit) begin
                if (!expected_hit_pipe[3]) begin
                    $error("[%0t] SB_MISMATCH: Unexpected hit for Page 0x%h", $time, access_id_pipe[3]);
                    scoreboard_errors++;
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
