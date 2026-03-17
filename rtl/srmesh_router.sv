// SRMESH 4-Port Router - Upgraded Version
// Prototype Implementation with 2 Virtual Channels (VC0, VC1)
// Uses Weighted Round Robin (WRR) Arbitration

module srmesh_router #(
    parameter FLIT_WIDTH  = 64,
    parameter ROUTER_X    = 0,
    parameter ROUTER_Y    = 0,
    parameter MAX_CREDITS = 4,
    parameter WRR_WEIGHT0 = 2, // VC0 Weight
    parameter WRR_WEIGHT1 = 1  // VC1 Weight
)(
    input  logic clk,
    input  logic rst_n,

    // Interface per port (North, South, East, West)
    // Using a simplified bundle approach for 4 directions
    input  logic [3:0]             in_valid,
    input  logic [FLIT_WIDTH-1:0]  in_flit [0:3],
    input  logic [3:0]             in_vc_id, // 0 or 1
    output logic [3:0]             in_credit_ret,

    output logic [3:0]             out_valid,
    output logic [FLIT_WIDTH-1:0]  out_flit [0:3],
    output logic [3:0]             out_vc_id,
    input  logic [3:0]             out_credit_ret
);

    // Direction indices: 0:N, 1:S, 2:E, 3:W
    
    // --- VC Storage (2 VCs per port) ---
    logic [FLIT_WIDTH-1:0] vc_buf [0:3][0:1]; // [port][vc]
    logic [3:0][1:0]       vc_full;

    // --- Credit Counters per VC ---
    logic [$clog2(MAX_CREDITS+1)-1:0] credits [0:3][0:1]; // [port][vc]

    // --- Routing Function ---
    function logic [1:0] get_route(input [FLIT_WIDTH-1:0] flit);
        logic [1:0] dx = flit[59:58];
        logic [1:0] dy = flit[57:56];
        if (dx > ROUTER_X)      return 2'd2; // East
        else if (dx < ROUTER_X) return 2'd3; // West
        else if (dy > ROUTER_Y) return 2'd1; // South
        else if (dy < ROUTER_Y) return 2'd0; // North
        else                    return 2'd0; // Local
    endfunction

    // --- WRR Arbitration Logic ---
    logic [1:0] wrr_cnt [0:3]; // per port
    logic [$clog2(4)-1:0] port_sel;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int p = 0; p < 4; p++) begin
                for (int v = 0; v < 2; v++) begin
                    credits[p][v] <= MAX_CREDITS;
                    vc_full[p][v] <= 0;
                end
                wrr_cnt[p] <= 0;
            end
            port_sel      <= 0;
            out_valid     <= 0;
            in_credit_ret <= 0;
        end else begin
            // Reset outputs
            out_valid     <= 0;
            in_credit_ret <= 0;
            
            // 1. Input Buffering & Credit Return
            for (int p = 0; p < 4; p++) begin
                if (in_valid[p] && !vc_full[p][in_vc_id[p]]) begin
                    vc_buf[p][in_vc_id[p]] <= in_flit[p];
                    vc_full[p][in_vc_id[p]] <= 1'b1;
                end
                
                // Process credit returns from neighbors
                if (out_credit_ret[p]) begin
                    // Simplified: need VC ID on credit return or assume broadcast
                    credits[p][0] <= (credits[p][0] < MAX_CREDITS) ? credits[p][0] + 1 : credits[p][0];
                end
            end

            // 2. WRR Arbitration & Forwarding (1 flit per cycle)
            port_sel <= port_sel + 1;
            for (int i = 0; i < 4; i++) begin
                logic [$clog2(4)-1:0] p = port_sel + i[$clog2(4)-1:0];
                logic v = (wrr_cnt[p] < WRR_WEIGHT0) ? 1'b0 : 1'b1;
                
                if (vc_full[p][v]) begin
                    logic [1:0] dest = get_route(vc_buf[p][v]);
                    if (credits[dest][v] > 0) begin
                        out_flit[dest] <= vc_buf[p][v];
                        out_valid[dest] <= 1'b1;
                        out_vc_id[dest] <= v;
                        credits[dest][v] <= credits[dest][v] - 1;
                        
                        vc_full[p][v] <= 1'b0;
                        in_credit_ret[p] <= 1'b1; // Trigger credit return to neighbor
                        
                        // Update WRR counter
                        if (v == 0) wrr_cnt[p] <= wrr_cnt[p] + 1;
                        else wrr_cnt[p] <= 0;
                        break; // Arbitrate only 1 flit per cycle for prototype
                    end
                end
            end
        end
    end

    // --- SVA Assertions ---
`ifdef SVA
    property p_no_credit_underflow;
        @(posedge clk) disable iff (!rst_n)
        forall (p in 0..3, v in 0..1)
            (out_valid[p] && out_vc_id == v) |-> (credits[p][v] > 0);
    endproperty
    // Note: forall is not standard SVA, would be unrolled in real RTL

    property p_flit_integrity;
        @(posedge clk) disable iff (!rst_n)
        (out_valid[0]) |-> (out_flit[0] != 0);
    endproperty
    assert property (p_flit_integrity);
`endif

endmodule
