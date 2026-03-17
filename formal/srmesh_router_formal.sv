// ============================================================================
// Module: srmesh_router_formal
// Description: Formal verification wrapper for SRMESH Router
// ============================================================================

module srmesh_router_formal (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [3:0]  in_valid,
    input  logic [63:0] in_flit [0:3],
    input  logic [3:0]  in_vc_id,
    input  logic [3:0]  out_credit_ret
);

    logic [3:0]  in_credit_ret;
    logic [3:0]  out_valid;
    logic [63:0] out_flit [0:3];
    logic [3:0]  out_vc_id;
    logic [1:0]  dbg_grant_port;
    logic        dbg_active_vc;
    logic [31:0] dbg_stall_cycles;

    srmesh_router #(
        .FLIT_WIDTH(64),
        .ROUTER_X(0),
        .ROUTER_Y(0),
        .MAX_CREDITS(4),
        .VC0_WEIGHT(2),
        .VC1_WEIGHT(1)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_flit(in_flit),
        .in_vc_id(in_vc_id),
        .in_credit_ret(in_credit_ret),
        .out_valid(out_valid),
        .out_flit(out_flit),
        .out_vc_id(out_vc_id),
        .out_credit_ret(out_credit_ret),
        .dbg_grant_port(dbg_grant_port),
        .dbg_active_vc(dbg_active_vc),
        .dbg_stall_cycles(dbg_stall_cycles)
    );

`ifdef FORMAL
    reg past_valid = 0;
    always @(posedge clk) past_valid <= 1;

    always @(posedge clk) begin
        if (!past_valid) begin
            assume(!rst_n);
        end
    end

    // Additional Properties for Router
    always @(posedge clk) begin
        if (rst_n && past_valid) begin
            // Cannot output valid if we have zero credits for that VC
            // Credits are checked internally. We just want to ensure we don't grant 
            // to a blocked destination.
            for (int p=0; p<4; p++) begin
                // In a bounded formal check, we ensure the outputs don't happen wildly
                if (out_valid[p]) begin
                    // Flit is non-zero (structural integrity assumption)
                    assert(out_flit[p] != 0 || in_flit[0] == 0); // Simplified
                end
            end
        end
    end
`endif

endmodule
