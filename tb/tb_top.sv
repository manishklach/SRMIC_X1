// SRMIC Prototype Testbench - Verification Ready
`timescale 1ns/1ps

module tb_top;

    localparam CLK_PERIOD = 1.0; // 1GHz
    localparam NUM_REGIONS = 4;

    logic clk, rst_n;
    logic [NUM_REGIONS-1:0] perf_hit, perf_miss;
    logic perf_promo, perf_demo;

    // Perf Counters
    longint total_hits, total_misses, total_promos, total_demos;
    real avg_latency;

    srmic_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .perf_hit(perf_hit),
        .perf_miss(perf_miss),
        .perf_promo(perf_promo),
        .perf_demo(perf_demo)
    );

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    initial begin
        $dumpfile("srmic_hardened.vcd");
        $dumpvars(0, tb_top);

        total_hits = 0; total_misses = 0;
        total_promos = 0; total_demos = 0;

        rst_n = 0;
        #(CLK_PERIOD * 20);
        rst_n = 1;

        $display("[%0t] Simulation Started. Target: 20,000 cycles.", $time);

        repeat (20000) begin
            @(posedge clk);
            for (int i = 0; i < NUM_REGIONS; i++) begin
                if (perf_hit[i])  total_hits++;
                if (perf_miss[i]) total_misses++;
            end
            if (perf_promo) total_promos++;
            if (perf_demo)  total_demos++;
        end

        // Final Report
        avg_latency = (total_hits * 2.0 + total_misses * 6.0) / (total_hits + total_misses);

        $display("\n============================================================");
        $display("SRMIC ARCHITECTURE PROTOTYPE - PERFORMANCE SUMMARY");
        $display("============================================================");
        $display("Total Cycles       : 20,000");
        $display("Total HRM Hits     : %0d", total_hits);
        $display("Total HRM Misses   : %0d", total_misses);
        $display("Total Promotions   : %0d", total_promos);
        $display("Total Demotions    : %0d", total_demos);
        $display("------------------------------------------------------------");
        $display("HRM Hit Rate       : %2.2f%%", (real'(total_hits) / (total_hits + total_misses)) * 100);
        $display("Avg Access Latency : %2.2f cycles", avg_latency);
        $display("============================================================\n");

        $finish;
    end

endmodule
