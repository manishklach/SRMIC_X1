`timescale 1ns/1ps

// ============================================================================
// Module: srmesh_router — SRMIC-X1
// All arrays flat-packed for Yosys/Verilator compatibility.
// slot(port,vc) = port*2 + vc  (8 slots total for 4 ports x 2 VCs)
// ============================================================================

module srmesh_router #(
    parameter FLIT_WIDTH  = 64,
    parameter ROUTER_X    = 0,
    parameter ROUTER_Y    = 0,
    parameter MAX_CREDITS = 4,
    parameter VC0_WEIGHT  = 2,
    parameter VC1_WEIGHT  = 1
)(
    input  logic                       clk,
    input  logic                       rst_n,
    input  logic [3:0]                 in_valid,
    input  logic [4*FLIT_WIDTH-1:0]    in_flit,
    input  logic [3:0]                 in_vc_id,
    output logic [3:0]                 in_credit_ret,
    output logic [3:0]                 out_valid,
    output logic [4*FLIT_WIDTH-1:0]    out_flit,
    output logic [3:0]                 out_vc_id,
    input  logic [3:0]                 out_credit_ret,
    output logic [1:0]                 dbg_grant_port,
    output logic                       dbg_active_vc,
    output logic [31:0]                dbg_stall_cycles
);

    // credit field width
    localparam CW = 3; // $clog2(MAX_CREDITS+1) = $clog2(5) = 3

    // flat packed arrays: 8 slots = 4 ports x 2 VCs
    logic [8*FLIT_WIDTH-1:0]  vc_buf;         // slot s: [s*FLIT_WIDTH +: FLIT_WIDTH]
    logic [7:0]               vc_full;        // slot s: [s]
    logic [8*3-1:0]           credits;        // slot s: [s*3 +: 3]  (CW=3 for MAX_CREDITS=4)
    logic [39:0]              starvation_cnt; // slot s: [s*5 +: 5]
    logic [4*3-1:0]           wrr_state;      // port p: [p*3 +: 3]
    logic [1:0]               port_rr;

    logic [3:0]               pipe_out_valid;
    logic [4*FLIT_WIDTH-1:0]  pipe_out_flit;
    logic [3:0]               pipe_out_vc_id;

    // get_route inlined as task-free expression (Yosys 0.33 compat)
    // Usage: use gr_* signals computed per-call in always_comb

    logic [1:0] sel_port;
    logic       sel_vc;
    logic       found_grant;
    logic [1:0] dest;

    always_comb begin
        // Defaults — eliminates all latch warnings
        found_grant = 1'b0;
        sel_port    = 2'd0;
        sel_vc      = 1'b0;
        dest        = 2'd0;

        begin : arb_block
            logic [1:0]  p;
            logic [3:0]  s0, s1;
            logic        pvc;
            logic [3:0]  sp, snp;
            logic [1:0]  dp, dnp;

            p   = 2'd0;
            s0  = 4'd0;
            s1  = 4'd0;
            pvc = 1'b0;
            sp  = 4'd0;
            snp = 4'd0;
            dp  = 2'd0;
            dnp = 2'd0;

            for (int i = 0; i < 4; i++) begin
                p  = port_rr + i[1:0];
                s0 = {2'b0, p} * 4'd2;
                s1 = {2'b0, p} * 4'd2 + 4'd1;

                // Priority 1: Starvation watchdog
                if (!found_grant && vc_full[s0[2:0]] &&
                    starvation_cnt[s0[2:0]*5 +: 5] > 5'd16) begin
                    sel_port = p; sel_vc = 1'b0; found_grant = 1'b1;
                    dest = ((vc_buf[s0[2:0]*FLIT_WIDTH +: FLIT_WIDTH][59:58] > ROUTER_X) ? 2'd2 : ((vc_buf[s0[2:0]*FLIT_WIDTH +: FLIT_WIDTH][59:58] < ROUTER_X) ? 2'd3 : ((vc_buf[s0[2:0]*FLIT_WIDTH +: FLIT_WIDTH][57:56] > ROUTER_Y) ? 2'd1 : 2'd0)));
                end
                if (!found_grant && vc_full[s1[2:0]] &&
                    starvation_cnt[s1[2:0]*5 +: 5] > 5'd16) begin
                    sel_port = p; sel_vc = 1'b1; found_grant = 1'b1;
                    dest = ((vc_buf[s1[2:0]*FLIT_WIDTH +: FLIT_WIDTH][59:58] > ROUTER_X) ? 2'd2 : ((vc_buf[s1[2:0]*FLIT_WIDTH +: FLIT_WIDTH][59:58] < ROUTER_X) ? 2'd3 : ((vc_buf[s1[2:0]*FLIT_WIDTH +: FLIT_WIDTH][57:56] > ROUTER_Y) ? 2'd1 : 2'd0)));
                end

                // Priority 2: WRR — preferred VC first
                if (!found_grant) begin
                    pvc = (wrr_state[{2'b0,p}*3 +: 3] < 3'd2) ? 1'b0 : 1'b1;
                    sp  = pvc ? s1 : s0;
                    snp = pvc ? s0 : s1;
                    if (vc_full[sp[2:0]]) begin
                        dp = ((vc_buf[sp[2:0]*FLIT_WIDTH +: FLIT_WIDTH][59:58] > ROUTER_X) ? 2'd2 : ((vc_buf[sp[2:0]*FLIT_WIDTH +: FLIT_WIDTH][59:58] < ROUTER_X) ? 2'd3 : ((vc_buf[sp[2:0]*FLIT_WIDTH +: FLIT_WIDTH][57:56] > ROUTER_Y) ? 2'd1 : 2'd0)));
                        if (credits[{2'b0,dp}*2*3/2 +: 3] > 0) begin
                            sel_port = p; sel_vc = pvc; found_grant = 1'b1; dest = dp;
                        end
                    end
                    if (!found_grant && vc_full[snp[2:0]]) begin
                        dnp = ((vc_buf[snp[2:0]*FLIT_WIDTH +: FLIT_WIDTH][59:58] > ROUTER_X) ? 2'd2 : ((vc_buf[snp[2:0]*FLIT_WIDTH +: FLIT_WIDTH][59:58] < ROUTER_X) ? 2'd3 : ((vc_buf[snp[2:0]*FLIT_WIDTH +: FLIT_WIDTH][57:56] > ROUTER_Y) ? 2'd1 : 2'd0)));
                        if (credits[{2'b0,dnp}*2*3/2 +: 3] > 0) begin
                            sel_port = p; sel_vc = ~pvc; found_grant = 1'b1; dest = dnp;
                        end
                    end
                end
            end
        end
    end

    assign dbg_grant_port = sel_port;
    assign dbg_active_vc  = sel_vc;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vc_buf           <= '0;
            vc_full          <= '0;
            starvation_cnt   <= '0;
            port_rr          <= '0;
            in_credit_ret    <= '0;
            out_valid        <= '0;
            pipe_out_valid   <= '0;
            pipe_out_flit    <= '0;
            pipe_out_vc_id   <= '0;
            dbg_stall_cycles <= '0;
            wrr_state        <= '0;
            // Init credits to MAX_CREDITS for all 8 slots
            for (int s = 0; s < 8; s++)
                credits[s*3 +: 3] <= 3'd4;
        end else begin
            out_valid <= pipe_out_valid;
            out_flit  <= pipe_out_flit;
            out_vc_id <= pipe_out_vc_id;
            pipe_out_valid <= '0;
            in_credit_ret  <= '0;

            if (!found_grant && (|vc_full))
                dbg_stall_cycles <= dbg_stall_cycles + 1;

            // Input buffering
            for (int p = 0; p < 4; p++) begin
                logic [2:0] sv;
                sv = {1'b0, p} * 3'd2 + {2'b0, in_vc_id[p]};
                if (in_valid[p] && !vc_full[sv]) begin
                    vc_buf[sv*FLIT_WIDTH +: FLIT_WIDTH] <= in_flit[p*FLIT_WIDTH +: FLIT_WIDTH];
                    vc_full[sv]              <= 1'b1;
                    starvation_cnt[sv*5 +: 5] <= '0;
                end
                if (out_credit_ret[p] && credits[p*2*3/2 +: 3] < 3'd4)
                    credits[p*2*3/2 +: 3] <= credits[p*2*3/2 +: 3] + 1;
                if (vc_full[p*2])   starvation_cnt[p*2*5 +: 5]   <= starvation_cnt[p*2*5 +: 5] + 1;
                if (vc_full[p*2+1]) starvation_cnt[(p*2+1)*5 +: 5] <= starvation_cnt[(p*2+1)*5 +: 5] + 1;
            end

            // Process grant
            if (found_grant) begin
                logic [2:0] ss;
                ss = sel_port * 3'd2 + {2'b0, sel_vc};
                pipe_out_flit[dest*FLIT_WIDTH +: FLIT_WIDTH] <=
                    vc_buf[ss*FLIT_WIDTH +: FLIT_WIDTH];
                pipe_out_valid[dest] <= 1'b1;
                pipe_out_vc_id[dest] <= sel_vc;
                if (credits[{1'b0,dest}*2*3/2 +: 3] > 0)
                    credits[{1'b0,dest}*2*3/2 +: 3] <= credits[{1'b0,dest}*2*3/2 +: 3] - 1;
                vc_full[ss]              <= 1'b0;
                in_credit_ret[sel_port]  <= 1'b1;
                starvation_cnt[ss*5 +: 5] <= '0;
                port_rr <= sel_port + 1;
                if (sel_vc == 1'b0)
                    wrr_state[{1'b0,sel_port}*3 +: 3] <= wrr_state[{1'b0,sel_port}*3 +: 3] + 1;
                else
                    wrr_state[{1'b0,sel_port}*3 +: 3] <= '0;
            end else begin
                port_rr <= port_rr + 1;
            end
        end
    end

`ifndef SYNTHESIS
    generate
        for (genvar p = 0; p < 4; p++) begin : gen_sva
            assert property (@(posedge clk) credits[p*2*3/2 +: 3] <= MAX_CREDITS);
`ifndef VERILATOR
            assert property (@(posedge clk) vc_full[p*2] |-> ##[1:40] !vc_full[p*2]);
`endif
        end
    endgenerate
`endif

endmodule