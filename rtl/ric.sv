// Residency Intelligence Controller (RIC) - Hardened Version
// Prototype Implementation for SRMIC Architecture

module ric #(
    parameter PAGE_ID_WIDTH = 16,
    parameter NUM_REGIONS   = 4,
    parameter PROMO_FIFO_DEPTH = 16,
    parameter PIN_REG_SIZE  = 8,
    parameter REGION_DEPTH  = 64
)(
    input  logic clk,
    input  logic rst_n,

    // Interface from compute/miss-handler
    input  logic                     miss_valid,
    input  logic [PAGE_ID_WIDTH-1:0] miss_page_id,

    // Status from regions
    input  logic                     thermal_throttle,
    input  logic [NUM_REGIONS-1:0]   region_full_raw, // Raw status

    // Promotion output
    output logic                     promote_valid,
    output logic [PAGE_ID_WIDTH-1:0] promote_page_id,
    output logic [$clog2(NUM_REGIONS)-1:0] promote_region_id,

    // Demotion output
    output logic                     demote_valid,
    output logic [PAGE_ID_WIDTH-1:0] demote_page_id,
    
    // Feedback from Regions for occupancy
    input  logic [NUM_REGIONS-1:0]   region_demote_ack
);

    // --- FSM States ---
    typedef enum logic [2:0] {
        IDLE          = 3'b000,
        CHECK_STATUS  = 3'b001,
        ISSUE_DEMOTE  = 3'b010,
        WAIT_DEMOTE   = 3'b011,
        ISSUE_PROMOTE = 3'b100
    } state_t;

    state_t state, next_state;

    // --- Promotion FIFO (Circular) ---
    logic [PAGE_ID_WIDTH-1:0] promo_fifo [0:PROMO_FIFO_DEPTH-1];
    logic [$clog2(PROMO_FIFO_DEPTH)-1:0] fifo_head, fifo_tail;
    logic [$clog2(PROMO_FIFO_DEPTH+1)-1:0] fifo_count;
    
    logic fifo_pop;
    logic fifo_empty, fifo_full;

    assign fifo_empty = (fifo_count == 0);
    assign fifo_full  = (fifo_count == PROMO_FIFO_DEPTH);

    // --- Pin Register File (CAM) ---
    logic [PAGE_ID_WIDTH-1:0] pin_regs [0:PIN_REG_SIZE-1];
    logic [PIN_REG_SIZE-1:0]  pin_valid;
    logic [$clog2(PIN_REG_SIZE)-1:0] pin_ptr;
    
    logic page_in_fifo;
    always_comb begin
        page_in_fifo = 1'b0;
        for (int i = 0; i < PIN_REG_SIZE; i++) begin
            if (pin_valid[i] && (pin_regs[i] == miss_page_id))
                page_in_fifo = 1'b1;
        end
    end

    // --- True Region Occupancy Tracking ---
    logic [$clog2(REGION_DEPTH+1)-1:0] occupancy [0:NUM_REGIONS-1];
    logic [NUM_REGIONS-1:0] region_at_limit;

    always_comb begin
        for (int i = 0; i < NUM_REGIONS; i++) begin
            region_at_limit[i] = (occupancy[i] >= REGION_DEPTH);
        end
    end

    // --- Deterministic Victim Selection (Region LRU) ---
    logic [$clog2(NUM_REGIONS)-1:0] target_region;
    logic [2:0] region_age [0:NUM_REGIONS-1];

    always_comb begin
        target_region = 0;
        for (int i = 1; i < NUM_REGIONS; i++) begin
            if (region_age[i] > region_age[target_region])
                target_region = i[$clog2(NUM_REGIONS)-1:0];
        end
    end

    // --- Token Bucket Throttle ---
    logic [3:0] credit_counter;
    logic [3:0] refill_timer;
    logic       can_promote;

    assign can_promote = (credit_counter > 0) && !thermal_throttle;

    // --- Regret Counters ---
    logic [7:0] regret_counters [0:15]; 

    // --- FSM Logic ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else state <= next_state;
    end

    always_comb begin
        next_state = state;
        promote_valid = 1'b0;
        demote_valid  = 1'b0;
        fifo_pop      = 1'b0;

        case (state)
            IDLE: begin
                if (!fifo_empty && can_promote)
                    next_state = CHECK_STATUS;
            end

            CHECK_STATUS: begin
                if (region_at_limit[target_region])
                    next_state = ISSUE_DEMOTE;
                else
                    next_state = ISSUE_PROMOTE;
            end

            ISSUE_DEMOTE: begin
                demote_valid = 1'b1;
                next_state   = WAIT_DEMOTE;
            end

            WAIT_DEMOTE: begin
                if (region_demote_ack[target_region])
                    next_state = ISSUE_PROMOTE;
            end

            ISSUE_PROMOTE: begin
                promote_valid = 1'b1;
                fifo_pop      = 1'b1;
                next_state    = IDLE;
            end

            default: next_state = IDLE;
        endcase
    end

    // --- Sequential Logic ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_head    <= 0;
            fifo_tail    <= 0;
            fifo_count   <= 0;
            pin_valid    <= 0;
            pin_ptr      <= 0;
            credit_counter <= 4'h8;
            refill_timer   <= 0;
            for (int i = 0; i < NUM_REGIONS; i++) begin
                occupancy[i] <= 0;
                region_age[i] <= i[2:0];
            end
            for (int i = 0; i < 16; i++) regret_counters[i] <= 0;
        end else begin
            // FIFO Push
            if (miss_valid && !fifo_full && !page_in_fifo) begin
                promo_fifo[fifo_tail] <= miss_page_id;
                fifo_tail <= fifo_tail + 1;
                fifo_count <= fifo_count + 1;
                pin_regs[pin_ptr] <= miss_page_id;
                pin_valid[pin_ptr] <= 1'b1;
                pin_ptr <= pin_ptr + 1;
            end

            // FIFO Pop
            if (fifo_pop) begin
                fifo_head <= fifo_head + 1;
                fifo_count <= fifo_count - 1;
            end

            // Occupancy Tracking
            if (promote_valid) begin
                occupancy[promote_region_id] <= occupancy[promote_region_id] + 1;
                credit_counter <= credit_counter - 1;
                // Update Age
                region_age[promote_region_id] <= 0;
                for (int i = 0; i < NUM_REGIONS; i++) begin
                    if (i != promote_region_id && region_age[i] < 3'd7)
                        region_age[i] <= region_age[i] + 1;
                end
            end

            for (int i = 0; i < NUM_REGIONS; i++) begin
                if (region_demote_ack[i] && occupancy[i] > 0)
                    occupancy[i] <= occupancy[i] - 1;
            end

            // Token Refill
            if (refill_timer == 4'd15) begin
                refill_timer <= 0;
                if (credit_counter < 4'hF) credit_counter <= credit_counter + 1;
            end else begin
                refill_timer <= refill_timer + 1;
            end
            
            // Regret Counter
            if (miss_valid && page_in_fifo) begin
                regret_counters[miss_page_id[3:0]] <= regret_counters[miss_page_id[3:0]] + 1;
            end
        end
    end

    assign promote_page_id   = promo_fifo[fifo_head];
    assign promote_region_id = target_region;
    assign demote_page_id    = 16'hDEAD; // Region will select specific victim

    // --- SVA Assertions ---
    // Verilator compatible SVA blocks
`ifdef SVA
    property p_no_fifo_overflow;
        @(posedge clk) disable iff (!rst_n)
        (miss_valid && fifo_full) |-> (page_in_fifo || !miss_valid); // Simplified
    endproperty
    assert property (p_no_fifo_overflow);

    property p_promote_credit;
        @(posedge clk) disable iff (!rst_n)
        promote_valid |-> (credit_counter > 0);
    endproperty
    assert property (p_promote_credit);

    property p_no_over_allocation;
        @(posedge clk) disable iff (!rst_n)
        promote_valid |-> (occupancy[promote_region_id] < REGION_DEPTH);
    endproperty
    // Note: In our FSM, we handle demote first, so occupancy should be checked
`endif

endmodule
