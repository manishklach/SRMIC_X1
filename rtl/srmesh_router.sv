// SRMESH 4-Port Router - Hardened Version
// Prototype Implementation with 2 Virtual Channels (VC0, VC1)
// Weighted Round Robin (WRR) and Starvation Prevention

module srmesh_router #(
    parameter FLIT_WIDTH  = 64,
    parameter ROUTER_X    = 0,
    parameter ROUTER_Y    = 0,
    parameter MAX_CREDITS = 4,
    parameter VC0_WEIGHT  = 2,
    parameter VC1_WEIGHT  = 1
)(
    input  logic clk,
    input  logic rst_n,

    // Interface per port (North:0, South:1, East:2, West:3)
    input  logic [3:0]             in_valid,
    input  logic [FLIT_WIDTH-1:0]  in_flit [0:3],
    input  logic [3:0]             in_vc_id,
    output logic [3:0]             in_credit_ret,

    output logic [3:0]             out_valid,
    output logic [FLIT_WIDTH-1:0]  out_flit [0:3],
    output logic [3:0]             out_vc_id,
    input  logic [3:0]             out_credit_ret
);

    // --- VC Storage ---
    logic [FLIT_WIDTH-1:0] vc_buf [0:3][0:1];
    logic [3:0][1:0]       vc_full;
    logic [3:0][1:0]       vc_vc_id; // Store VC ID in buffer

    // --- Starvation Prevention Counters ---
    logic [4:0] starvation_cnt [0:3][0:1]; // 5-bit for 16+ cycles

    // --- Credit Counters ---
    logic [$clog2(MAX_CREDITS+1)-1:0] credits [0:3][0:1];

    // --- Phase 3: Latency Modeling (1-cycle per hop) ---
    logic [3:0]             out_valid_pre;
    logic [FLIT_WIDTH-1:0]  out_flit_pre [0:3];
    logic [3:0]             out_vc_id_pre;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 0;
            out_vc_id <= 0;
        end else begin
            out_valid <= out_valid_pre;
            out_flit  <= out_flit_pre;
            out_vc_id <= out_vc_id_pre;
        end
    end

    // --- Routing Function ---
    function logic [1:0] get_route(input [FLIT_WIDTH-1:0] flit);
        logic [1:0] dx = flit[59:58];
        logic [1:0] dy = flit[57:56];
        if (dx > ROUTER_X)      return 2'd2; // East
        else if (dx < ROUTER_X) return 2'd3; // West
        else if (dy > ROUTER_Y) return 2'd1; // South
        else                    return 2'd0; // North
        else                    return 2'd0; // Local
    endfunction

    // --- Phase 5: WRR Arbitration ---
    logic [1:0] wrr_state [0:3];
    logic [$clog2(4)-1:0] port_rr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int p=0; p<4; p++) begin
                for (int v=0; v<2; v++) begin
                    credits[p][v] <= MAX_CREDITS;
                    vc_full[p][v] <= 0;
                    starvation_cnt[p][v] <= 0;
                end
                wrr_state[p] <= 0;
            end
            port_rr <= 0;
            in_credit_ret <= 0;
        end else begin
            out_valid_pre <= 0;
            in_credit_ret <= 0;

            // Input buffering
            for (int p=0; p<4; p++) begin
                if (in_valid[p] && !vc_full[p][in_vc_id[p]]) begin
                    vc_buf[p][in_vc_id[p]] <= in_flit[p];
                    vc_full[p][in_vc_id[p]] <= 1'b1;
                    starvation_cnt[p][in_vc_id[p]] <= 0;
                end
                // Increment starvation counters for waiting flits
                for (int v=0; v<2; v++) begin
                    if (vc_full[p][v]) starvation_cnt[p][v] <= starvation_cnt[p][v] + 1;
                end
                // Credit return processing (assume VC0 for simplified return)
                if (out_credit_ret[p]) credits[p][0] <= (credits[p][0] < MAX_CREDITS) ? credits[p][0] + 1 : credits[p][0];
            end

            // Arbitration
            port_rr <= port_rr + 1;
            for (int i=0; i<4; i++) begin
                logic [1:0] p = port_rr + i[1:0];
                
                // Starvation check: Force grant if waiting > 16 cycles
                logic force_v0 = (vc_full[p][0] && starvation_cnt[p][0] > 16);
                logic force_v1 = (vc_full[p][1] && starvation_cnt[p][1] > 16);
                
                logic v;
                if (force_v0) v = 1'b0;
                else if (force_v1) v = 1'b1;
                else v = (wrr_state[p] < VC0_WEIGHT) ? 1'b0 : 1'b1;

                if (vc_full[p][v]) begin
                    logic [1:0] dest = get_route(vc_buf[p][v]);
                    if (credits[dest][v] > 0) begin
                        out_flit_pre[dest] <= vc_buf[p][v];
                        out_valid_pre[dest] <= 1'b1;
                        out_vc_id_pre[dest] <= v;
                        credits[dest][v] <= credits[dest][v] - 1;
                        
                        vc_full[p][v] <= 1'b0;
                        in_credit_ret[p] <= 1'b1;
                        
                        // Update WRR state
                        if (v == 0) wrr_state[p] <= wrr_state[p] + 1;
                        else wrr_state[p] <= 0;
                        break; 
                    end
                end
            end
        end
    end

    // --- Phase 1 & 5: SVA Assertions ---
`ifndef SYNTHESIS
    // 1. Credit never underflows
    generate
        for (genvar p=0; p<4; p++) begin : gen_credits_check
            assert property (@(posedge clk) credits[p][0] <= MAX_CREDITS);
            assert property (@(posedge clk) credits[p][1] <= MAX_CREDITS);
        end
    endgenerate

    // 2. No flit accepted when credit == 0
    // (This is implicitly checked by the arbiter logic, but we can assert)
    assert property (@(posedge clk) (out_valid_pre[0] && out_vc_id_pre[0] == 0) |-> (credits[0][0] > 0));

    // 3. Fairness / Starvation prevention
    assert property (@(posedge clk) (vc_full[0][0]) |-> (##[1:32] !vc_full[0][0])); 
`endif

endmodule
