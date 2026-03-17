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
    localparam FIFO_DEPTH      = 16;

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

    // --- Scoreboard Residency State ---
    typedef enum logic [1:0] { 
        NOT_RESIDENT      = 2'b00, 
        PROMOTION_PENDING = 2'b01, 
        RESIDENT          = 2'b10, 
        DEMOTION_PENDING  = 2'b11 
    } res_state_t;

    res_state_t sb_state [0:SCOREBOARD_SIZE-1];
    logic [PAGE_ID_WIDTH-1:0] sb_resident_pages [0:SCOREBOARD_SIZE-1];
    int sb_timer [0:SCOREBOARD_SIZE-1];
    
    // --- Scoreboard Response FIFO ---
    typedef struct packed {
        logic [PAGE_ID_WIDTH-1:0] page_id;
        logic                     expected_hit;
    } sb_req_t;

    sb_req_t sb_fifo [0:FIFO_DEPTH-1];
    int sb_fifo_wr_ptr, sb_fifo_rd_ptr, sb_fifo_count;

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
            sb_fifo_wr_ptr    <= 0;
            sb_fifo_rd_ptr    <= 0;
            sb_fifo_count     <= 0;
            for (int i=0; i<SCOREBOARD_SIZE; i++) begin
                sb_state[i]          <= NOT_RESIDENT;
                sb_resident_pages[i] <= 0;
                sb_timer[i]          <= 0;
            end
        end else begin
            // 1. Prediction at time of access issue (T0)
            if (dut.synth_access_valid && !(|dut.gen_regions[0].i_hrm.access_stall)) begin
                automatic logic current_hit = 1'b0;
                for (int i=0; i<SCOREBOARD_SIZE; i++) begin
                    // A page is considered resident if it is already RESIDENT, 
                    // or if its promotion is completing in the current cycle.
                    if ((sb_state[i] == RESIDENT || (sb_state[i] == PROMOTION_PENDING && sb_timer[i] == 1)) && 
                        (sb_resident_pages[i] == dut.synth_access_id)) begin
                        current_hit = 1'b1;
                    end
                end

                if (sb_fifo_count < FIFO_DEPTH) begin
                    sb_fifo[sb_fifo_wr_ptr].page_id      <= dut.synth_access_id;
                    sb_fifo[sb_fifo_wr_ptr].expected_hit <= current_hit;
                    sb_fifo_wr_ptr <= (sb_fifo_wr_ptr + 1) % FIFO_DEPTH;
                    sb_fifo_count  <= sb_fifo_count + 1;
                end else begin
                    $error("[%0t] SB_FIFO_OVERFLOW: Increase FIFO_DEPTH", $time);
                    scoreboard_errors++;
                end
            end

            // 2. Residency State Machine Updates
            for (int i=0; i<SCOREBOARD_SIZE; i++) begin
                if (sb_timer[i] > 1) begin
                    sb_timer[i] <= sb_timer[i] - 1;
                end else if (sb_timer[i] == 1) begin
                    sb_timer[i] <= 0;
                    if (sb_state[i] == PROMOTION_PENDING) sb_state[i] <= RESIDENT;
                    if (sb_state[i] == DEMOTION_PENDING)  sb_state[i] <= NOT_RESIDENT;
                end
            end

            // 3. Handle Promotions (4 cycle latency)
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

            // 4. Handle Demotions (1 cycle latency)
            if (perf_demo) begin
                for (int i=0; i<SCOREBOARD_SIZE; i++) begin
                    if (sb_state[i] != NOT_RESIDENT && sb_resident_pages[i] == dut.demote_page_id) begin
                        sb_state[i] <= DEMOTION_PENDING;
                        sb_timer[i] <= 1;
                        break;
                    end
                end
            end
            
            // 5. Validate at Response Time
            // Wait for response_valid from any region (they are synced in this simple model)
            if (|dut.gen_regions[0].i_hrm.response_valid) begin
                if (sb_fifo_count > 0) begin
                    automatic sb_req_t req = sb_fifo[sb_fifo_rd_ptr];
                    automatic logic actual_hit = |perf_hit;
                    
                    if (actual_hit != req.expected_hit) begin
                        $error("[%0t] SB_MISMATCH: Page 0x%h, Expected %s, Got %s", 
                               $time, req.page_id, 
                               req.expected_hit ? "HIT" : "MISS",
                               actual_hit ? "HIT" : "MISS");
                        scoreboard_errors++;
                    end
                    
                    sb_fifo_rd_ptr <= (sb_fifo_rd_ptr + 1) % FIFO_DEPTH;
                    sb_fifo_count  <= sb_fifo_count - 1;
                end else begin
                    $error("[%0t] SB_UNEXPECTED_RESPONSE: No pending request in FIFO", $time);
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
