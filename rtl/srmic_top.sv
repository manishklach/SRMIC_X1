// SRMIC Top-Level Integration
// Prototype Implementation for SRMIC Architecture

module srmic_top #(
    parameter PAGE_ID_WIDTH = 16,
    parameter NUM_REGIONS   = 4,
    parameter FLIT_WIDTH    = 64
)(
    input  logic clk,
    input  logic rst_n
);

    // --- Internal Signals ---
    logic                     thermal_throttle;
    logic [NUM_REGIONS-1:0]   region_full;
    logic                     promote_valid;
    logic [PAGE_ID_WIDTH-1:0] promote_page_id;
    logic [$clog2(NUM_REGIONS)-1:0] promote_region_id;

    logic                     demote_valid;
    logic [PAGE_ID_WIDTH-1:0] demote_page_id;

    // HRM Interface
    logic [NUM_REGIONS-1:0]   hrm_promote_valid;
    logic [PAGE_ID_WIDTH-1:0] hrm_demote_page_id [0:NUM_REGIONS-1];
    logic [NUM_REGIONS-1:0]   hrm_hit;
    logic [NUM_REGIONS-1:0]   hrm_miss;

    // Synthetic Traffic
    logic [PAGE_ID_WIDTH-1:0] synth_miss_page_id;
    logic                     synth_miss_valid;
    logic [15:0]              lfsr;

    // --- Synthetic Traffic Generation ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr <= 16'hACE1;
            synth_miss_page_id <= 0;
            synth_miss_valid   <= 0;
            thermal_throttle   <= 0;
        end else begin
            lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
            synth_miss_valid   <= lfsr[0] & lfsr[5]; // Randomish miss
            thermal_throttle   <= lfsr[10] & lfsr[11] & lfsr[12]; // Occasional throttle
            if (synth_miss_valid) synth_miss_page_id <= synth_miss_page_id + 1;
        end
    end

    // --- RIC Instance ---
    ric #(
        .PAGE_ID_WIDTH(PAGE_ID_WIDTH),
        .NUM_REGIONS(NUM_REGIONS)
    ) i_ric (
        .clk(clk),
        .rst_n(rst_n),
        .miss_valid(synth_miss_valid),
        .miss_page_id(synth_miss_page_id),
        .thermal_throttle(thermal_throttle),
        .region_full(region_full),
        .promote_valid(promote_valid),
        .promote_page_id(promote_page_id),
        .promote_region_id(promote_region_id),
        .demote_valid(demote_valid),
        .demote_page_id(demote_page_id)
    );

    // --- HRM Regions ---
    genvar i;
    generate
        for (i = 0; i < NUM_REGIONS; i++) begin : gen_regions
            assign hrm_promote_valid[i] = promote_valid && (promote_region_id == i);
            
            hrm_region #(
                .PAGE_ID_WIDTH(PAGE_ID_WIDTH),
                .REGION_DEPTH(64)
            ) i_hrm (
                .clk(clk),
                .rst_n(rst_n),
                .promote_valid(hrm_promote_valid[i]),
                .promote_page_id(promote_page_id),
                .demote_request(demote_valid),
                .access_valid(1'b0), // Connect to router in full mesh
                .access_page_id(16'h0),
                .region_full(region_full[i]),
                .hit(hrm_hit[i]),
                .miss(hrm_miss[i]),
                .demote_page_id(hrm_demote_page_id[i])
            );
        end
    endgenerate

    // --- SRMESH 2x2 Mesh ---
    // (Simplified instantiation for prototype)
    srmesh_router #(.ROUTER_X(0), .ROUTER_Y(0)) r00 (.*);
    srmesh_router #(.ROUTER_X(1), .ROUTER_Y(0)) r10 (.*);
    srmesh_router #(.ROUTER_X(0), .ROUTER_Y(1)) r01 (.*);
    srmesh_router #(.ROUTER_X(1), .ROUTER_Y(1)) r11 (.*);

    // Mesh connections (E-W, N-S) would go here
    // For this prototype, the focus is on RIC/HRM residency logic.

endmodule
