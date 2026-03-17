// SRMIC Top-Level Integration - Latency Modeled
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
    output logic                     perf_demo
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

    // Latency Modeling Pipelines
    // Promotion Latency = 4 cycles
    logic [3:0] promo_delay_pipe;
    logic [PAGE_ID_WIDTH-1:0] promo_id_pipe [0:3];
    logic [1:0] promo_reg_pipe [0:3];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            promo_delay_pipe <= 0;
        end else begin
            promo_delay_pipe <= {promo_delay_pipe[2:0], promote_valid};
            promo_id_pipe[0] <= promote_page_id;
            promo_reg_pipe[0] <= promote_region_id;
            for (int i = 1; i < 4; i++) begin
                promo_id_pipe[i] <= promo_id_pipe[i-1];
                promo_reg_pipe[i] <= promo_reg_pipe[i-1];
            end
        end
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
            assign hrm_promote_valid[i] = promo_delay_pipe[3] && (promo_reg_pipe[3] == i);
            assign hrm_demote_req[i]    = demote_valid && (promote_region_id == i); // Simplified mapping
            assign region_demote_ack[i] = hrm_demote_ack[i];
            
            hrm_region #(
                .PAGE_ID_WIDTH(PAGE_ID_WIDTH),
                .REGION_DEPTH(64)
            ) i_hrm (
                .clk(clk),
                .rst_n(rst_n),
                .promote_valid(hrm_promote_valid[i]),
                .promote_page_id(promo_id_pipe[3]),
                .promote_ack(hrm_promote_ack[i]),
                .demote_request(hrm_demote_req[i]),
                .demote_ack(hrm_demote_ack[i]),
                .demote_page_id(hrm_demote_page_id[i]),
                .access_valid(synth_access_valid), 
                .access_page_id(synth_access_id),
                .access_stall(),
                .region_full(region_full[i]),
                .hit(hrm_hit[i]),
                .miss(hrm_miss[i])
            );
        end
    endgenerate

    // Synthetic Traffic (Moved to top for simplified control)
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
            synth_miss_valid   <= (lfsr[3:0] == 4'hA); // Burst miss pattern
            synth_access_valid <= lfsr[5]; // Constant traffic
            thermal_throttle   <= (lfsr[11:8] == 4'hF);
            if (synth_miss_valid) synth_miss_page_id <= synth_miss_page_id + 1;
            synth_access_id <= lfsr[PAGE_ID_WIDTH-1:0];
        end
    end

    // Performance Outputs
    assign perf_hit   = hrm_hit;
    assign perf_miss  = hrm_miss;
    assign perf_promo = promote_valid;
    assign perf_demo  = demote_valid;

endmodule
