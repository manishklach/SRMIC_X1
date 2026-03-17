// ============================================================================
// Module: tb_top
// Project: SRMIC-X1
// FIX LOG (v2):
//  ROOT CAUSE: SB_UNEXPECTED_HIT caused by promotion-window race.
//  When access arrives while page is PROMOTION_PENDING, scoreboard predicted
//  MISS. But DUT tag array commits promotion at T4 (promo_ack_pipe[3]).
//  If 2-cycle hit response fires at/after T4, DUT returns HIT but scoreboard
//  has only a MISS entry => $fatal.
//
//  FIX 1: Introduce UNKNOWN FIFO for accesses on PROMOTION_PENDING pages.
//         Either HIT or MISS is valid for UNKNOWN entries.
//  FIX 2: Use dut.promote_region_id (not dbg_selected_region) in step 5.
//  FIX 3: Promotion commit (step 3) matches by region + PROMOTION_PENDING
//         state using hrm_promote_ack_internal[r].
// ============================================================================

`timescale 1ns/1ps

module tb_top;

    localparam CLK_PERIOD      = 1.0;
    localparam NUM_REGIONS     = 4;
    localparam PAGE_ID_WIDTH   = 16;
    localparam SCOREBOARD_SIZE = 256;
    localparam RUN_CYCLES      = 20000;
    localparam FIFO_DEPTH      = 64;

    localparam logic [15:0] DEBUG_PAGE    = 16'h000a;
    localparam logic        DEBUG_VERBOSE = 1'b1;

    logic clk, rst_n;
    logic [NUM_REGIONS-1:0] perf_hit, perf_miss;
    logic perf_promo, perf_demo;
    logic [31:0] perf_bank_conflicts;
    logic [31:0] perf_router_stalls;

    logic [2:0]                      dbg_ric_state;
    logic [4:0]                      dbg_fifo_count;
    logic [3:0]                      dbg_credit_counter;
    logic [$clog2(NUM_REGIONS)-1:0]  dbg_selected_region;
    logic [6:0]                      dbg_occupancy [0:NUM_REGIONS-1];
    logic [31:0]                     dbg_bank_conflicts [0:NUM_REGIONS-1];
    logic [1:0]                      dbg_router_grant_port;
    logic                            dbg_router_active_vc;
    logic [NUM_REGIONS-1:0]          dbg_access_stall;
    logic [NUM_REGIONS-1:0]          dbg_response_valid;
    logic [NUM_REGIONS-1:0]          dbg_region_hit;
    logic [NUM_REGIONS-1:0]          dbg_region_miss;
    logic [PAGE_ID_WIDTH-1:0]        dbg_last_access_page_id [0:NUM_REGIONS-1];
    logic [NUM_REGIONS-1:0]          dbg_last_hit;
    logic [NUM_REGIONS-1:0]          dbg_last_miss;
    logic [PAGE_ID_WIDTH-1:0]        dbg_last_promoted_page  [0:NUM_REGIONS-1];
    logic [PAGE_ID_WIDTH-1:0]        dbg_last_demoted_page   [0:NUM_REGIONS-1];
    logic                            dbg_synth_access_valid;
    logic [PAGE_ID_WIDTH-1:0]        dbg_synth_access_id;

    // New: committed page per region (from srmic_top debug port)
    logic [PAGE_ID_WIDTH-1:0]        dbg_promote_committed_page [0:NUM_REGIONS-1];
    logic [$clog2(NUM_REGIONS)-1:0]  promote_target_region_wire;

    logic [NUM_REGIONS-1:0] hrm_promote_ack_internal;
    generate
        for (genvar r=0; r<NUM_REGIONS; r++) begin : gen_promo_ack
            assign hrm_promote_ack_internal[r] = dut.gen_regions[r].i_hrm.promote_ack;
        end
    endgenerate

    longint total_cycles, total_requests, total_hits, total_misses;
    longint total_promos, total_demos, total_latency;
    real    avg_latency, hit_rate, miss_rate;
    int     scoreboard_errors, seed, fd;

    typedef enum logic [1:0] {
        NOT_RESIDENT      = 2'b00,
        PROMOTION_PENDING = 2'b01,
        RESIDENT          = 2'b10,
        DEMOTION_PENDING  = 2'b11
    } res_state_t;

    res_state_t               sb_state         [0:SCOREBOARD_SIZE-1];
    logic [PAGE_ID_WIDTH-1:0] sb_resident_pages[0:SCOREBOARD_SIZE-1];
    logic [$clog2(NUM_REGIONS)-1:0] sb_region  [0:SCOREBOARD_SIZE-1];
    int                       sb_timer         [0:SCOREBOARD_SIZE-1];

    // HIT FIFO — definite hits
    logic [PAGE_ID_WIDTH-1:0] sb_hit_fifo [0:NUM_REGIONS-1][0:FIFO_DEPTH-1];
    int sb_hit_wr_ptr[0:NUM_REGIONS-1], sb_hit_rd_ptr[0:NUM_REGIONS-1], sb_hit_count[0:NUM_REGIONS-1];

    // MISS FIFO — definite misses
    logic [PAGE_ID_WIDTH-1:0] sb_miss_fifo[0:NUM_REGIONS-1][0:FIFO_DEPTH-1];
    int sb_miss_wr_ptr[0:NUM_REGIONS-1], sb_miss_rd_ptr[0:NUM_REGIONS-1], sb_miss_count[0:NUM_REGIONS-1];

    // UNKNOWN FIFO — access on PROMOTION_PENDING page: either HIT or MISS valid
    logic [PAGE_ID_WIDTH-1:0] sb_unk_fifo [0:NUM_REGIONS-1][0:FIFO_DEPTH-1];
    int sb_unk_wr_ptr[0:NUM_REGIONS-1], sb_unk_rd_ptr[0:NUM_REGIONS-1], sb_unk_count[0:NUM_REGIONS-1];

    srmic_top #(.PAGE_ID_WIDTH(PAGE_ID_WIDTH), .NUM_REGIONS(NUM_REGIONS)) dut (
        .clk(clk), .rst_n(rst_n),
        .perf_hit(perf_hit), .perf_miss(perf_miss),
        .perf_promo(perf_promo), .perf_demo(perf_demo),
        .perf_bank_conflicts(perf_bank_conflicts), .perf_router_stalls(perf_router_stalls),
        .dbg_ric_state(dbg_ric_state), .dbg_fifo_count(dbg_fifo_count),
        .dbg_credit_counter(dbg_credit_counter), .dbg_selected_region(dbg_selected_region),
        .dbg_occupancy(dbg_occupancy), .dbg_bank_conflicts(dbg_bank_conflicts),
        .dbg_router_grant_port(dbg_router_grant_port), .dbg_router_active_vc(dbg_router_active_vc),
        .dbg_access_stall(dbg_access_stall), .dbg_response_valid(dbg_response_valid),
        .dbg_region_hit(dbg_region_hit), .dbg_region_miss(dbg_region_miss),
        .dbg_last_access_page_id(dbg_last_access_page_id),
        .dbg_last_hit(dbg_last_hit), .dbg_last_miss(dbg_last_miss),
        .dbg_last_promoted_page(dbg_last_promoted_page),
        .dbg_last_demoted_page(dbg_last_demoted_page),
        .dbg_synth_access_valid(dbg_synth_access_valid),
        .dbg_synth_access_id(dbg_synth_access_id),
        .dbg_promote_committed_page(dbg_promote_committed_page),
        .promote_target_region(promote_target_region_wire)
    );

    task dump_sb_for_page(logic [PAGE_ID_WIDTH-1:0] page_id);
        $display("--- Scoreboard Dump for Page 0x%h ---", page_id);
        for (int i=0; i<SCOREBOARD_SIZE; i++)
            if (sb_resident_pages[i]==page_id && sb_state[i]!=NOT_RESIDENT)
                $display("  Entry %0d: state=%s region=%0d timer=%0d",
                         i, sb_state[i].name(), sb_region[i], sb_timer[i]);
        $display("--------------------------------------");
    endtask

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            scoreboard_errors = 0;
            for (int r=0; r<NUM_REGIONS; r++) begin
                sb_hit_wr_ptr[r]=0; sb_hit_rd_ptr[r]=0; sb_hit_count[r]=0;
                sb_miss_wr_ptr[r]=0; sb_miss_rd_ptr[r]=0; sb_miss_count[r]=0;
                sb_unk_wr_ptr[r]=0; sb_unk_rd_ptr[r]=0; sb_unk_count[r]=0;
            end
            for (int i=0; i<SCOREBOARD_SIZE; i++) begin
                sb_state[i]=NOT_RESIDENT; sb_resident_pages[i]=0;
                sb_region[i]=0; sb_timer[i]=0;
            end
        end else begin

            // ----------------------------------------------------------
            // STEP 1: Classify request as HIT / MISS / UNKNOWN
            // ----------------------------------------------------------
            if (dbg_synth_access_valid) begin
                for (int r=0; r<NUM_REGIONS; r++) begin
                    if (!dbg_access_stall[r]) begin
                        automatic logic is_resident = 1'b0;
                        automatic logic is_pending  = 1'b0;
                        for (int i=0; i<SCOREBOARD_SIZE; i++) begin
                            if (sb_resident_pages[i] == dbg_synth_access_id &&
                                sb_region[i] == r[$clog2(NUM_REGIONS)-1:0]) begin
                                if (sb_state[i] == RESIDENT)          is_resident = 1'b1;
                                if (sb_state[i] == PROMOTION_PENDING) is_pending  = 1'b1;
                            end
                        end

                        if (is_resident) begin
                            if (sb_hit_count[r] < FIFO_DEPTH) begin
                                sb_hit_fifo[r][sb_hit_wr_ptr[r]] = dbg_synth_access_id;
                                sb_hit_wr_ptr[r] = (sb_hit_wr_ptr[r]+1) % FIFO_DEPTH;
                                sb_hit_count[r]++;
                            end else begin
                                $error("[%0t] SB_HIT_FIFO_OVERFLOW R%0d", $time, r);
                                scoreboard_errors++;
                            end
                        end else if (is_pending) begin
                            // Promotion in flight — accept either outcome
                            if (sb_unk_count[r] < FIFO_DEPTH) begin
                                sb_unk_fifo[r][sb_unk_wr_ptr[r]] = dbg_synth_access_id;
                                sb_unk_wr_ptr[r] = (sb_unk_wr_ptr[r]+1) % FIFO_DEPTH;
                                sb_unk_count[r]++;
                            end else begin
                                $error("[%0t] SB_UNK_FIFO_OVERFLOW R%0d", $time, r);
                                scoreboard_errors++;
                            end
                        end else begin
                            if (sb_miss_count[r] < FIFO_DEPTH) begin
                                sb_miss_fifo[r][sb_miss_wr_ptr[r]] = dbg_synth_access_id;
                                sb_miss_wr_ptr[r] = (sb_miss_wr_ptr[r]+1) % FIFO_DEPTH;
                                sb_miss_count[r]++;
                            end else begin
                                $error("[%0t] SB_MISS_FIFO_OVERFLOW R%0d", $time, r);
                                scoreboard_errors++;
                            end
                        end

                        if (DEBUG_VERBOSE && dbg_synth_access_id == DEBUG_PAGE)
                            $display("[%0d] TRACE page=0x%h region=%0d event=REQUEST_ISSUED expected=%s",
                                     total_cycles, dbg_synth_access_id, r,
                                     is_resident ? "HIT" : (is_pending ? "UNKNOWN" : "MISS"));
                    end
                end
            end

            // ----------------------------------------------------------
            // STEP 2: Duplicate residency detection
            // ----------------------------------------------------------
            for (int i=0; i<SCOREBOARD_SIZE; i++)
                if (sb_state[i]==RESIDENT || sb_state[i]==DEMOTION_PENDING)
                    for (int j=i+1; j<SCOREBOARD_SIZE; j++)
                        if ((sb_state[j]==RESIDENT || sb_state[j]==DEMOTION_PENDING) &&
                            sb_resident_pages[i]==sb_resident_pages[j])
                            $display("[%0d] DUPLICATE_RESIDENCY page=0x%h entries %0d %0d",
                                     total_cycles, sb_resident_pages[i], i, j);

            // ----------------------------------------------------------
            // STEP 3: Promotion commit — match by region AND page_id
            // ----------------------------------------------------------
            // FIX v3: Previous version matched only by region index.
            // If two promotions target the same region back-to-back,
            // first-match-by-region commits the WRONG scoreboard entry.
            // Use promote_page_id_pipe[3] from the HRM region to get
            // the exact page being written to tag_array this cycle.
            for (int r=0; r<NUM_REGIONS; r++) begin
                if (hrm_promote_ack_internal[r]) begin
                    // dbg_last_promoted_page is set when promo_ack_pipe[3]=1,
                    // one cycle before promote_ack output register fires.
                    // This is the correct page — pipe[3] has already shifted
                    // by the time promote_ack=1 is observable.
                    automatic logic [PAGE_ID_WIDTH-1:0] committed_page =
                        dbg_last_promoted_page[r];
                    automatic logic found_it = 1'b0;
                    for (int i=0; i<SCOREBOARD_SIZE; i++) begin
                        if (sb_state[i] == PROMOTION_PENDING &&
                            sb_region[i] == r[$clog2(NUM_REGIONS)-1:0] &&
                            sb_resident_pages[i] == committed_page) begin
                            sb_state[i] = RESIDENT;
                            sb_timer[i] = 0;
                            found_it    = 1'b1;
                            if (DEBUG_VERBOSE && sb_resident_pages[i] == DEBUG_PAGE)
                                $display("[%0d] TRACE page=0x%h event=PROMOTION_COMMITTED region=%0d",
                                         total_cycles, sb_resident_pages[i], r);
                            break;
                        end
                    end
                    if (!found_it) begin
                        $display("[%0d] SB_WARN: promote_ack r=%0d page=0x%h no match",
                                 total_cycles, r, committed_page);
                    end else if (committed_page == DEBUG_PAGE) begin
                        $display("[%0d] COMMIT_TRACE page=0x%h region=%0d -> RESIDENT",
                                 total_cycles, committed_page, r);
                    end
                end
            end

            // ----------------------------------------------------------
            // STEP 4: Timer aging and demotion commit
            // ----------------------------------------------------------
            for (int i=0; i<SCOREBOARD_SIZE; i++) begin
                if (sb_timer[i] > 0) sb_timer[i]--;
                if (sb_state[i]==DEMOTION_PENDING && sb_timer[i]==0) begin
                    if (DEBUG_VERBOSE && sb_resident_pages[i]==DEBUG_PAGE)
                        $display("[%0d] TRACE page=0x%h event=DEMOTION_COMPLETED region=%0d",
                                 total_cycles, sb_resident_pages[i], sb_region[i]);
                    sb_state[i] = NOT_RESIDENT;
                end
            end

            // ----------------------------------------------------------
            // STEP 5: New promotion issued
            //         FIX: use dut.promote_region_id not dbg_selected_region
            // ----------------------------------------------------------
            if (perf_promo) begin
                automatic int found = -1;
                for (int i=0; i<SCOREBOARD_SIZE; i++)
                    if (sb_state[i]==NOT_RESIDENT) begin found=i; break; end
                if (found==-1) found = total_promos % SCOREBOARD_SIZE;
                sb_state[found]          = PROMOTION_PENDING;
                sb_resident_pages[found] = dut.promote_page_id;
                sb_region[found]         = promote_target_region_wire;
                sb_timer[found]          = 4;
                // Always trace 0x000a promotions; also trace all in failure window
                if (dut.promote_page_id == DEBUG_PAGE || (total_cycles > 3600 && total_cycles < 3900))
                    $display("[%0d] PROMO_TRACE page=0x%h region=%0d",
                             total_cycles, dut.promote_page_id, promote_target_region_wire);
                if (DEBUG_VERBOSE && dut.promote_page_id==DEBUG_PAGE)
                    $display("[%0d] TRACE page=0x%h event=PROMOTION_ISSUED region=%0d",
                             total_cycles, dut.promote_page_id, dut.promote_region_id);
            end

            // ----------------------------------------------------------
            // STEP 6: Demotion issued
            // ----------------------------------------------------------
            if (perf_demo) begin
                if (total_cycles > 3600 && total_cycles < 3900)
                    $display("[%0d] DEMO_TRACE page=0x%h region=%0d",
                             total_cycles, dut.demote_page_id, promote_target_region_wire);
                for (int i=0; i<SCOREBOARD_SIZE; i++) begin
                    if (sb_state[i]==RESIDENT &&
                        sb_resident_pages[i]==dut.demote_page_id &&
                        sb_region[i]==promote_target_region_wire) begin
                        sb_state[i] = DEMOTION_PENDING;
                        sb_timer[i] = 1;
                        break;
                    end
                end
            end

            // ----------------------------------------------------------
            // STEP 7: Validate at response time
            //         FIX: drain UNKNOWN FIFO before declaring error
            // ----------------------------------------------------------
            for (int r=0; r<NUM_REGIONS; r++) begin

                if (perf_hit[r]) begin
                    if (sb_hit_count[r] > 0) begin
                        sb_hit_rd_ptr[r] = (sb_hit_rd_ptr[r]+1) % FIFO_DEPTH;
                        sb_hit_count[r]--;
                    end else if (sb_unk_count[r] > 0) begin
                        // Promotion-window hit — architecturally valid
                        sb_unk_rd_ptr[r] = (sb_unk_rd_ptr[r]+1) % FIFO_DEPTH;
                        sb_unk_count[r]--;
                    end else begin
                        $error("[%0t] SB_UNEXPECTED_HIT (Region %0d)", $time, r);
                        scoreboard_errors++;
                        dump_sb_for_page(DEBUG_PAGE);
                        $fatal("SB_UNEXPECTED_HIT triggered");
                    end
                end

                if (perf_miss[r]) begin
                    if (sb_miss_count[r] > 0) begin
                        sb_miss_rd_ptr[r] = (sb_miss_rd_ptr[r]+1) % FIFO_DEPTH;
                        sb_miss_count[r]--;
                    end else if (sb_unk_count[r] > 0) begin
                        // Promotion-window miss — architecturally valid
                        sb_unk_rd_ptr[r] = (sb_unk_rd_ptr[r]+1) % FIFO_DEPTH;
                        sb_unk_count[r]--;
                    end else begin
                        $error("[%0t] SB_UNEXPECTED_MISS (Region %0d)", $time, r);
                        scoreboard_errors++;
                        $fatal("SB_UNEXPECTED_MISS triggered");
                    end
                end

            end
        end
    end

    initial begin clk=0; forever #(CLK_PERIOD/2) clk=~clk; end

    initial begin
        if (!$value$plusargs("seed=%d", seed)) seed=1234;
        $display("[%0t] SIM SEED: %0d", $time, seed);
        $dumpfile("srmic_trace.vcd"); $dumpvars(0, tb_top);
        total_cycles=0; total_requests=0; total_hits=0; total_misses=0;
        total_promos=0; total_demos=0; total_latency=0;
        rst_n=0; #(CLK_PERIOD*20); rst_n=1;
        $display("[%0t] Starting SRMIC bring-up simulation (%0d cycles)...", $time, RUN_CYCLES);
        repeat (RUN_CYCLES) begin
            @(posedge clk); total_cycles++;
            for (int i=0; i<NUM_REGIONS; i++) begin
                if (perf_hit[i])  begin total_hits++;  total_requests++; total_latency+=2; end
                if (perf_miss[i]) begin total_misses++; total_requests++; total_latency+=6; end
            end
            if (perf_promo) total_promos++;
            if (perf_demo)  total_demos++;
        end
        if (total_requests>0) begin
            avg_latency = real'(total_latency)/total_requests;
            hit_rate    = (real'(total_hits)  /total_requests)*100.0;
            miss_rate   = (real'(total_misses)/total_requests)*100.0;
        end
        $display("\n============================================================");
        $display("SRMIC RTL SIM SUMMARY");
        $display("============================================================");
        $display("Total cycles:       %0d", total_cycles);
        $display("Total requests:     %0d", total_requests);
        $display("Hits:               %0d", total_hits);
        $display("Misses:             %0d", total_misses);
        $display("Promotions:         %0d", total_promos);
        $display("Demotions:          %0d", total_demos);
        $display("Bank conflicts:     %0d", perf_bank_conflicts);
        $display("Router stalls:      %0d", perf_router_stalls);
        $display("Average latency:    %2.2f cycles", avg_latency);
        $display("Hit rate:           %2.2f%%", hit_rate);
        $display("Miss rate:          %2.2f%%", miss_rate);
        $display("------------------------------------------------------------");
        if (scoreboard_errors==0) $display("SRMIC RTL TEST: PASS");
        else                      $display("SRMIC RTL TEST: FAIL (%0d errors)", scoreboard_errors);
        $display("============================================================\n");
        fd=$fopen("sim_results.log","w");
        if (fd) begin
            $fdisplay(fd,"cycles=%0d",    total_cycles);
            $fdisplay(fd,"requests=%0d",  total_requests);
            $fdisplay(fd,"hits=%0d",      total_hits);
            $fdisplay(fd,"misses=%0d",    total_misses);
            $fdisplay(fd,"promotions=%0d",total_promos);
            $fdisplay(fd,"demotions=%0d", total_demos);
            $fdisplay(fd,"latency=%2.2f", avg_latency);
            $fdisplay(fd,"hit_rate=%2.2f",hit_rate);
            $fdisplay(fd,"status=%s",     (scoreboard_errors==0)?"PASS":"FAIL");
            $fclose(fd);
        end
        $finish;
    end

`ifndef SYNTHESIS
    assert property (@(posedge clk) total_cycles < 100000);
`endif

endmodule