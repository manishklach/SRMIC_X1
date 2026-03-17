// ============================================================================
// Module: srmic_fpga_top
// Description: FPGA wrapper for SRMIC Top, providing a basic AXI-lite 
//              or simple request/response shim for physical target synthesis.
// ============================================================================

module srmic_fpga_top (
    input  wire        sys_clk,
    input  wire        sys_rst_n,

    // Simple external interface (emulating host memory controller)
    input  wire        ext_req_valid,
    input  wire [15:0] ext_req_page_id,
    output wire        ext_req_stall,
    
    // Status LED outputs
    output wire        led_hit,
    output wire        led_miss,
    output wire        led_throttle
);

    // Synchronize reset
    reg rst_n_sync1, rst_n_sync2;
    always @(posedge sys_clk) begin
        rst_n_sync1 <= sys_rst_n;
        rst_n_sync2 <= rst_n_sync1;
    end

    // DUT Signals
    wire [3:0] perf_hit;
    wire [3:0] perf_miss;
    wire       perf_promo;
    wire       perf_demo;
    wire [31:0] perf_bank_conflicts;
    wire [31:0] perf_router_stalls;

    // Tie off debug signals to prevent optimization of critical logic during sanity synth
    wire [2:0] dbg_ric_state;
    
    // DUT Instantiation
    srmic_top #(
        .PAGE_ID_WIDTH(16),
        .NUM_REGIONS(4),
        .FLIT_WIDTH(64)
    ) dut (
        .clk(sys_clk),
        .rst_n(rst_n_sync2),
        // In a real FPGA wrapper, these would be driven by the external interface.
        // We rely on the internal synthetic generator for the standalone bitstream check.
        .perf_hit(perf_hit),
        .perf_miss(perf_miss),
        .perf_promo(perf_promo),
        .perf_demo(perf_demo),
        .perf_bank_conflicts(perf_bank_conflicts),
        .perf_router_stalls(perf_router_stalls),
        
        .dbg_ric_state(dbg_ric_state),
        .dbg_fifo_count(),
        .dbg_credit_counter(),
        .dbg_selected_region(),
        // .dbg_occupancy(), // Not tied for simplicity
        // .dbg_bank_conflicts(),
        .dbg_router_grant_port(),
        .dbg_router_active_vc()
    );

    assign ext_req_stall = 1'b0;

    // Drive LEDs to prevent logic from being entirely optimized away
    assign led_hit      = |perf_hit;
    assign led_miss     = |perf_miss;
    assign led_throttle = dbg_ric_state == 3'b010; // ISSUE_DEMOTE state

endmodule
