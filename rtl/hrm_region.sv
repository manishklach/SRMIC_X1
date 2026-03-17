// HRM Region Controller - Upgraded Version
// Prototype Implementation for SRMIC Architecture

module hrm_region #(
    parameter PAGE_ID_WIDTH = 16,
    parameter REGION_DEPTH = 64,
    parameter NUM_BANKS = 4
)(
    input  logic clk,
    input  logic rst_n,

    // Promotion Interface (from RIC)
    input  logic                     promote_valid,
    input  logic [PAGE_ID_WIDTH-1:0] promote_page_id,
    output logic                     promote_ack,

    // Demotion Interface
    input  logic                     demote_request,
    output logic                     demote_ack,
    output logic [PAGE_ID_WIDTH-1:0] demote_page_id,

    // Access Interface (from compute/fabric)
    input  logic                     access_valid,
    input  logic [PAGE_ID_WIDTH-1:0] access_page_id,
    output logic                     access_stall,
    
    // Status / Outputs
    output logic                     region_full,
    output logic                     hit,
    output logic                     miss
);

    localparam ENTRIES_PER_BANK = REGION_DEPTH / NUM_BANKS;

    // --- Storage ---
    logic [PAGE_ID_WIDTH-1:0] tag_array [0:REGION_DEPTH-1];
    logic [REGION_DEPTH-1:0]  valid_array;
    logic [2:0]               lru_counters [0:REGION_DEPTH-1];

    // --- Bank Conflict Model ---
    // Simple: bits [1:0] of page_id determine bank
    logic [NUM_BANKS-1:0] bank_busy;
    logic [1:0] access_bank;
    assign access_bank = access_page_id[1:0];

    // Bank conflict if promotion or demotion is accessing the same bank
    // In this prototype, we'll just track if any "admin" task is active.
    logic admin_active;
    assign admin_active = promote_valid || demote_request;
    assign access_stall = access_valid && admin_active;

    // --- Parallel Tag Compare (Combinational with Registered Output) ---
    logic hit_comb;
    logic [$clog2(REGION_DEPTH)-1:0] hit_index_comb;
    
    always_comb begin
        hit_comb = 1'b0;
        hit_index_comb = 0;
        for (int i = 0; i < REGION_DEPTH; i++) begin
            if (valid_array[i] && (tag_array[i] == access_page_id)) begin
                hit_comb = 1'b1;
                hit_index_comb = i[$clog2(REGION_DEPTH)-1:0];
            end
        end
    end

    // --- True LRU Replacement ---
    logic [$clog2(REGION_DEPTH)-1:0] victim_index;
    always_comb begin
        victim_index = 0;
        for (int i = 1; i < REGION_DEPTH; i++) begin
            if (lru_counters[i] > lru_counters[victim_index])
                victim_index = i[$clog2(REGION_DEPTH)-1:0];
        end
        // Invalid entry priority
        for (int i = 0; i < REGION_DEPTH; i++) begin
            if (!valid_array[i]) begin
                victim_index = i[$clog2(REGION_DEPTH)-1:0];
                break;
            end
        end
    end

    assign demote_page_id = tag_array[victim_index];

    // --- Sequential Updates ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_array <= 0;
            hit         <= 0;
            miss        <= 0;
            promote_ack <= 0;
            demote_ack  <= 0;
            for (int i = 0; i < REGION_DEPTH; i++) begin
                tag_array[i]    <= 0;
                lru_counters[i] <= 0;
            end
        end else begin
            // Default responses
            hit <= 1'b0;
            miss <= 1'b0;
            promote_ack <= 1'b0;
            demote_ack <= 1'b0;

            // Handle Access (if no stall)
            if (access_valid && !access_stall) begin
                hit  <= hit_comb;
                miss <= !hit_comb;
                
                if (hit_comb) begin
                    lru_counters[hit_index_comb] <= 3'd0;
                    for (int i = 0; i < REGION_DEPTH; i++) begin
                        if (i != hit_index_comb && valid_array[i]) begin
                            if (lru_counters[i] < 3'd7)
                                lru_counters[i] <= lru_counters[i] + 1;
                        end
                    end
                end
            end

            // Handle Promotion
            if (promote_valid) begin
                tag_array[victim_index]    <= promote_page_id;
                valid_array[victim_index]  <= 1'b1;
                lru_counters[victim_index] <= 3'd0;
                promote_ack <= 1'b1;
                
                for (int i = 0; i < REGION_DEPTH; i++) begin
                    if (i != victim_index && valid_array[i]) begin
                        if (lru_counters[i] < 3'd7)
                            lru_counters[i] <= lru_counters[i] + 1;
                    end
                end
            end

            // Handle Demotion
            if (demote_request) begin
                valid_array[victim_index] <= 1'b0;
                demote_ack <= 1'b1;
            end
        end
    end

    assign region_full = &valid_array;

    // --- SVA Assertions ---
`ifdef SVA
    property p_demote_when_full;
        @(posedge clk) disable iff (!rst_n)
        demote_request |-> region_full;
    endproperty
    assert property (p_demote_when_full);

    property p_no_simultaneous_ops;
        @(posedge clk) disable iff (!rst_n)
        !(promote_valid && demote_request);
    endproperty
    assert property (p_no_simultaneous_ops);
`endif

endmodule
