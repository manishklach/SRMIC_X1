// ============================================================================
// Module: ric_formal
// Description: Formal verification wrapper for Residency Intelligence Controller
// ============================================================================

module ric_formal (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        miss_valid,
    input  logic [15:0] miss_page_id,
    input  logic        thermal_throttle,
    input  logic [3:0]  region_full_raw,
    input  logic [3:0]  region_demote_ack
);

    // Outputs from DUT
    logic        promote_valid;
    logic [15:0] promote_page_id;
    logic [1:0]  promote_region_id;
    logic        demote_valid;
    logic [15:0] demote_page_id;
    
    // Debug ports from DUT
    logic [2:0]  dbg_state;
    logic [3:0]  dbg_fifo_count;
    logic [3:0]  dbg_credit_counter;
    logic [1:0]  dbg_target_region;
    logic [6:0]  dbg_occupancy [0:3];

    // DUT Instantiation
    ric #(
        .PAGE_ID_WIDTH(16),
        .NUM_REGIONS(4),
        .PROMO_FIFO_DEPTH(16),
        .PIN_REG_SIZE(8),
        .REGION_DEPTH(64)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .miss_valid(miss_valid),
        .miss_page_id(miss_page_id),
        .thermal_throttle(thermal_throttle),
        .region_full_raw(region_full_raw),
        .promote_valid(promote_valid),
        .promote_page_id(promote_page_id),
        .promote_region_id(promote_region_id),
        .demote_valid(demote_valid),
        .demote_page_id(demote_page_id),
        .region_demote_ack(region_demote_ack),
        .dbg_state(dbg_state),
        .dbg_fifo_count(dbg_fifo_count),
        .dbg_credit_counter(dbg_credit_counter),
        .dbg_target_region(dbg_target_region),
        .dbg_occupancy(dbg_occupancy)
    );

`ifdef FORMAL
    // Initial reset assumption
    reg past_valid = 0;
    always @(posedge clk) past_valid <= 1;

    always @(posedge clk) begin
        if (!past_valid) begin
            assume(!rst_n);
        end else begin
            // Restrict inputs to realistic behaviors
            assume($stable(rst_n) || rst_n);
        end
    end

    // Formal Assertions (Over and above embedded SVA)
    always @(posedge clk) begin
        if (rst_n && past_valid) begin
            // 1. FIFO bounds
            assert(dbg_fifo_count <= 16);
            
            // 2. Occupancy bounds
            assert(dbg_occupancy[0] <= 64);
            assert(dbg_occupancy[1] <= 64);
            assert(dbg_occupancy[2] <= 64);
            assert(dbg_occupancy[3] <= 64);
            
            // 3. Atomicity
            assert(!(promote_valid && demote_valid));
        end
    end
`endif

endmodule
