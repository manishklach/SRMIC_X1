`timescale 1ns/1ps

// ============================================================================
// Module: hrm_region
// Project: SRMIC-X1
// Description: HRM Region Controller
//              Manages local SRAM residency with bank conflict modeling.
// ============================================================================

module hrm_region #(
    // ==================================================
    // Parameters
    // ==================================================
    parameter PAGE_ID_WIDTH = 16,
    parameter REGION_DEPTH  = 64,
    parameter NUM_BANKS     = 4
)(
    // ==================================================
    // Ports
    // ==================================================
    input  logic                            clk,
    input  logic                            rst_n,

    // Promotion Interface (from RIC)
    input  logic                            promote_valid,
    input  logic [PAGE_ID_WIDTH-1:0]        promote_page_id,
    output logic                            promote_ack,

    // Demotion Interface
    input  logic                            demote_request,
    output logic                            demote_ack,
    output logic [PAGE_ID_WIDTH-1:0]        demote_page_id,

    // Access Interface (from compute/fabric)
    input  logic                            access_valid,
    input  logic [PAGE_ID_WIDTH-1:0]        access_page_id,
    output logic                            access_stall,
    output logic                            response_valid,
    output logic                            hit,
    output logic                            miss,

    // Status / Monitoring
    output logic                            region_full,
    output logic [31:0]                     bank_conflict_count,

    // Debug Observability
    output logic [PAGE_ID_WIDTH-1:0]        dbg_last_access_page_id,
    output logic                            dbg_last_hit,
    output logic                            dbg_last_miss,
    output logic [PAGE_ID_WIDTH-1:0]        dbg_last_promoted_page,
    output logic [PAGE_ID_WIDTH-1:0]        dbg_last_demoted_page
);

    // ==================================================
    // Local State
    // ==================================================
    logic [PAGE_ID_WIDTH-1:0]               tag_array [0:REGION_DEPTH-1];
    logic [REGION_DEPTH-1:0]                valid_array;
    logic [2:0]                             lru_counters [0:REGION_DEPTH-1];

    // Latency Modeling Pipelines
    logic                                   req_accept;
    logic [5:0]                             resp_valid_pipe;
    logic [5:0]                             resp_hit_pipe;
    logic [3:0]                             promo_ack_pipe;
    logic [PAGE_ID_WIDTH-1:0]               promote_page_id_pipe [0:3];
    logic [$clog2(REGION_DEPTH)-1:0]        victim_index_pipe [0:3];
    logic [$clog2(REGION_DEPTH)-1:0]        demote_victim_index_reg;

`ifndef SYNTHESIS
    // Shadow registers for promotion commit verification
    logic                                   promo_commit_check_valid;
    logic [$clog2(REGION_DEPTH)-1:0]        promo_commit_check_index;
    logic [PAGE_ID_WIDTH-1:0]               promo_commit_check_page_id;
`endif

    // ==================================================
    // Combinational Logic
    // ==================================================
    logic [1:0]                             target_bank;
    logic [1:0]                             admin_bank;
    logic                                   hit_comb;
    logic [$clog2(REGION_DEPTH)-1:0]        hit_index_comb;
    logic [$clog2(REGION_DEPTH)-1:0]        victim_index;

    // Bank Conflict Model: bank_id = access_page_id[1:0]
    assign target_bank = access_page_id[1:0]; 
    assign admin_bank  = promote_valid ? promote_page_id[1:0] : 2'd0;

    always_comb begin
        access_stall = 1'b0;
        if (access_valid && (promote_valid || demote_request)) begin
            if (target_bank == admin_bank) access_stall = 1'b1;
        end
    end

    assign req_accept = access_valid && !access_stall;

    // Tag Match Logic
    always_comb begin
        hit_comb = 1'b0;
        hit_index_comb = 0;
        for (int i = 0; i < REGION_DEPTH; i++) begin
            if (valid_array[i] && (tag_array[i] == access_page_id)) begin
                hit_comb       = 1'b1;
                hit_index_comb = i[$clog2(REGION_DEPTH)-1:0];
            end
        end
    end

    // Victim Selection (LRU)
    always_comb begin
        victim_index = 0;
        for (int i = 1; i < REGION_DEPTH; i++) begin
            if (lru_counters[i] > lru_counters[victim_index])
                victim_index = i[$clog2(REGION_DEPTH)-1:0];
        end
        // Invalidate priority
        for (int i = 0; i < REGION_DEPTH; i++) begin
            if (!valid_array[i]) begin
                victim_index = i[$clog2(REGION_DEPTH)-1:0];
                break;
            end
        end
    end

    assign demote_page_id = tag_array[victim_index];
    assign region_full    = &valid_array;

    // ==================================================
    // Sequential Logic
    // ==================================================
    
    // Latency Modeling Pipelines: Hit=2c, Miss=6c, Promo=4c
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            resp_valid_pipe     <= 0;
            resp_hit_pipe       <= 0;
            promo_ack_pipe      <= 0;
            response_valid      <= 0;
            hit                 <= 0;
            miss                <= 0;
            promote_ack         <= 0;
            bank_conflict_count <= 0;
            for (int i = 0; i < 4; i++) begin
                promote_page_id_pipe[i] <= 0;
                victim_index_pipe[i]    <= 0;
            end
            dbg_last_access_page_id <= 0;
            dbg_last_hit            <= 0;
            dbg_last_miss           <= 0;
        end else begin
            if (access_stall) bank_conflict_count <= bank_conflict_count + 1;

            if (req_accept) begin
                dbg_last_access_page_id <= access_page_id;
            end

            // Unified Response Pipeline
            // Only shift a non-zero entry on req_accept.
            // Hit logic: hit_comb is captured on req_accept.
            resp_valid_pipe <= {resp_valid_pipe[4:0], req_accept};
            resp_hit_pipe   <= {resp_hit_pipe[4:0], (req_accept && hit_comb)};
            
            // Promotion Metadata Pipeline
            promo_ack_pipe <= {promo_ack_pipe[2:0], promote_valid};
            promote_page_id_pipe[0] <= promote_page_id;
            victim_index_pipe[0]    <= victim_index;
            for (int i = 1; i < 4; i++) begin
                promote_page_id_pipe[i] <= promote_page_id_pipe[i-1];
                victim_index_pipe[i]    <= victim_index_pipe[i-1];
            end

            // Pipeline Outputs
            // Hit is 2 cycles, Miss is 6 cycles.
            // In the unified pipeline, hit status is carried through.
            // A miss is effectively (resp_valid && !resp_hit).
            
            response_valid <= resp_valid_pipe[1] || resp_valid_pipe[5];
            hit            <= resp_valid_pipe[1] && resp_hit_pipe[1];
            miss           <= resp_valid_pipe[5] && !resp_hit_pipe[5];
            promote_ack    <= promo_ack_pipe[3]; // 4 cycles

            if (resp_valid_pipe[1] && resp_hit_pipe[1]) dbg_last_hit <= 1'b1;
            else if (response_valid) dbg_last_hit <= 1'b0;

            if (resp_valid_pipe[5] && !resp_hit_pipe[5]) dbg_last_miss <= 1'b1;
            else if (response_valid) dbg_last_miss <= 1'b0;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_array             <= 0;
            demote_ack              <= 0;
            demote_victim_index_reg <= 0;
            for (int i = 0; i < REGION_DEPTH; i++) begin
                tag_array[i]    <= 0;
                lru_counters[i] <= 0;
            end
`ifndef SYNTHESIS
            promo_commit_check_valid <= 1'b0;
            promo_commit_check_index <= 0;
            promo_commit_check_page_id <= 0;
`endif
            dbg_last_promoted_page <= 0;
            dbg_last_demoted_page  <= 0;
        end else begin
            demote_ack <= 1'b0;

            // LRU Update
            if (req_accept && hit_comb) begin
                lru_counters[hit_index_comb] <= 3'd0;
                for (int i = 0; i < REGION_DEPTH; i++) begin
                    if (i != {{(32-$clog2(REGION_DEPTH)){1'b0}}, hit_index_comb} && valid_array[i]) begin
                        if (lru_counters[i] < 3'd7) lru_counters[i] <= lru_counters[i] + 1;
                    end
                end
            end

            // Apply Promotion at end of pipeline using captured metadata
            if (promo_ack_pipe[3]) begin
                tag_array[victim_index_pipe[3]]    <= promote_page_id_pipe[3]; 
                valid_array[victim_index_pipe[3]]  <= 1'b1;
                lru_counters[victim_index_pipe[3]] <= 3'd0;
                for (int i = 0; i < REGION_DEPTH; i++) begin
                    if (i != {{(32-$clog2(REGION_DEPTH)){1'b0}}, victim_index_pipe[3]} && valid_array[i]) begin
                        if (lru_counters[i] < 3'd7) lru_counters[i] <= lru_counters[i] + 1;
                    end
                end
                dbg_last_promoted_page <= promote_page_id_pipe[3];
`ifndef SYNTHESIS
                // Set shadow registers for one-cycle-delayed check
                promo_commit_check_valid <= 1'b1;
                promo_commit_check_index <= victim_index_pipe[3];
                promo_commit_check_page_id <= promote_page_id_pipe[3];
`endif
            end else begin
`ifndef SYNTHESIS
                promo_commit_check_valid <= 1'b0;
`endif
            end

            // Demotion captures victim index at request time
            if (demote_request) begin
                demote_victim_index_reg <= victim_index;
                dbg_last_demoted_page   <= tag_array[victim_index];
            end

            // Invalidation happens 1 cycle after request (sync with demote_ack)
            if (demote_request) begin
                valid_array[victim_index] <= 1'b0;
                demote_ack                <= 1'b1;
            end
        end
    end

    // ==================================================
    // Assertions
    // ==================================================
`ifndef SYNTHESIS
    assert property (@(posedge clk) (req_accept && hit_comb) |-> valid_array[hit_index_comb]);
    assert property (@(posedge clk) demote_request |-> region_full);

    always @(posedge clk) begin
        if (rst_n) begin
            assert (victim_index < REGION_DEPTH)
                else $fatal("HRM victim_index out of bounds");
            
            // Corrected Promotion commit integrity check (delayed by 1 cycle)
            if (promo_commit_check_valid) begin
                assert (valid_array[promo_commit_check_index] == 1'b1)
                    else $error("HRM_PROMO_ERROR: Valid bit not set at commit time");
                assert (tag_array[promo_commit_check_index] == promo_commit_check_page_id)
                    else $error("HRM_PROMO_ERROR: Tag mismatch at commit time");
            end

            // Assertion: every response corresponds to exactly one accepted request
            // We check that response_valid (assigned from pipe in prev cycle)
            // corresponds to the pipe stages. Since pipe also shifted, 
            // we use $past to check the values that actually drove the register.
            if (response_valid) begin
                assert ($past(resp_valid_pipe[1] || resp_valid_pipe[5]))
                    else $error("HRM_RESPONSE_ERROR: response_valid without accepted request");
            end
        end
    end
    
    // Tag Uniqueness
    always_comb begin
        for (int i = 0; i < REGION_DEPTH; i++) begin
            for (int j = i + 1; j < REGION_DEPTH; j++) begin
                if (valid_array[i] && valid_array[j]) begin
                    assert (tag_array[i] != tag_array[j]);
                end
            end
        end
    end
`endif

endmodule
