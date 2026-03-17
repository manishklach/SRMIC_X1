// SRMIC Top-Level Integration - Hardened Silicon Version
// Prototype Implementation for SRMIC Architecture

module srmic_top #(
    parameter PAGE_ID_WIDTH = 16,
    parameter NUM_REGIONS   = 4,
    parameter FLIT_WIDTH    = 64
)(
    input  logic clk,
    input  logic rst_n,

    // Performance Monitoring Interface
    output logic [NUM_REGIONS-1:0]   perf_hit,
    output logic [NUM_REGIONS-1:0]   perf_miss,
    output logic                     perf_promo,
    output logic                     perf_demo,
    output logic [31:0]              perf_bank_conflicts
);

    // --- Internal Signals ---
    logic                     thermal_throttle;
    logic [NUM_REGIONS-1:0]   region_full;
    logic                     promote_valid;
    logic [PAGE_ID_WIDTH-1:0] promote_page_id;
    logic [$clog2(NUM_REGIONS)-1:0] promote_region_id;

    logic                     demote_valid;
    logic [PAGE_ID_WIDTH-1:0] demote_page_id;
    logic [NUM_REGIONS-1:0]   region_demote_ack;

    // HRM Interface
    logic [NUM_REGIONS-1:0]   hrm_promote_valid;
    logic [NUM_REGIONS-1:0]   hrm_promote_ack;
    logic [NUM_REGIONS-1:0]   hrm_demote_req;
    logic [NUM_REGIONS-1:0]   hrm_demote_ack;
    logic [PAGE_ID_WIDTH-1:0] hrm_demote_page_id [0:NUM_REGIONS-1];
    logic [NUM_REGIONS-1:0]   hrm_hit;
    logic [NUM_REGIONS-1:0]   hrm_miss;
    logic [31:0]              hrm_bank_conflicts [0:NUM_REGIONS-1];

    always_comb begin
        perf_bank_conflicts = 0;
        for (int i=0; i<NUM_REGIONS; i++) perf_bank_conflicts += hrm_bank_conflicts[i];
    end

    // --- RIC Instance ---
    ric #(
        .PAGE_ID_WIDTH(PAGE_ID_WIDTH),
        .NUM_REGIONS(NUM_REGIONS),
        .REGION_DEPTH(64)
    ) i_ric (
        .clk(clk),
        .rst_n(rst_n),
        .miss_valid(synth_miss_valid),
        .miss_page_id(synth_miss_page_id),
        .thermal_throttle(thermal_throttle),
        .region_full_raw(region_full),
        .promote_valid(promote_valid),
        .promote_page_id(promote_page_id),
        .promote_region_id(promote_region_id),
        .demote_valid(demote_valid),
        .demote_page_id(demote_page_id),
        .region_demote_ack(region_demote_ack)
    );

    // --- HRM Regions ---
    genvar i;
    generate
        for (i = 0; i < NUM_REGIONS; i++) begin : gen_regions
            assign hrm_promote_valid[i] = promote_valid && (promote_region_id == i);
            assign hrm_demote_req[i]    = demote_valid && (promote_region_id == i);
            assign region_demote_ack[i] = hrm_demote_ack[i];
            
            hrm_region #(
                .PAGE_ID_WIDTH(PAGE_ID_WIDTH),
                .REGION_DEPTH(64)
            ) i_hrm (
                .clk(clk),
                .rst_n(rst_n),
                .promote_valid(hrm_promote_valid[i]),
                .promote_page_id(promote_page_id),
                .promote_ack(hrm_promote_ack[i]),
                .demote_request(hrm_demote_req[i]),
                .demote_ack(hrm_demote_ack[i]),
                .demote_page_id(hrm_demote_page_id[i]),
                .access_valid(synth_access_valid), 
                .access_page_id(synth_access_id),
                .access_stall(),
                .response_valid(),
                .region_full(region_full[i]),
                .hit(hrm_hit[i]),
                .miss(hrm_miss[i]),
                .bank_conflict_count(hrm_bank_conflicts[i])
            );
        end
    endgenerate

    // --- Synthetic Traffic Generation (Hardened Pattern) ---
    logic [PAGE_ID_WIDTH-1:0] synth_miss_page_id;
    logic                     synth_miss_valid;
    logic [PAGE_ID_WIDTH-1:0] synth_access_id;
    logic                     synth_access_valid;
    logic [15:0]              lfsr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr <= 16'hACE1;
            synth_miss_page_id <= 0;
            synth_miss_valid   <= 0;
            synth_access_valid <= 0;
            thermal_throttle   <= 0;
        end else begin
            lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
            
            // Rich Traffic Pattern:
            // 60% misses, 30% re-access, 10% burst
            if (lfsr[3:0] < 4'd10) begin // ~60%
                synth_miss_valid <= lfsr[4];
                synth_access_valid <= 1'b0;
            end else if (lfsr[3:0] < 4'd14) begin // ~25%
                synth_access_valid <= 1'b1;
                synth_access_id <= lfsr[PAGE_ID_WIDTH-1:0] & 16'h000F; // Re-access hot pages
            end else begin // Burst / Conflict
                synth_access_valid <= 1'b1;
                synth_access_id <= 16'h0001; // Force bank conflict
            end
            
            if (synth_miss_valid) synth_miss_page_id <= synth_miss_page_id + 1;
        end
    end

    assign perf_hit   = hrm_hit;
    assign perf_miss  = hrm_miss;
    assign perf_promo = promote_valid;
    assign perf_demo  = demote_valid;

endmodule
