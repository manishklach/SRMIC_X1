`timescale 1ns/1ps

// ============================================================================
// Module: srmesh_router
// Project: SRMIC-X1
// Description: Hardened 4-Port Mesh Router
//              Implements credit-based flow control and WRR arbitration.
// ============================================================================

module srmesh_router #(
    // ==================================================
    // Parameters
    // ==================================================
    parameter FLIT_WIDTH  = 64,
    parameter ROUTER_X    = 0,
    parameter ROUTER_Y    = 0,
    parameter MAX_CREDITS = 4,
    parameter VC0_WEIGHT  = 2,
    parameter VC1_WEIGHT  = 1
)(
    // ==================================================
    // Ports
    // ==================================================
    input  logic                            clk,
    input  logic                            rst_n,

    // Interface per port (North:0, South:1, East:2, West:3)
    input  logic [3:0]                      in_valid,
    input  logic [FLIT_WIDTH-1:0]           in_flit [0:3],
    input  logic [3:0]                      in_vc_id,
    output logic [3:0]                      in_credit_ret,

    output logic [3:0]                      out_valid,
    output logic [FLIT_WIDTH-1:0]           out_flit [0:3],
    output logic [3:0]                      out_vc_id,
    input  logic [3:0]                      out_credit_ret,

    // Debug Observability
    output logic [1:0]                      dbg_grant_port,
    output logic                            dbg_active_vc,
    output logic [31:0]                     dbg_stall_cycles
);

    // ==================================================
    // Local State
    // ==================================================
    logic [FLIT_WIDTH-1:0]                  vc_buf [0:3][0:1];
    logic [3:0][1:0]                        vc_full;
    logic [$clog2(MAX_CREDITS+1)-1:0]       credits [0:3][0:1];
    logic [4:0]                             starvation_cnt [0:3][0:1];
    logic [1:0]                             wrr_state [0:3];
    logic [1:0]                             port_rr;

    // Latency Pipeline
    logic [3:0]                             pipe_out_valid;
    logic [FLIT_WIDTH-1:0]                  pipe_out_flit [0:3];
    logic [3:0]                             pipe_out_vc_id;

    // ==================================================
    // Combinational Logic
    // ==================================================
    function logic [1:0] get_route(input [FLIT_WIDTH-1:0] flit);
        logic [1:0] dx;
        logic [1:0] dy;
        dx = flit[59:58];
        dy = flit[57:56];
        if (dx > ROUTER_X)      return 2'd2; // East
        else if (dx < ROUTER_X) return 2'd3; // West
        else if (dy > ROUTER_Y) return 2'd1; // South
        else                    return 2'd0; // North
    endfunction

    logic [1:0]                             sel_port;
    logic                                   sel_vc;
    logic                                   found_grant;
    logic                                   preferred_vc;
    logic [1:0]                             dest;

    always_comb begin
        found_grant = 1'b0;
        sel_port    = 0;
        sel_vc      = 0;
        preferred_vc = 0;
        dest        = 0;
        
        // Note: break not supported by Yosys.
        // Use found_grant as guard to preserve first-grant priority semantics.
        for (int i = 0; i < 4; i++) begin
            logic [1:0] p;
            p = port_rr + i[1:0];

            if (!found_grant) begin
                // Priority 1: Starvation Watchdog
                if (vc_full[p][0] && (starvation_cnt[p][0] > 16)) begin
                    sel_port = p; sel_vc = 0; found_grant = 1'b1;
                    dest = get_route(vc_buf[p][0]);
                end else if (vc_full[p][1] && (starvation_cnt[p][1] > 16)) begin
                    sel_port = p; sel_vc = 1; found_grant = 1'b1;
                    dest = get_route(vc_buf[p][1]);
                end
            end

            if (!found_grant) begin
                // Priority 2: WRR Arbitration
                preferred_vc = (wrr_state[p] < VC0_WEIGHT) ? 1'b0 : 1'b1;
                if (vc_full[p][preferred_vc]) begin
                    logic [1:0] d;
                    d = get_route(vc_buf[p][preferred_vc]);
                    if (credits[d][preferred_vc] > 0) begin
                        sel_port = p; sel_vc = preferred_vc; found_grant = 1'b1;
                        dest = d;
                    end
                end else if (vc_full[p][!preferred_vc]) begin
                    logic [1:0] d;
                    d = get_route(vc_buf[p][!preferred_vc]);
                    if (credits[d][!preferred_vc] > 0) begin
                        sel_port = p; sel_vc = !preferred_vc; found_grant = 1'b1;
                        dest = d;
                    end
                end
            end
        end
    end

    assign dbg_grant_port = sel_port;
    assign dbg_active_vc  = sel_vc;

    // ==================================================
    // Sequential Logic
    // ==================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int p = 0; p < 4; p++) begin
                for (int v = 0; v < 2; v++) begin
                    credits[p][v]        <= MAX_CREDITS;
                    vc_full[p][v]        <= 0;
                    starvation_cnt[p][v] <= 0;
                end
                wrr_state[p] <= 0;
            end
            port_rr          <= 0;
            in_credit_ret    <= 0;
            out_valid        <= 0;
            dbg_stall_cycles <= 0;
        end else begin
            // Latency Pipeline
            out_valid <= pipe_out_valid;
            out_flit  <= pipe_out_flit;
            out_vc_id <= pipe_out_vc_id;

            pipe_out_valid <= 0;
            in_credit_ret  <= 0;

            if (!found_grant && (|vc_full)) dbg_stall_cycles <= dbg_stall_cycles + 1;

            // Buffer Input & Credit Handshake
            for (int p = 0; p < 4; p++) begin
                if (in_valid[p] && !vc_full[p][in_vc_id[p]]) begin
                    vc_buf[p][in_vc_id[p]]         <= in_flit[p];
                    vc_full[p][in_vc_id[p]]        <= 1'b1;
                    starvation_cnt[p][in_vc_id[p]] <= 0;
                end
                if (out_credit_ret[p]) begin
                    credits[p][0] <= (credits[p][0] < MAX_CREDITS) ? credits[p][0] + 1 : credits[p][0];
                end
                if (vc_full[p][0]) starvation_cnt[p][0] <= starvation_cnt[p][0] + 1;
                if (vc_full[p][1]) starvation_cnt[p][1] <= starvation_cnt[p][1] + 1;
            end

            // Process Grant
            if (found_grant) begin
                pipe_out_flit[dest]              <= vc_buf[sel_port][sel_vc];
                pipe_out_valid[dest]             <= 1'b1;
                pipe_out_vc_id[dest]             <= sel_vc;
                credits[dest][sel_vc]            <= credits[dest][sel_vc] - 1;
                vc_full[sel_port][sel_vc]        <= 1'b0;
                in_credit_ret[sel_port]          <= 1'b1;
                starvation_cnt[sel_port][sel_vc] <= 0;

                port_rr <= sel_port + 1;
                if (sel_vc == 0) wrr_state[sel_port] <= wrr_state[sel_port] + 1;
                else wrr_state[sel_port]             <= 0;
            end else begin
                port_rr <= port_rr + 1;
            end
        end
    end

    // ==================================================
    // Assertions
    // ==================================================
`ifndef SYNTHESIS
    generate
        for (genvar p = 0; p < 4; p++) begin : gen_sva
            assert property (@(posedge clk) credits[p][0] <= MAX_CREDITS);
            assert property (@(posedge clk) credits[p][1] <= MAX_CREDITS);
            assert property (@(posedge clk) (pipe_out_valid[p] && pipe_out_vc_id[p] == 0) |-> (credits[p][0] > 0));
`ifndef VERILATOR
            assert property (@(posedge clk) vc_full[p][0] |-> ##[1:40] !vc_full[p][0]); 
`endif
        end
    endgenerate
`endif

endmodule