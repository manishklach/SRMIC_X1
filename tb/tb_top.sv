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

    logic [PAGE_ID_WIDTH-1:0] sb_resident_pages [0:SCOREBOARD_SIZE-1];
    logic [SCOREBOARD_SIZE-1:0] sb_valid;

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
            sb_valid          <= 0;
            scoreboard_errors <= 0;
        end else begin
            // Track promotions
            if (perf_promo) begin
                int found = -1;
                for (int i=0; i<SCOREBOARD_SIZE; i++) begin
                    if (!sb_valid[i]) begin 
                        found = i; 
                        break; 
                    end
                end
                if (found == -1) found = total_promos % SCOREBOARD_SIZE;
                
                sb_resident_pages[found] <= dut.promote_page_id;
                sb_valid[found]          <= 1'b1;
            end
            
            // Validate hits
            if (|perf_hit) begin
                logic page_found = 1'b0;
                for (int i=0; i<SCOREBOARD_SIZE; i++) begin
                    if (sb_valid[i] && (sb_resident_pages[i] == dut.synth_access_id))
                        page_found = 1'b1;
                end
                if (!page_found) begin
                    $error("[%0t] SB_MISMATCH: Unexpected hit for Page 0x%h", $time, dut.synth_access_id);
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
