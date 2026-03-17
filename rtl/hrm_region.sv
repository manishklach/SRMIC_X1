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
    output logic [31:0]                     bank_conflict_count
);

    // ==================================================
    // Local State
    // ==================================================
    logic [PAGE_ID_WIDTH-1:0]               tag_array [0:REGION_DEPTH-1];
    logic [REGION_DEPTH-1:0]                valid_array;
    logic [2:0]                             lru_counters [0:REGION_DEPTH-1];

    // Latency Modeling Pipelines
    logic [5:0]                             hit_pipe, miss_pipe;
    logic [3:0]                             promo_ack_pipe;

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
            hit_pipe            <= 0;
            miss_pipe           <= 0;
            promo_ack_pipe      <= 0;
            response_valid      <= 0;
            hit                 <= 0;
            miss                <= 0;
            promote_ack         <= 0;
            bank_conflict_count <= 0;
        end else begin
            if (access_stall) bank_conflict_count <= bank_conflict_count + 1;

            // Shift registers for latency
            hit_pipe       <= {hit_pipe[4:0], (access_valid && !access_stall && hit_comb)};
            miss_pipe      <= {miss_pipe[4:0], (access_valid && !access_stall && !hit_comb)};
            promo_ack_pipe <= {promo_ack_pipe[2:0], promote_valid};

            // Pipeline Outputs
            hit            <= hit_pipe[1];   // 2 cycles
            miss           <= miss_pipe[5];  // 6 cycles
            response_valid <= hit_pipe[1] || miss_pipe[5];
            promote_ack    <= promo_ack_pipe[3]; // 4 cycles
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_array <= 0;
            demote_ack  <= 0;
            for (int i = 0; i < REGION_DEPTH; i++) begin
                tag_array[i]    <= 0;
                lru_counters[i] <= 0;
            end
        end else begin
            demote_ack <= 1'b0;

            // LRU Update
            if (access_valid && !access_stall && hit_comb) begin
                lru_counters[hit_index_comb] <= 3'd0;
                for (int i = 0; i < REGION_DEPTH; i++) begin
                    if (i != {{(32-$clog2(REGION_DEPTH)){1'b0}}, hit_index_comb} && valid_array[i]) begin
                        if (lru_counters[i] < 3'd7) lru_counters[i] <= lru_counters[i] + 1;
                    end
                end
            end

            // Apply Promotion at end of pipeline
            if (promo_ack_pipe[3]) begin
                tag_array[victim_index]    <= promote_page_id; 
                valid_array[victim_index]  <= 1'b1;
                lru_counters[victim_index] <= 3'd0;
                for (int i = 0; i < REGION_DEPTH; i++) begin
                    if (i != {{(32-$clog2(REGION_DEPTH)){1'b0}}, victim_index} && valid_array[i]) begin
                        if (lru_counters[i] < 3'd7) lru_counters[i] <= lru_counters[i] + 1;
                    end
                end
            end

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
    assert property (@(posedge clk) (access_valid && hit_comb) |-> valid_array[hit_index_comb]);
    assert property (@(posedge clk) demote_request |-> region_full);
    assert property (@(posedge clk) 1'b1 |-> (victim_index < REGION_DEPTH));
    
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
