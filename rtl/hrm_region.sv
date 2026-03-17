// HRM Region Controller
// Prototype Implementation for SRMIC Architecture

module hrm_region #(
    parameter PAGE_ID_WIDTH = 16,
    parameter REGION_DEPTH = 64
)(
    input  logic clk,
    input  logic rst_n,

    // Promotion Interface (from RIC)
    input  logic                     promote_valid,
    input  logic [PAGE_ID_WIDTH-1:0] promote_page_id,

    // Demotion Request (optional trigger)
    input  logic                     demote_request,

    // Access Interface (from compute/fabric)
    input  logic                     access_valid,
    input  logic [PAGE_ID_WIDTH-1:0] access_page_id,

    // Status / Outputs
    output logic                     region_full,
    output logic                     hit,
    output logic                     miss,
    output logic [PAGE_ID_WIDTH-1:0] demote_page_id
);

    // --- Storage ---
    logic [PAGE_ID_WIDTH-1:0] tag_array [0:REGION_DEPTH-1];
    logic [REGION_DEPTH-1:0]  valid_array;
    logic [2:0]               lru_counters [0:REGION_DEPTH-1];

    // --- Hit Detection ---
    logic [$clog2(REGION_DEPTH)-1:0] hit_index;
    logic hit_found;

    always_comb begin
        hit_found = 1'b0;
        hit_index = 0;
        for (int i = 0; i < REGION_DEPTH; i++) begin
            if (valid_array[i] && (tag_array[i] == access_page_id)) begin
                hit_found = 1'b1;
                hit_index = i[$clog2(REGION_DEPTH)-1:0];
            end
        end
    end

    assign hit = access_valid && hit_found;
    assign miss = access_valid && !hit_found;

    // --- Region Full Logic ---
    assign region_full = &valid_array;

    // --- Victim Selection (LRU) ---
    logic [$clog2(REGION_DEPTH)-1:0] victim_index;
    always_comb begin
        victim_index = 0;
        for (int i = 1; i < REGION_DEPTH; i++) begin
            if (lru_counters[i] > lru_counters[victim_index])
                victim_index = i[$clog2(REGION_DEPTH)-1:0];
        end
        // Overwrite: If any entry is invalid, it's the best victim
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
            for (int i = 0; i < REGION_DEPTH; i++) begin
                tag_array[i]    <= 0;
                lru_counters[i] <= 0;
            end
        end else begin
            // Promotion Handling
            if (promote_valid) begin
                tag_array[victim_index]    <= promote_page_id;
                valid_array[victim_index]  <= 1'b1;
                lru_counters[victim_index] <= 3'd0;
                
                // Age other entries
                for (int i = 0; i < REGION_DEPTH; i++) begin
                    if (i != victim_index && valid_array[i]) begin
                        if (lru_counters[i] < 3'd7)
                            lru_counters[i] <= lru_counters[i] + 1;
                    end
                end
            end

            // Access/Hit Handling (Update LRU)
            if (hit) begin
                lru_counters[hit_index] <= 3'd0;
                for (int i = 0; i < REGION_DEPTH; i++) begin
                    if (i != hit_index && valid_array[i]) begin
                        if (lru_counters[i] < 3'd7)
                            lru_counters[i] <= lru_counters[i] + 1;
                    end
                end
            end
        end
    end

endmodule
