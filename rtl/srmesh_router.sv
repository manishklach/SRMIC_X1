// SRMESH 4-Port Router
// Prototype Implementation for SRMIC Architecture
// Uses XY Routing and Credit-Based Flow Control

module srmesh_router #(
    parameter FLIT_WIDTH = 64,
    parameter ROUTER_X   = 0,
    parameter ROUTER_Y   = 0,
    parameter MAX_CREDITS = 4
)(
    input  logic clk,
    input  logic rst_n,

    // North Port
    input  logic                   north_in_valid,
    input  logic [FLIT_WIDTH-1:0]  north_in_flit,
    output logic                   north_in_credit_ret, // Credit return to neighbor

    output logic                   north_out_valid,
    output logic [FLIT_WIDTH-1:0]  north_out_flit,
    input  logic                   north_out_credit_ret, // Credit return from neighbor

    // South Port
    input  logic                   south_in_valid,
    input  logic [FLIT_WIDTH-1:0]  south_in_flit,
    output logic                   south_in_credit_ret,

    output logic                   south_out_valid,
    output logic [FLIT_WIDTH-1:0]  south_out_flit,
    input  logic                   south_out_credit_ret,

    // East Port
    input  logic                   east_in_valid,
    input  logic [FLIT_WIDTH-1:0]  east_in_flit,
    output logic                   east_in_credit_ret,

    output logic                   east_out_valid,
    output logic [FLIT_WIDTH-1:0]  east_out_flit,
    input  logic                   east_out_credit_ret,

    // West Port
    input  logic                   west_in_valid,
    input  logic [FLIT_WIDTH-1:0]  west_in_flit,
    output logic                   west_in_credit_ret,

    output logic                   west_out_valid,
    output logic [FLIT_WIDTH-1:0]  west_out_flit,
    input  logic                   west_out_credit_ret
);

    // --- Credit Counters for Outputs ---
    logic [$clog2(MAX_CREDITS+1)-1:0] north_credits, south_credits, east_credits, west_credits;

    // --- Input Buffers (Simple 1-deep) ---
    logic [FLIT_WIDTH-1:0] n_buf, s_buf, e_buf, w_buf;
    logic n_full, s_full, e_full, w_full;

    // --- Routing Logic ---
    // Extract dest coordinates from flit: [59:58]=X, [57:56]=Y
    function logic [1:0] get_route(input [FLIT_WIDTH-1:0] flit);
        logic [1:0] dx = flit[59:58];
        logic [1:0] dy = flit[57:56];
        if (dx > ROUTER_X)      return 2'd2; // East
        else if (dx < ROUTER_X) return 2'd3; // West
        else if (dy > ROUTER_Y) return 2'd1; // South
        else if (dy < ROUTER_Y) return 2'd0; // North
        else                    return 2'd0; // Local (mapped to North for now)
    endfunction

    // --- Crossbar Arbitration (Round Robin) ---
    logic [1:0] rr_ptr;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            north_credits <= MAX_CREDITS;
            south_credits <= MAX_CREDITS;
            east_credits  <= MAX_CREDITS;
            west_credits  <= MAX_CREDITS;
            
            n_full <= 0; s_full <= 0; e_full <= 0; w_full <= 0;
            rr_ptr <= 0;
            
            north_out_valid <= 0;
            south_out_valid <= 0;
            east_out_valid  <= 0;
            west_out_valid  <= 0;
        end else begin
            // Input Buffer Logic
            if (north_in_valid && !n_full) begin n_buf <= north_in_flit; n_full <= 1; end
            if (south_in_valid && !s_full) begin s_buf <= south_in_flit; s_full <= 1; end
            if (east_in_valid  && !e_full) begin e_buf <= east_in_flit;  e_full <= 1; end
            if (west_in_valid  && !w_full) begin w_buf <= west_in_flit;  w_full <= 1; end

            // Credit Return Logic
            north_in_credit_ret <= 0; // Triggered when buffer cleared
            south_in_credit_ret <= 0;
            east_in_credit_ret  <= 0;
            west_in_credit_ret  <= 0;

            // Credit Accounting for Outputs
            if (north_out_credit_ret && north_credits < MAX_CREDITS) north_credits <= north_credits + 1;
            if (south_out_credit_ret && south_credits < MAX_CREDITS) south_credits <= south_credits + 1;
            if (east_out_credit_ret  && east_credits  < MAX_CREDITS) east_credits  <= east_credits + 1;
            if (west_out_credit_ret  && west_credits  < MAX_CREDITS) west_credits  <= west_credits + 1;

            // Full Arbiter & Forward
            north_out_valid <= 0; south_out_valid <= 0; east_out_valid <= 0; west_out_valid <= 0;
            
            rr_ptr <= rr_ptr + 1;
            
            // Simplified round-robin: each input port gets a turn to route its flit
            // North Input
            if (n_full) begin
                logic [1:0] dest = get_route(n_buf);
                if (dest == 2'd2 && east_credits > 0) begin
                    east_out_flit <= n_buf; east_out_valid <= 1; east_credits <= east_credits - 1;
                    n_full <= 0; north_in_credit_ret <= 1;
                end else if (dest == 2'd1 && south_credits > 0) begin
                    south_out_flit <= n_buf; south_out_valid <= 1; south_credits <= south_credits - 1;
                    n_full <= 0; north_in_credit_ret <= 1;
                end else if (dest == 2'd3 && west_credits > 0) begin
                    west_out_flit <= n_buf; west_out_valid <= 1; west_credits <= west_credits - 1;
                    n_full <= 0; north_in_credit_ret <= 1;
                end
            end
            
            // South Input
            if (s_full) begin
                logic [1:0] dest = get_route(s_buf);
                if (dest == 2'd2 && east_credits > 0) begin
                    east_out_flit <= s_buf; east_out_valid <= 1; east_credits <= east_credits - 1;
                    s_full <= 0; south_in_credit_ret <= 1;
                end else if (dest == 2'd0 && north_credits > 0) begin
                    north_out_flit <= s_buf; north_out_valid <= 1; north_credits <= north_credits - 1;
                    s_full <= 0; south_in_credit_ret <= 1;
                end else if (dest == 2'd3 && west_credits > 0) begin
                    west_out_flit <= s_buf; west_out_valid <= 1; west_credits <= west_credits - 1;
                    s_full <= 0; south_in_credit_ret <= 1;
                end
            end

            // East Input
            if (e_full) begin
                logic [1:0] dest = get_route(e_buf);
                if (dest == 2'd3 && west_credits > 0) begin
                    west_out_flit <= e_buf; west_out_valid <= 1; west_credits <= west_credits - 1;
                    e_full <= 0; east_in_credit_ret <= 1;
                end else if (dest == 2'd0 && north_credits > 0) begin
                    north_out_flit <= e_buf; north_out_valid <= 1; north_credits <= north_credits - 1;
                    e_full <= 0; east_in_credit_ret <= 1;
                end else if (dest == 2'd1 && south_credits > 0) begin
                    south_out_flit <= e_buf; south_out_valid <= 1; south_credits <= south_credits - 1;
                    e_full <= 0; east_in_credit_ret <= 1;
                end
            end

            // West Input
            if (w_full) begin
                logic [1:0] dest = get_route(w_buf);
                if (dest == 2'd2 && east_credits > 0) begin
                    east_out_flit <= w_buf; east_out_valid <= 1; east_credits <= east_credits - 1;
                    w_full <= 0; west_in_credit_ret <= 1;
                end else if (dest == 2'd0 && north_credits > 0) begin
                    north_out_flit <= w_buf; north_out_valid <= 1; north_credits <= north_credits - 1;
                    w_full <= 0; west_in_credit_ret <= 1;
                end else if (dest == 2'd1 && south_credits > 0) begin
                    south_out_flit <= w_buf; south_out_valid <= 1; south_credits <= south_credits - 1;
                    w_full <= 0; west_in_credit_ret <= 1;
                end
            end
            
            // Note: Full crossbar logic would be more complex; 
            // this is a simplified prototype for residency flow.
        end
    end

endmodule
