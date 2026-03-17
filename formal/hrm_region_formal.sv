// ============================================================================
// Module: hrm_region_formal
// Description: Formal verification wrapper for HRM Region Controller
// ============================================================================

module hrm_region_formal (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        promote_valid,
    input  logic [15:0] promote_page_id,
    input  logic        demote_request,
    input  logic        access_valid,
    input  logic [15:0] access_page_id
);

    logic        promote_ack;
    logic        demote_ack;
    logic [15:0] demote_page_id;
    logic        access_stall;
    logic        response_valid;
    logic        hit;
    logic        miss;
    logic        region_full;
    logic [31:0] bank_conflict_count;

    hrm_region #(
        .PAGE_ID_WIDTH(16),
        .REGION_DEPTH(64),
        .NUM_BANKS(4)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .promote_valid(promote_valid),
        .promote_page_id(promote_page_id),
        .promote_ack(promote_ack),
        .demote_request(demote_request),
        .demote_ack(demote_ack),
        .demote_page_id(demote_page_id),
        .access_valid(access_valid),
        .access_page_id(access_page_id),
        .access_stall(access_stall),
        .response_valid(response_valid),
        .hit(hit),
        .miss(miss),
        .region_full(region_full),
        .bank_conflict_count(bank_conflict_count)
    );

`ifdef FORMAL
    reg past_valid = 0;
    always @(posedge clk) past_valid <= 1;

    always @(posedge clk) begin
        if (!past_valid) begin
            assume(!rst_n);
        end
    end

    // Additional Properties
    always @(posedge clk) begin
        if (rst_n && past_valid) begin
            // Demote request must only be processed when full (if our logic strictly handles it)
            if (demote_request) begin
                // The region only actually invalidates if requested, but architecture 
                // invariant says RIC only requests when full. We assume the RIC obeys this.
                assume(region_full);
            end

            // We cannot hit and miss simultaneously
            if (response_valid) begin
                assert(hit ^ miss);
            end
        end
    end
`endif

endmodule
