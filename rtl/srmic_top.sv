`timescale 1ns/1ps

// ============================================================================
// Module: srmic_top
// Project: SRMIC-X1
// Description: Top-level integration of SRMIC architecture components.
//              Includes synthetic traffic generation for RTL verification.
// ============================================================================

module srmic_top #(
    // ==================================================
    // Parameters
    // ==================================================
    parameter PAGE_ID_WIDTH = 16,
    parameter NUM_REGIONS   = 4,
    parameter FLIT_WIDTH    = 64
)(
    // ==================================================
    // Ports
    // ==================================================
    input  logic                            clk,
    input  logic                            rst_n,

    // Performance Monitoring Interface
    output logic [NUM_REGIONS-1:0]          perf_hit,
    output logic [NUM_REGIONS-1:0]          perf_miss,
    output logic                            perf_promo,
    output logic                            perf_demo,
    output logic [31:0]                     perf_bank_conflicts,
    output logic [31:0]                     perf_router_stalls,

    // Performance Monitoring (synthesis-visible)
    // Debug ports excluded from synthesis via `ifndef SYNTHESIS
    output logic [2:0]                      dbg_ric_state,
    output logic [4:0]                      dbg_fifo_count,
    output logic [3:0]                      dbg_credit_counter,
    output logic [$clog2(NUM_REGIONS)-1:0]  dbg_selected_region,
    output logic [6:0]                      dbg_occupancy [0:NUM_REGIONS-1],
    output logic [31:0]                     dbg_bank_conflicts [0:NUM_REGIONS-1],
    output logic [1:0]                      dbg_router_grant_port,
    output logic                            dbg_router_active_vc,
    output logic [NUM_REGIONS-1:0]          dbg_access_stall,
    output logic [NUM_REGIONS-1:0]          dbg_response_valid,
    output logic [NUM_REGIONS-1:0]          dbg_region_hit,
    output logic [NUM_REGIONS-1:0]          dbg_region_miss,
    output logic [PAGE_ID_WIDTH-1:0]        dbg_last_access_page_id [0:NUM_REGIONS-1],
    output logic [NUM_REGIONS-1:0]          dbg_last_hit,
    output logic [NUM_REGIONS-1:0]          dbg_last_miss,
    output logic [PAGE_ID_WIDTH-1:0]        dbg_last_promoted_page  [0:NUM_REGIONS-1],
    output logic [PAGE_ID_WIDTH-1:0]        dbg_last_demoted_page   [0:NUM_REGIONS-1],
    output logic                            dbg_synth_access_valid,
    output logic [PAGE_ID_WIDTH-1:0]        dbg_synth_access_id,
    output logic [PAGE_ID_WIDTH-1:0]        dbg_promote_committed_page [0:NUM_REGIONS-1],
    output logic [$clog2(NUM_REGIONS)-1:0]  promote_target_region
`endif
);

    // ==================================================
    // Local State / Signals
    // ==================================================
    logic                                   thermal_throttle;
    logic [NUM_REGIONS-1:0]                 region_full;
    logic                                   promote_valid;
    logic [PAGE_ID_WIDTH-1:0]               promote_page_id;
    logic [$clog2(NUM_REGIONS)-1:0]         promote_region_id;
    logic                                   demote_valid;
    logic [PAGE_ID_WIDTH-1:0]               demote_page_id;
    logic [NUM_REGIONS-1:0]                 region_demote_ack;

    // HRM Interface
    logic [NUM_REGIONS-1:0]                 hrm_promote_valid;
    logic [NUM_REGIONS-1:0]                 hrm_promote_ack;
    logic [NUM_REGIONS-1:0]                 hrm_demote_req;
    logic [NUM_REGIONS-1:0]                 hrm_demote_ack;
    logic [NUM_REGIONS-1:0]                 hrm_hit;
    logic [NUM_REGIONS-1:0]                 hrm_miss;
    logic [31:0]                            hrm_bank_conflicts [0:NUM_REGIONS-1];
`ifdef SYNTHESIS
    // Synthesis-mode wires for debug ports that are excluded from port list
    logic [NUM_REGIONS-1:0]                 synth_access_stall;
    logic [NUM_REGIONS-1:0]                 synth_response_valid;
`endif

    // Real demote page IDs from HRM regions
    logic [PAGE_ID_WIDTH-1:0]               hrm_demote_page_id [0:NUM_REGIONS-1];
    logic [3:0]                             dummy_in_credit_ret;
    logic [3:0]                             dummy_out_valid;
    logic [4*FLIT_WIDTH-1:0]                dummy_out_flit;
    logic [3:0]                             dummy_out_vc_id;

    // Synthetic Traffic Generation
    logic [PAGE_ID_WIDTH-1:0]               synth_miss_page_id;
    logic                                   synth_miss_valid;
    logic [PAGE_ID_WIDTH-1:0]               synth_access_id;
    logic                                   synth_access_valid;
    logic [15:0]                            lfsr;

    // Traffic Visibility assignments
`ifndef SYNTHESIS
    assign dbg_synth_access_valid  = synth_access_valid;
    assign dbg_synth_access_id     = synth_access_id;
    assign promote_target_region   = promote_region_id;
`endif

    // ==================================================
    // Combinational Logic
    // ==================================================
    always_comb begin
        perf_bank_conflicts = 0;
        for (int i = 0; i < NUM_REGIONS; i++) begin
            perf_bank_conflicts += hrm_bank_conflicts[i];
`ifndef SYNTHESIS
            dbg_bank_conflicts[i] = hrm_bank_conflicts[i];
`endif
        end
    end

    // ==================================================
    // Sequential Logic (Traffic Gen)
    // ==================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr               <= 16'hACE1;
            synth_miss_page_id <= 0;
            synth_miss_valid   <= 0;
            synth_access_valid <= 0;
            thermal_throttle   <= 0;
        end else begin
            lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
            
            // Rich Traffic Pattern:
            // 60% random misses, 25% hot-page reaccess, 10% burst conflict, 5% throttle
            if (lfsr[3:0] < 4'd10) begin 
                synth_miss_valid   <= lfsr[4];
                synth_access_valid <= 1'b0;
            end else if (lfsr[3:0] < 4'd14) begin 
                synth_access_valid <= 1'b1;
                synth_access_id    <= lfsr[PAGE_ID_WIDTH-1:0] & 16'h000F;
            end else if (lfsr[3:0] == 4'd14) begin 
                synth_access_valid <= 1'b1;
                synth_access_id    <= 16'h0001; 
            end else begin 
                thermal_throttle   <= lfsr[5];
            end
            
            if (synth_miss_valid) synth_miss_page_id <= synth_miss_page_id + 1;
        end
    end

    // ==================================================
    // Module Instantiations
    // ==================================================

    // Residency Intelligence Controller
    ric #(
        .PAGE_ID_WIDTH(PAGE_ID_WIDTH),
        .NUM_REGIONS(NUM_REGIONS)
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
        .demote_page_id(), // Overridden by hrm_demote_page_id mux below
        .region_demote_ack(region_demote_ack),
`ifndef SYNTHESIS
        .dbg_state(dbg_ric_state),
        .dbg_fifo_count(dbg_fifo_count),
        .dbg_credit_counter(dbg_credit_counter),
        .dbg_target_region(dbg_selected_region),
        .dbg_occupancy(dbg_occupancy)
`endif
    );

    // HRM Regions
    generate
        for (genvar i = 0; i < NUM_REGIONS; i++) begin : gen_regions
            hrm_region #(
                .PAGE_ID_WIDTH(PAGE_ID_WIDTH),
                .REGION_DEPTH(64)
            ) i_hrm (
                .clk(clk),
                .rst_n(rst_n),
                .promote_valid(promote_valid && (promote_region_id == i)),
                .promote_page_id(promote_page_id),
                .promote_ack(hrm_promote_ack[i]),
                .demote_request(demote_valid && (promote_region_id == i[1:0])),
                .demote_ack(hrm_demote_ack[i]),
                .demote_page_id(hrm_demote_page_id[i]),
                .access_valid(synth_access_valid), 
                .access_page_id(synth_access_id),
`ifdef SYNTHESIS
                .access_stall(synth_access_stall[i]),
                .response_valid(synth_response_valid[i]),
`else
                .access_stall(dbg_access_stall[i]),
                .response_valid(dbg_response_valid[i]),
`endif
                .hit(hrm_hit[i]),
                .miss(hrm_miss[i]),
                .region_full(region_full[i]),
                .bank_conflict_count(hrm_bank_conflicts[i]),
`ifndef SYNTHESIS
                .dbg_last_access_page_id(dbg_last_access_page_id[i]),
                .dbg_last_hit(dbg_last_hit[i]),
                .dbg_last_miss(dbg_last_miss[i]),
                .dbg_last_promoted_page(dbg_last_promoted_page[i]),
                .dbg_last_demoted_page(dbg_last_demoted_page[i])
`endif
            );
`ifndef SYNTHESIS
            assign dbg_region_hit[i]  = hrm_hit[i];
            assign dbg_region_miss[i] = hrm_miss[i];
`endif
        end
    endgenerate

    assign region_demote_ack = hrm_demote_ack;

    // Override RIC demote_page_id with actual evicted page from target HRM region
    // The RIC outputs 0xDEAD as placeholder; this mux provides the real value.
    always_comb begin
        demote_page_id = 16'hDEAD; // default
        for (int i = 0; i < NUM_REGIONS; i++) begin
            if (demote_valid && (promote_region_id == i))
                demote_page_id = hrm_demote_page_id[i];
        end
    end

`ifndef SYNTHESIS
    // Wire committed page per region from HRM pipeline
    generate
        for (genvar i = 0; i < NUM_REGIONS; i++) begin : gen_committed_page
            assign dbg_promote_committed_page[i] = gen_regions[i].i_hrm.promote_page_id_pipe[3];
        end
    endgenerate
`endif

    // Mesh Router
    srmesh_router i_router (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(4'b0),
        .in_flit({(4*FLIT_WIDTH){1'b0}}),
        .in_vc_id(4'b0),
        .in_credit_ret(dummy_in_credit_ret),
        .out_valid(dummy_out_valid),
        .out_flit(dummy_out_flit),
        .out_vc_id(dummy_out_vc_id),
        .out_credit_ret(4'b0),
`ifndef SYNTHESIS
        .dbg_grant_port(dbg_router_grant_port),
        .dbg_active_vc(dbg_router_active_vc),
`endif
        .dbg_stall_cycles(perf_router_stalls)
    );

    assign perf_hit   = hrm_hit;
    assign perf_miss  = hrm_miss;
    assign perf_promo = promote_valid;
    assign perf_demo  = demote_valid;

endmodule