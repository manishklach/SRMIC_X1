// ============================================================================
// SRMIC Hardened Prototype Testbench - Silicon Bring-up Version
// ============================================================================
`timescale 1ns/1ps

module tb_top;

    // ==================================================
    // Parameters
    // ==================================================
    localparam CLK_PERIOD = 1.0; // 1GHz
    localparam NUM_REGIONS = 4;
    localparam PAGE_ID_WIDTH = 16;
    localparam SCOREBOARD_SIZE = 256;

    // ==================================================
    // Ports / Signals
    // ==================================================
    logic clk, rst_n;
    logic [NUM_REGIONS-1:0] perf_hit, perf_miss;
    logic perf_promo, perf_demo;
    logic [31:0] perf_bank_conflicts;
    logic [31:0] perf_router_stalls;

    // ==================================================
    // State (Performance Counters & Scoreboard)
    // ==================================================
    longint total_cycles;
    longint total_requests;
    longint total_hits;
    longint total_misses;
    longint total_promos;
    longint total_demos;
    longint total_latency;
    real avg_latency;
    real hit_rate;
    real miss_rate;

    int scoreboard_errors;
    int seed;
    int fd;

    logic [PAGE_ID_WIDTH-1:0] sb_resident_pages [0:SCOREBOARD_SIZE-1];
    logic [SCOREBOARD_SIZE-1:0] sb_valid;

    // ==================================================
    // DUT Instantiation
    // ==================================================
    srmic_top dut (
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
    // Clock Generation
    // ==================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // ==================================================
    // Sequential Logic (Scoreboard)
    // ==================================================
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            // Reset scoreboard logic
        end else begin
            if (perf_promo) begin
                // Simplified: store in first invalid slot or wrap around
                int found = -1;
                for (int i=0; i<SCOREBOARD_SIZE; i++) begin
                    if (!sb_valid[i]) begin
                        found = i;
                        break;
                    end
                end
                if (found == -1) found = total_promos % SCOREBOARD_SIZE;
                
                sb_resident_pages[found] <= dut.promote_page_id;
                sb_valid[found] <= 1'b1;
            end
            
            // Check hits against scoreboard
            if (|perf_hit) begin
                logic page_found = 1'b0;
                for (int i=0; i<SCOREBOARD_SIZE; i++) begin
                    if (sb_valid[i] && (sb_resident_pages[i] == dut.synth_access_id)) begin
                        page_found = 1'b1;
                    end
                end
                if (!page_found) begin
                    $error("[%0t] SB_MISMATCH: Unexpected hit for Page 0x%h", $time, dut.synth_access_id);
                    scoreboard_errors++;
                end
            end
        end
    end

    // ==================================================
    // Main Simulation Control
    // ==================================================
    initial begin
        if (!$value$plusargs("seed=%d", seed)) begin
            seed = 1234; // Default seed
        end
        $display("Using seed: %0d", seed);
        // Note: Verilator doesn't natively use $srandom in the same way, but keeping it for Icarus/others
        // $srandom(seed);

        // Waveform Dump
        $dumpfile("build/srmic_trace.vcd");
        $dumpvars(0, tb_top);

        // Reset
        total_cycles = 0;
        total_requests = 0;
        total_hits = 0;
        total_misses = 0;
        total_promos = 0;
        total_demos = 0;
        total_latency = 0;
        scoreboard_errors = 0;
        sb_valid = 0;

        rst_n = 0;
        #(CLK_PERIOD * 20);
        rst_n = 1;

        $display("[%0t] Starting SRMIC Hardened Silicon Sim (20,000 cycles)...", $time);

        repeat (20000) begin
            @(posedge clk);
            total_cycles++;
            
            for (int i=0; i<NUM_REGIONS; i++) begin
                if (perf_hit[i]) begin
                    total_hits++; total_requests++; total_latency += 2;
                end
                if (perf_miss[i]) begin
                    total_misses++; total_requests++; total_latency += 6;
                end
            end
            if (perf_promo) total_promos++;
            if (perf_demo)  total_demos++;
        end

        // Computation
        if (total_requests > 0) begin
            avg_latency = real'(total_latency) / total_requests;
            hit_rate = (real'(total_hits) / total_requests) * 100.0;
            miss_rate = (real'(total_misses) / total_requests) * 100.0;
        end else begin
            avg_latency = 0.0;
            hit_rate = 0.0;
            miss_rate = 0.0;
        end

        // Final Report
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

        if (scoreboard_errors == 0) begin
            $display("SRMIC RTL TEST: PASS");
        end else begin
            $display("SRMIC RTL TEST: FAIL (%0d errors)", scoreboard_errors);
        end
        $display("============================================================\n");

        // Write metrics to sim_results.log
        fd = $fopen("build/sim_results.log", "w");
        if (fd) begin
            $fdisplay(fd, "total_cycles=%0d", total_cycles);
            $fdisplay(fd, "total_requests=%0d", total_requests);
            $fdisplay(fd, "total_hits=%0d", total_hits);
            $fdisplay(fd, "total_misses=%0d", total_misses);
            $fdisplay(fd, "total_promotions=%0d", total_promos);
            $fdisplay(fd, "total_demotions=%0d", total_demos);
            $fdisplay(fd, "total_bank_conflicts=%0d", perf_bank_conflicts);
            $fdisplay(fd, "total_router_stalls=%0d", perf_router_stalls);
            $fdisplay(fd, "average_latency=%2.2f", avg_latency);
            $fdisplay(fd, "hit_rate=%2.2f", hit_rate);
            $fdisplay(fd, "miss_rate=%2.2f", miss_rate);
            $fdisplay(fd, "scoreboard_errors=%0d", scoreboard_errors);
            if (scoreboard_errors == 0) begin
                $fdisplay(fd, "status=PASS");
            end else begin
                $fdisplay(fd, "status=FAIL");
            end
            $fclose(fd);
        end

        if (scoreboard_errors > 0) begin
            $fatal(1, "Testbench failed with %0d scoreboard errors.", scoreboard_errors);
        end else begin
            $finish;
        end
    end

endmodule
