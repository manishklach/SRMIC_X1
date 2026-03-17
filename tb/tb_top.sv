// SRMIC Prototype Testbench
`timescale 1ns/1ps

module tb_top;

    // Parameters
    localparam CLK_PERIOD = 1.0; // 1GHz

    // Signals
    logic clk;
    logic rst_n;

    // Device Under Test (DUT)
    srmic_top dut (
        .clk(clk),
        .rst_n(rst_n)
    );

    // Clock Generator
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Simulation Sequence
    initial begin
        // Waveform capture
        $dumpfile("srmic_trace.vcd");
        $dumpvars(0, tb_top);

        // Reset phase
        $display("[%0t] Resetting SRMIC Prototype...", $time);
        rst_n = 0;
        #(CLK_PERIOD * 10);
        rst_n = 1;
        $display("[%0t] Reset released. Starting simulation.", $time);

        // Run for 5000 cycles
        #(CLK_PERIOD * 5000);

        $display("[%0t] Simulation complete. Hits: %0d, Misses: %0d", 
                  $time, dut.hrm_hit, dut.hrm_miss);
        $finish;
    end

    // Monitoring
    always @(posedge clk) begin
        if (dut.promote_valid) begin
            $display("[%0t] PROMOTION: PageID=0x%h -> Region=%0d", 
                      $time, dut.promote_page_id, dut.promote_region_id);
        end
        if (dut.demote_valid) begin
            $display("[%0t] DEMOTION: Region Selection Triggered", $time);
        end
        if (dut.thermal_throttle) begin
            $display("[%0t] THERMAL THROTTLE ACTIVE", $time);
        end
    end

endmodule
