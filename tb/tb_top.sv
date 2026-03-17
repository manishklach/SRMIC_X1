// SRMIC Hardened Prototype Testbench
`timescale 1ns/1ps

module tb_top;

    localparam CLK_PERIOD = 1.0; // 1GHz
    localparam NUM_REGIONS = 4;

    logic clk, rst_n;
    logic [NUM_REGIONS-1:0] perf_hit, perf_miss;
    logic perf_promo, perf_demo;
    logic [31:0] perf_bank_conflicts;

    // Performance Counters
    longint total_hits, total_misses, total_promos, total_demos, total_latency;
    longint total_requests;
    real avg_latency;

    srmic_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .perf_hit(perf_hit),
        .perf_miss(perf_miss),
        .perf_promo(perf_promo),
        .perf_demo(perf_demo),
        .perf_bank_conflicts(perf_bank_conflicts)
    );

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    initial begin
        $dumpfile("srmic_hardened_sim.vcd");
        $dumpvars(0, tb_top);

        total_hits = 0; total_misses = 0;
        total_promos = 0; total_demos = 0;
        total_latency = 0; total_requests = 0;

        rst_n = 0;
        #(CLK_PERIOD * 20);
        rst_n = 1;

        $display("[%0t] Starting SRMIC Hardened Simulation (20,000 cycles)...", $time);

        repeat (20000) begin
            @(posedge clk);
            for (int i=0; i<NUM_REGIONS; i++) begin
                if (perf_hit[i]) begin
                    total_hits++;
                    total_latency += 2; // Hit latency
                    total_requests++;
                end
                if (perf_miss[i]) begin
                    total_misses++;
                    total_latency += 6; // Miss latency
                    total_requests++;
                end
            end
            if (perf_promo) total_promos++;
            if (perf_demo)  total_demos++;
        end

        // Computation
        if (total_requests > 0)
            avg_latency = real'(total_latency) / total_requests;
        else
            avg_latency = 0;

        $display("\n============================================================");
        $display("SRMIC RTL SIM SUMMARY");
        $display("============================================================");
        $display("Total cycles:       20,000");
        $display("Hits:               %0d", total_hits);
        $display("Misses:             %0d", total_misses);
        $display("Promotions:         %0d", total_promos);
        $display("Demotions:          %0d", total_demos);
        $display("Bank Conflicts:     %0d", perf_bank_conflicts);
        $display("Average Latency:    %2.2f cycles", avg_latency);
        $display("------------------------------------------------------------\n");

        $finish;
    end

endmodule
