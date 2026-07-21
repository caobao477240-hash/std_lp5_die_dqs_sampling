`timescale 1ns / 1ps

// =========================================================================
//  LPDDR5 Test Scheduler
// =========================================================================
// Selects one active LPDDR5 test engine and forwards its edge-aligned waveform
// to lpddr5_channel. INIT owns channel reset; IDD and GF only borrow the data,
// command, WCK, DMI, and OE waveform buses while their lock is active.
module lpddr5_test_scheduler (
    // Clock / Reset
    input                       clk                             ,
    input                       rst_n_in                        ,
    // Selected CK run enable and serialized waveform to PHY
    output                      channel_ck_a_run_en             ,
    output                      channel_reset_n_a               ,
    output                      channel_cs_a_0_rise             ,
    output                      channel_cs_a_0_fall             ,
    output       [6:0]          channel_ca_a_rise               ,
    output       [6:0]          channel_ca_a_fall               ,
    output       [1:0]          channel_wck_a_run_en            ,
    output       [1:0]          channel_wck_a_phase             ,
    output       [63:0]         channel_dq_a_tx_word            ,
    output       [7:0]          channel_dmi_a_tx_word           ,
    output       [1:0]          channel_rdqs_t_a_in_dh          ,
    output       [1:0]          channel_rdqs_t_a_in_dl          ,
    output                      channel_dq_oe                   ,
    output                      channel_rdqs_oe                 ,
    output                      channel_rx_dq_capture_en        ,
    input        [63:0]         dq_a_word_flat                  ,
    input                       dq_a_word_valid                 ,
    input        [255:0]        dq_a_burst_flat                 ,
    input                       dq_a_burst_valid                ,

    // Init Control
    input                       init_en                         ,
    output                      init_done                       ,
    output                      init_fail                       ,

    // MRW / runtime RDC
    input        [23:0]         mrw_r                           ,

    // IDD
    input        [9:0]          idd_en                          ,
    output                      idd_done                        ,

    output reg   [15:0]         rdc_err_bitmap                  ,
    output reg                  rdc_check_valid                 ,
    output reg                  rdc_check_pass                  ,

    // RDC Training
    input                       rdc_train_init_en               ,
    input                       rdc_train_apply_best_cfg        ,
    input                       rdc_train_dual_pattern_cfg      ,
    input        [3:0]          rdc_train_dq_start_cfg          ,
    input        [3:0]          rdc_train_dq_end_cfg            ,
    input        [8:0]          rdc_train_tap_start_cfg         ,
    input        [8:0]          rdc_train_tap_stop_cfg          ,
    input        [8:0]          rdc_train_tap_step_cfg          ,
    input                       rdc_train_dq_delay_l_we         ,
    input                       rdc_train_dq_delay_h_we         ,
    input        [95:0]         rdc_train_dq_delay_wdat         ,
    input        [8:0]          rdc_train_scan_tap_sel          ,
    output       [143:0]        rdc_dq_delay_flat               ,
    output       [3:0]          rdc_train_state                 ,
    output                      rdc_train_busy                  ,
    output                      rdc_train_done                  ,
    output                      rdc_train_apply_best            ,
    output       [3:0]          rdc_train_dq_start              ,
    output       [8:0]          rdc_train_tap                   ,
    output       [9:0]          rdc_train_status_best_len       ,
    output       [15:0]         rdc_train_pass_mask             ,
    output       [15:0]         rdc_train_fail_mask             ,
    output       [15:0]         rdc_train_last_err_bitmap       ,
    output                      rdc_train_init_ready            ,
    output                      rdc_train_pass_all              ,
    output       [143:0]        rdc_train_best_flat             ,
    output       [143:0]        rdc_train_left_flat             ,
    output       [143:0]        rdc_train_right_flat            ,
    output       [15:0]         rdc_train_scan_pass_bitmap      ,

    // Calibration / Measurement
    input        [7:0]          read_capture_start_cnt          ,
    input        [7:0]          gf_capture_start_cnt            ,
    input        [3:0]          init_beat_offset                ,
    input        [3:0]          gf_beat_offset                  ,
    output       [3:0]          rx_burst_beat_offset            ,
    input        [9:0]          gf_rd_wck_start_cnt             ,
    input        [9:0]          gf_rd_wck_last_cnt              ,
    input        [9:0]          gf_wr_wck_start_cnt             ,
    input        [9:0]          gf_wr_wck_last_cnt              ,
    input        [9:0]          gf_read_done_cnt                ,
    input        [9:0]          gf_write_done_cnt               ,
    input        [9:0]          gf_act_cmd_gap_cnt              ,
    input        [9:0]          gf_rd_cmd_gap_cnt               ,
    input        [9:0]          gf_wr_cmd_gap_cnt               ,
    input        [9:0]          gf_pre_cmd_gap_cnt              ,
    input        [2:0]          gf_refresh_batch_num            ,
    input        [1:0]          gf_pattern_mode_cfg             ,
    output       [7:0]          die_message                     ,

    // GF (Gross Function) Interface
    input        [5:0]          gf_start_col                    ,// GF start column
    input        [5:0]          gf_end_col                      ,// GF end column
    input        [17:0]         gf_start_row                    ,// GF start row
    input        [17:0]         gf_end_row                      ,// GF end row
    input        [1:0]          gf_start_bg                     ,// GF start bank group
    input        [1:0]          gf_end_bg                       ,// GF end bank group
    input        [1:0]          gf_start_ba                     ,// GF start bank
    input        [1:0]          gf_end_ba                       ,// GF end bank
    output       [31:0]         gf_error_count                  ,
    output       [7:0]          err_block_cnt                   ,
    output       [63:0]         err_block_message               ,
    input                       gf_total_start                  ,
    input                       gf_inner_start                  ,
    output                      gf_inner_done                   ,
    input        [1:0]          gf_op_mode                      ,
    input                       gf_read_data_sel                ,
    input                       gf_write_data_sel               ,
    input                       gf_march_y_mode                 ,// 0=positive sequence, 1=negative sequence
    output       [95:0]         gf_fail_aux_result              ,

    // ILA debug
    output       [111:0]        dbg_ascii_stc                   ,
    output                      dbg_init_busy                   ,
    output                      dbg_gf_inner_en                 ,
    output                      dbg_gf_total_start              ,
    output                      dbg_init_done                   ,
    output                      dbg_gf_inner_done               ,
    output                      dbg_gf_en_read                  ,
    output                      dbg_gf_en_write                 ,
    output       [2:0]          dbg_chn_state                   ,
    output       [10:0]         dbg_init_mr_cnt                 ,
    output       [27:0]         dbg_gf_addr                     ,
    output       [9:0]          dbg_gf_cnt_read                 ,
    output       [9:0]          dbg_gf_cnt_write                ,
    output       [20:0]         dbg_gf_state                    ,
    output       [1:0]          dbg_gf_op_mode                  ,
    output                      dbg_gf_read_data_sel            ,
    output                      dbg_gf_write_data_sel           ,
    output                      dbg_gf_march_y_mode             ,
    output       [15:0]         dbg_gf_read_expected_beat       ,
    output                      dbg_gf_compare_window           ,
    output                      dbg_gf_compare_mismatch_odd     ,
    output                      dbg_gf_compare_mismatch_even    ,
    output                      dbg_gf_err_flag                 ,
    output                      dbg_gf_fail_now
);

// =========================================================================
//  Signal Declarations
// =========================================================================

    wire            idle2mrw;
    wire            idle2iddprecharge;

    // INIT waveform generated in parallel with the legacy core output.
    wire            init_wave_reset_n_a;
    wire            init_wave_cs_a_0_rise;
    wire            init_wave_cs_a_0_fall;
    wire [6:0]      init_wave_ca_a_rise;
    wire [6:0]      init_wave_ca_a_fall;
    wire [1:0]      init_wave_wck_a_run_en;
    wire            init_busy;
    wire [2:0]      init_state;
    wire [10:0]     init_mr_cnt;
    wire            init_runtime_mr_busy;
    wire            init_rdc_sample_en;
    wire            init_rx_dq_capture_en;
    wire [23:0]     init_rdc_train_mrw_r;
    wire [31:0]     init_rdc_train_mrr_r;
    wire            init_rdc_train_pattern_sel;
    wire [111:0]    init_ascii_state;

    // IDD controller outputs.
    wire            idd_ref_done;
    wire            idd_busy;
    wire [2:0]      idd_state;
    wire            idd_ck_stop;
    wire [111:0]    idd_ascii_state;
    wire            idd_ref_wave_ck_a_run_en;
    wire            idd_ref_wave_cs_a_0_rise;
    wire            idd_ref_wave_cs_a_0_fall;
    wire [6:0]      idd_ref_wave_ca_a_rise;
    wire [6:0]      idd_ref_wave_ca_a_fall;
    wire [15:0]     idd_ref_wave_dq_a_in_dh;
    wire [15:0]     idd_ref_wave_dq_a_in_dl;
    reg  [15:0]     idd_ref_wave_dq_a_in_dh_d;
    reg  [15:0]     idd_ref_wave_dq_a_in_dl_d;
    wire            idd_ref_wave_dq_oe;
    wire            idd_ref_wave_rdqs_oe;

    // GF engine outputs.
    wire [20:0]     gf_engine_state;
    wire            gf_engine_pass_start_d;
    wire            gf_engine_en_read;
    wire            gf_engine_en_write;
    wire            gf_engine_rx_dq_capture_en;
    wire            gf_engine_err_flag;
    wire [9:0]      gf_engine_cnt_read;
    wire [9:0]      gf_engine_cnt_write;
    wire            gf_compare_window;
    wire            gf_compare_mismatch_odd;
    wire            gf_compare_mismatch_even;
    wire [15:0]     gf_read_expected_beat;
    wire [1:0]      gf_engine_cnt_ba;
    wire [1:0]      gf_engine_cnt_bg;
    wire [17:0]     gf_engine_cnt_row;
    wire [5:0]      gf_engine_cnt_col;
    wire [17:0]     gf_engine_cnt_row_ns;
    wire [27:0]     gf_addr;
    wire [111:0]    gf_ascii_state;
    wire            gf_wave_ck_a_run_en;
    wire            gf_wave_cs_a_0_rise;
    wire            gf_wave_cs_a_0_fall;
    wire [6:0]      gf_wave_ca_a_rise;
    wire [6:0]      gf_wave_ca_a_fall;
    wire [1:0]      gf_wave_wck_a_run_en;
    wire [1:0]      gf_wave_wck_a_phase;
    wire [63:0]     gf_wave_dq_a_tx_word;
    wire            gf_wave_dq_oe;

    // Selected waveform sent to the unique channel/PHY boundary.
    localparam      CHN_INIT = 3'b001;
    localparam      CHN_IDD  = 3'b010;
    localparam      CHN_GF   = 3'b100;

function [255:0] rdc_expect_burst_from_mr;
    input [7:0] mr33;
    input [7:0] mr34;
    reg  [15:0] pattern_bits;
    integer     beat;
    begin
        // JEDEC RDC read-out order: MR33 OP[0] first, then MR34.
        pattern_bits = {mr34, mr33};
        for (beat = 0; beat < 16; beat = beat + 1) begin
            // Default MR31/MR32 = 0x55 invert the even DQ lanes, so a
            // pattern bit of 1 reads back 0xAAAA on the 16-DQ bus.
            rdc_expect_burst_from_mr[(beat * 16) +: 16] =
                (pattern_bits[beat] == 1'b1) ? 16'haaaa : 16'h5555;
        end
    end
endfunction

    // RDC pattern bytes.  Must match rdc_train_pattern_value() in
    // rdc_train.v and the MR33/MR34 defaults in lpddr5_init.v.
    localparam [7:0]   RDC_PAT0_MR33 = 8'h5a;
    localparam [7:0]   RDC_PAT0_MR34 = 8'ha5;
    localparam [7:0]   RDC_PAT1_MR33 = 8'h3c;
    localparam [7:0]   RDC_PAT1_MR34 = 8'hc3;
    // The expected burst is derived from the pattern bytes, beat-major:
    // dq_a_burst_flat[beat*16 +: 16] is one 16-DQ beat.  RDC read-out is
    // MR33 on beats 0-7 and MR34 on beats 8-15, OP[0] first.  Default
    // MR31/MR32 = 0x55 invert the even DQ lanes, so a pattern bit of 1
    // reads back 0xAAAA (verified by ILA capture 2026-07-16).
    localparam [255:0] RDC_EXPECT_PATTERN0_BURST =
        rdc_expect_burst_from_mr(RDC_PAT0_MR33, RDC_PAT0_MR34);
    localparam [255:0] RDC_EXPECT_PATTERN1_BURST =
        rdc_expect_burst_from_mr(RDC_PAT1_MR33, RDC_PAT1_MR34);

    wire            init_enb_lock;
    wire            init_mr_channel_enb_lock;
    wire            idd_enb_lock;
    wire            idd_channel_enb_lock;
    reg             idd_enb_lock_r;
    wire            mr_enb_lock;
    wire            mr_channel_enb_lock;
    reg             mr_enb_lock_r;
    wire            gf_enb_lock;
    wire            runtime_req_allowed;
    wire            runtime_mrw_req_allowed;
    wire            runtime_rdc_req_allowed;
    wire [23:0]     mrw_cmd_mux;
    wire [255:0]    rdc_expect_burst;
    wire            idd_edge_detect;
    wire            mrw_edge_detect;
    wire            mrw_start_pulse;
    wire            rdc_edge_detect;
    wire            rdc_start_pulse;
    wire            schedule_mrw_req;
    wire            schedule_rdc_req;
    wire            idle2rdc;
    wire            schedule_idd_req;
    wire [2:0]      chn_state;
    reg  [9:0]      idd_en_r;
    reg             idd_en_r_2;
    reg             idd_req_pending;
    reg             idd_req_inflight;

    // ILA / Debug
    reg  [111:00]   ASCII_STC/*synthesis preserve*/;     // ASCII state text for ILA
    wire            gf_fail_now;
    wire            gf_total_start_rise;
    reg             gf_total_start_d;
    reg  [3:0]      fail_row_count;
    reg  [27:0]     fail_addr0;
    reg  [27:0]     fail_addr1;
    reg  [27:0]     fail_addr2;
    wire [21:0]     fail_row_key;
    wire            fail_row_seen;
    wire [63:0]     rdc_err_word0;
    wire [63:0]     rdc_err_word1;
    wire [63:0]     rdc_err_word2;
    wire [63:0]     rdc_err_word3;
    wire [15:0]     rdc_err_bitmap_now;
    wire            rdc_burst_done;

    // wire    clk;
    wire            rst_n;

    reg             rdc_capture_seen;

    // MRW pipeline
    reg  [23:0]     mrw_r_1;
    reg  [23:0]     mrw_r_2;
    reg             mrw_r_2_up_flag;

    // Runtime RDC request pipeline
    reg  [31:0]     mrr_r_1;
    reg  [31:0]     mrr_r_2;
    reg             mrr_r_2_up_flag;

    assign rst_n = rst_n_in;

// =========================================================================
//  RDC Check Logic
// =========================================================================

always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) begin
        rdc_capture_seen <= 1'b0;
    end
    else if (init_en == 1'b1) begin
        rdc_capture_seen <= 1'b0;
    end
    else if (rdc_burst_done == 1'b1) begin
        rdc_capture_seen <= 1'b0;
    end
    else if ((init_rdc_sample_en == 1'b1) &&
             (channel_rx_dq_capture_en == 1'b1)) begin
        rdc_capture_seen <= 1'b1;
    end
    else begin
        rdc_capture_seen <= rdc_capture_seen;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) begin
        rdc_err_bitmap  <= 16'h0000;
        rdc_check_valid <= 1'b0;
        rdc_check_pass  <= 1'b0;
    end
    else if (init_en == 1'b1) begin
        rdc_err_bitmap  <= 16'h0000;
        rdc_check_valid <= 1'b0;
        rdc_check_pass  <= 1'b0;
    end
    else if ((init_rdc_sample_en == 1'b1) &&
             (channel_rx_dq_capture_en == 1'b1) &&
             (rdc_capture_seen == 1'b0)) begin
        rdc_err_bitmap  <= 16'h0000;
        rdc_check_valid <= 1'b0;
        rdc_check_pass  <= 1'b0;
    end
    else if (rdc_burst_done == 1'b1) begin
        rdc_err_bitmap  <= rdc_err_bitmap_now;
        rdc_check_valid <= 1'b1;
        rdc_check_pass  <= (rdc_err_bitmap_now == 16'h0000);
    end
    else begin
        rdc_err_bitmap  <= rdc_err_bitmap;
        rdc_check_valid <= rdc_check_valid;
        rdc_check_pass  <= rdc_check_pass;
    end
end

// =========================================================================
//  Channel / PHY
// =========================================================================

assign init_enb_lock = init_busy;
assign idd_enb_lock  = idd_busy;
assign mr_enb_lock   = init_runtime_mr_busy;
assign channel_rx_dq_capture_en =
    (chn_state == CHN_INIT) ? init_rx_dq_capture_en      :
    (chn_state == CHN_GF  ) ? gf_engine_rx_dq_capture_en :
                              1'b0;
assign rdc_expect_burst =
    (init_rdc_train_pattern_sel == 1'b1) ? RDC_EXPECT_PATTERN1_BURST :
                                           RDC_EXPECT_PATTERN0_BURST;
assign rdc_err_word0 = dq_a_burst_flat[ 63:  0] ^ rdc_expect_burst[ 63:  0];
assign rdc_err_word1 = dq_a_burst_flat[127: 64] ^ rdc_expect_burst[127: 64];
assign rdc_err_word2 = dq_a_burst_flat[191:128] ^ rdc_expect_burst[191:128];
assign rdc_err_word3 = dq_a_burst_flat[255:192] ^ rdc_expect_burst[255:192];
assign rdc_err_bitmap_now =
       rdc_err_word0[15:0]  | rdc_err_word0[31:16]  |
       rdc_err_word0[47:32] | rdc_err_word0[63:48]  |
       rdc_err_word1[15:0]  | rdc_err_word1[31:16]  |
       rdc_err_word1[47:32] | rdc_err_word1[63:48]  |
       rdc_err_word2[15:0]  | rdc_err_word2[31:16]  |
       rdc_err_word2[47:32] | rdc_err_word2[63:48]  |
       rdc_err_word3[15:0]  | rdc_err_word3[31:16]  |
       rdc_err_word3[47:32] | rdc_err_word3[63:48];
assign rdc_burst_done = (dq_a_burst_valid == 1'b1) &&
                        (rdc_capture_seen == 1'b1);
assign gf_fail_now = gf_compare_window &&
                     (gf_compare_mismatch_odd || gf_compare_mismatch_even);
assign gf_total_start_rise = gf_total_start && !gf_total_start_d;
assign fail_row_key = gf_addr[27:6];
assign fail_row_seen =
       ((fail_row_count > 4'd0) && (fail_addr0[27:6] == fail_row_key))
    || ((fail_row_count > 4'd1) && (fail_addr1[27:6] == fail_row_key))
    || ((fail_row_count > 4'd2) && (fail_addr2[27:6] == fail_row_key));
assign gf_fail_aux_result = {8'h0, fail_row_count, fail_addr2, fail_addr1, fail_addr0};

assign dbg_ascii_stc   = ASCII_STC;
assign dbg_init_busy            = init_busy;
assign dbg_gf_inner_en          = gf_engine_pass_start_d;
assign dbg_gf_total_start       = gf_total_start;
assign dbg_init_done            = init_done;
assign dbg_gf_inner_done        = gf_inner_done;
assign dbg_gf_en_read           = gf_engine_en_read;
assign dbg_gf_en_write          = gf_engine_en_write;
assign dbg_chn_state            = chn_state;
assign dbg_init_mr_cnt          = init_mr_cnt;
assign dbg_gf_addr              = gf_addr;
assign dbg_gf_cnt_read          = gf_engine_cnt_read;
assign dbg_gf_cnt_write         = gf_engine_cnt_write;
assign dbg_gf_state    = gf_engine_state;
assign dbg_gf_op_mode               = gf_op_mode;
assign dbg_gf_read_data_sel         = gf_read_data_sel;
assign dbg_gf_write_data_sel        = gf_write_data_sel;
assign dbg_gf_march_y_mode          = gf_march_y_mode;
assign dbg_gf_read_expected_beat    = gf_read_expected_beat;
assign dbg_gf_compare_window        = gf_compare_window;
assign dbg_gf_compare_mismatch_odd  = gf_compare_mismatch_odd;
assign dbg_gf_compare_mismatch_even = gf_compare_mismatch_even;
assign dbg_gf_err_flag              = gf_engine_err_flag;
assign dbg_gf_fail_now              = gf_fail_now;
// Keep GF selected for the full host GF command.  The outer GF controller
// drops inner_en between write/read passes, but the legacy monolithic core
// kept CK/command ownership continuous across those pass boundaries.
assign gf_enb_lock   = gf_total_start || gf_engine_pass_start_d;

assign runtime_req_allowed =
    (init_enb_lock == 1'b0) &&
    (idd_enb_lock  == 1'b0) &&
    (mr_enb_lock   == 1'b0) &&
    (gf_enb_lock   == 1'b0);
assign runtime_mrw_req_allowed =
    (idd_enb_lock == 1'b0) &&
    (mr_enb_lock  == 1'b0) &&
    (gf_enb_lock  == 1'b0) &&
    ((init_enb_lock == 1'b0) || (rdc_train_busy == 1'b1));
assign runtime_rdc_req_allowed =
    (idd_enb_lock == 1'b0) &&
    (mr_enb_lock  == 1'b0) &&
    (gf_enb_lock  == 1'b0) &&
    ((init_enb_lock == 1'b0) || (rdc_train_busy == 1'b1));
assign idd_edge_detect            = (idd_en_r_2 == 1'b0) && (idd_en_r[0] == 1'b1);
assign mrw_edge_detect            = (mrw_r_2[16] == 1'b0) && (mrw_r_1[16] == 1'b1);
assign mrw_start_pulse            = mrw_r_2_up_flag;
assign rdc_edge_detect            = (mrr_r_2[24] == 1'b0) && (mrr_r_1[24] == 1'b1);
assign rdc_start_pulse            = mrr_r_2_up_flag;
assign mrw_cmd_mux                =
    (rdc_train_busy == 1'b1) ? init_rdc_train_mrw_r : mrw_r;
assign schedule_mrw_req           = runtime_mrw_req_allowed && mrw_start_pulse;
assign schedule_rdc_req           = runtime_rdc_req_allowed && !schedule_mrw_req && rdc_start_pulse;
assign schedule_idd_req           = runtime_req_allowed && !schedule_mrw_req && !schedule_rdc_req && idd_req_pending;
assign idle2mrw                   = schedule_mrw_req;
assign idle2rdc                   = schedule_rdc_req;
assign idle2iddprecharge          = schedule_idd_req;

// GF and INIT read bursts arrive with different command-to-data latency, so
// each path owns its own 6-word capture slice offset inside the PHY buffer.
assign rx_burst_beat_offset       = (chn_state == CHN_GF) ? gf_beat_offset :
                                                            init_beat_offset;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        idd_enb_lock_r <= 1'b0;
    else
        idd_enb_lock_r <= idd_enb_lock;
end

// Keep the IDD source selected for one cycle after the FSM returns to IDLE.
// This preserves the legacy registered-output handoff at the state boundary.
assign idd_channel_enb_lock = idd_enb_lock || idd_enb_lock_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        mr_enb_lock_r <= 1'b0;
    else
        mr_enb_lock_r <= mr_enb_lock;
end

assign mr_channel_enb_lock = mr_enb_lock || mr_enb_lock_r;
assign init_mr_channel_enb_lock = init_enb_lock || mr_channel_enb_lock;
assign chn_state = {gf_enb_lock, idd_channel_enb_lock, init_mr_channel_enb_lock};

// RESET is owned by INIT for the full test lifetime. Runtime engines
// never issue a DRAM reset, and selecting their idle reset would pull it low.
assign channel_reset_n_a = init_wave_reset_n_a;

assign channel_ck_a_run_en =
    (chn_state == CHN_INIT) ? 1'b1                  :
    (chn_state == CHN_GF  ) ? gf_wave_ck_a_run_en   :
                              idd_ref_wave_ck_a_run_en;

assign channel_cs_a_0_rise =
    (chn_state == CHN_INIT) ? init_wave_cs_a_0_rise :
    (chn_state == CHN_GF  ) ? gf_wave_cs_a_0_rise   :
                              idd_ref_wave_cs_a_0_rise;

assign channel_cs_a_0_fall =
    (chn_state == CHN_INIT) ? init_wave_cs_a_0_fall :
    (chn_state == CHN_GF  ) ? gf_wave_cs_a_0_fall   :
                              idd_ref_wave_cs_a_0_fall;

assign channel_ca_a_rise =
    (chn_state == CHN_INIT) ? init_wave_ca_a_rise :
    (chn_state == CHN_GF  ) ? gf_wave_ca_a_rise   :
                              idd_ref_wave_ca_a_rise;

assign channel_ca_a_fall =
    (chn_state == CHN_INIT) ? init_wave_ca_a_fall :
    (chn_state == CHN_GF  ) ? gf_wave_ca_a_fall   :
                              idd_ref_wave_ca_a_fall;

assign channel_wck_a_run_en =
    (chn_state == CHN_INIT) ? init_wave_wck_a_run_en :
    (chn_state == CHN_GF  ) ? gf_wave_wck_a_run_en   :
                              2'b00;

assign channel_wck_a_phase =
    (chn_state == CHN_GF) ? gf_wave_wck_a_phase :
                            2'b00;

always @(posedge clk or negedge rst_n_in) begin
    if (!rst_n_in) begin
        idd_ref_wave_dq_a_in_dh_d <= 16'h0000;
        idd_ref_wave_dq_a_in_dl_d <= 16'h0000;
    end
    else begin
        idd_ref_wave_dq_a_in_dh_d <= idd_ref_wave_dq_a_in_dh;
        idd_ref_wave_dq_a_in_dl_d <= idd_ref_wave_dq_a_in_dl;
    end
end

// INIT only issues command/read operations.  Keep its write data and output
// enables inactive at the scheduler boundary instead of exporting constants.
assign channel_dq_a_tx_word =
    (chn_state == CHN_GF  ) ? gf_wave_dq_a_tx_word :
    (chn_state == CHN_INIT) ? 64'h0000_0000_0000_0000 :
                              {idd_ref_wave_dq_a_in_dh, idd_ref_wave_dq_a_in_dl,
                              idd_ref_wave_dq_a_in_dh_d, idd_ref_wave_dq_a_in_dl_d};

assign channel_dmi_a_tx_word =
    8'h00;

assign channel_rdqs_t_a_in_dh = 2'b00;
assign channel_rdqs_t_a_in_dl = 2'b00;

assign channel_dq_oe =
    (chn_state == CHN_INIT) ? 1'b0                :
    (chn_state == CHN_GF  ) ? gf_wave_dq_oe       :
                              idd_ref_wave_dq_oe;

assign channel_rdqs_oe =
    (chn_state == CHN_INIT) ? 1'b0                 :
                              idd_ref_wave_rdqs_oe;

lpddr5_init U_lpddr5_init (
    .clk                            (clk                            ),
    .rst_n                          (rst_n                          ),
    .init_en                        (init_en                        ),
    .start_mrw                      (idle2mrw                       ),
    .mrw_cmd                        (mrw_r_2                        ),
    .start_rdc                      (idle2rdc                       ),
    .rdc_train_init_en              (rdc_train_init_en              ),
    .rdc_train_apply_best_cfg       (rdc_train_apply_best_cfg       ),
    .rdc_train_dual_pattern_cfg     (rdc_train_dual_pattern_cfg     ),
    .rdc_train_dq_start_cfg         (rdc_train_dq_start_cfg         ),
    .rdc_train_dq_end_cfg           (rdc_train_dq_end_cfg           ),
    .rdc_train_tap_start_cfg        (rdc_train_tap_start_cfg        ),
    .rdc_train_tap_stop_cfg         (rdc_train_tap_stop_cfg         ),
    .rdc_train_tap_step_cfg         (rdc_train_tap_step_cfg         ),
    .rdc_train_dq_delay_l_we        (rdc_train_dq_delay_l_we        ),
    .rdc_train_dq_delay_h_we        (rdc_train_dq_delay_h_we        ),
    .rdc_train_dq_delay_wdat        (rdc_train_dq_delay_wdat        ),
    .rdc_train_scan_tap_sel         (rdc_train_scan_tap_sel         ),
    .rdc_err_bitmap                 (rdc_err_bitmap                 ),
    .rdc_check_valid                (rdc_check_valid                ),
    .rdc_dq_delay_flat              (rdc_dq_delay_flat              ),
    .rdc_train_mrw_r                (init_rdc_train_mrw_r           ),
    .rdc_train_mrr_r                (init_rdc_train_mrr_r           ),
    .rdc_train_state                (rdc_train_state                ),
    .rdc_train_busy                 (rdc_train_busy                 ),
    .rdc_train_done                 (rdc_train_done                 ),
    .rdc_train_apply_best           (rdc_train_apply_best           ),
    .rdc_train_dq_start             (rdc_train_dq_start             ),
    .rdc_train_tap                  (rdc_train_tap                  ),
    .rdc_train_pattern_sel          (init_rdc_train_pattern_sel     ),
    .rdc_train_status_best_len      (rdc_train_status_best_len      ),
    .rdc_train_pass_mask            (rdc_train_pass_mask            ),
    .rdc_train_fail_mask            (rdc_train_fail_mask            ),
    .rdc_train_last_err_bitmap      (rdc_train_last_err_bitmap      ),
    .rdc_train_init_ready           (rdc_train_init_ready           ),
    .rdc_train_pass_all             (rdc_train_pass_all             ),
    .rdc_train_best_flat            (rdc_train_best_flat            ),
    .rdc_train_left_flat            (rdc_train_left_flat            ),
    .rdc_train_right_flat           (rdc_train_right_flat           ),
    .rdc_train_scan_pass_bitmap     (rdc_train_scan_pass_bitmap     ),
    .read_capture_start_cnt         (read_capture_start_cnt         ),
    .dq_a_word_flat                 (dq_a_word_flat                 ),
    .dq_a_word_valid                (dq_a_word_valid                ),
    .init_busy                      (init_busy                      ),
    .init_done                      (init_done                      ),
    .init_fail                      (init_fail                      ),
    .init_state                     (init_state                     ),
    .runtime_mr_busy                (init_runtime_mr_busy           ),
    .rdc_sample_en                  (init_rdc_sample_en             ),
    .rx_dq_capture_en              (init_rx_dq_capture_en         ),
    .ascii_state                    (init_ascii_state               ),
    .die_message                    (die_message                    ),
    .init_mr_cnt                    (init_mr_cnt                    ),
    .wave_reset_n_a                 (init_wave_reset_n_a            ),
    .wave_cs_a_0_rise              (init_wave_cs_a_0_rise          ),
    .wave_cs_a_0_fall              (init_wave_cs_a_0_fall          ),
    .wave_ca_a_rise                (init_wave_ca_a_rise            ),
    .wave_ca_a_fall                (init_wave_ca_a_fall            ),
    .wave_wck_a_run_en             (init_wave_wck_a_run_en         )
);

lpddr5_idd U_lpddr5_idd (
    .clk                            (clk                            ),
    .rst_n                          (rst_n                          ),
    .start_idd                      (idle2iddprecharge              ),
    .idd_en_r                       (idd_en_r                       ),
    .cnt_bg                         (gf_engine_cnt_bg               ),
    .cnt_ba                         (gf_engine_cnt_ba               ),
    .idd_busy                       (idd_busy                       ),
    .idd_state                      (idd_state                      ),
    .idd_done                       (idd_ref_done                   ),
    .idd_ck_stop                    (idd_ck_stop                    ),
    .ascii_state                    (idd_ascii_state                ),
    .wave_ck_a_run_en               (idd_ref_wave_ck_a_run_en       ),
    .wave_cs_a_0_rise              (idd_ref_wave_cs_a_0_rise       ),
    .wave_cs_a_0_fall              (idd_ref_wave_cs_a_0_fall       ),
    .wave_ca_a_rise                (idd_ref_wave_ca_a_rise         ),
    .wave_ca_a_fall                (idd_ref_wave_ca_a_fall         ),
    .wave_dq_a_in_dh                (idd_ref_wave_dq_a_in_dh        ),
    .wave_dq_a_in_dl                (idd_ref_wave_dq_a_in_dl        ),
    .wave_dq_oe                     (idd_ref_wave_dq_oe             ),
    .wave_rdqs_oe                   (idd_ref_wave_rdqs_oe           )
);

lpddr5_gf_engine U_lpddr5_gf_engine (
    .clk                            (clk                            ),
    .rst_n                          (rst_n                          ),
    .engine_inhibit                 (init_enb_lock || idd_channel_enb_lock || mr_channel_enb_lock),
    .idd_ck_stop                    (idd_ck_stop                    ),
    .GF_start_col                   (gf_start_col                   ),
    .GF_end_col                     (gf_end_col                     ),
    .GF_start_row                   (gf_start_row                   ),
    .GF_end_row                     (gf_end_row                     ),
    .GF_start_bg                    (gf_start_bg                    ),
    .GF_end_bg                      (gf_end_bg                      ),
    .GF_start_ba                    (gf_start_ba                    ),
    .GF_end_ba                      (gf_end_ba                      ),
    .gf_test_en                     (gf_total_start                 ),
    .gf_pass_start                  (gf_inner_start                 ),
    .gf_op_mode                     (gf_op_mode                     ),
    .gf_read_data_sel               (gf_read_data_sel               ),
    .gf_write_data_sel              (gf_write_data_sel              ),
    .march_y_sequence               (gf_march_y_mode                ),
    .die_message                    (die_message                    ),
    .read_capture_start_cnt         (gf_capture_start_cnt           ),
    .gf_rd_wck_start_cnt            (gf_rd_wck_start_cnt            ),
    .gf_rd_wck_last_cnt             (gf_rd_wck_last_cnt             ),
    .gf_wr_wck_start_cnt            (gf_wr_wck_start_cnt            ),
    .gf_wr_wck_last_cnt             (gf_wr_wck_last_cnt             ),
    .gf_read_done_cnt               (gf_read_done_cnt               ),
    .gf_write_done_cnt              (gf_write_done_cnt              ),
    .gf_act_cmd_gap_cnt             (gf_act_cmd_gap_cnt             ),
    .gf_rd_cmd_gap_cnt              (gf_rd_cmd_gap_cnt              ),
    .gf_wr_cmd_gap_cnt              (gf_wr_cmd_gap_cnt              ),
    .gf_pre_cmd_gap_cnt             (gf_pre_cmd_gap_cnt             ),
    .gf_refresh_batch_num           (gf_refresh_batch_num           ),
    .gf_pattern_mode_cfg            (gf_pattern_mode_cfg            ),
    .dq_a_burst_flat                (dq_a_burst_flat                ),
    .dq_a_burst_valid               (dq_a_burst_valid               ),
    .err_cnt_GF                     (gf_error_count                 ),
    .err_block_cnt                  (err_block_cnt                  ),
    .err_block_message              (err_block_message              ),
    .gf_pass_done                   (gf_inner_done                  ),
    .gf_state                       (gf_engine_state                ),
    .gf_pass_start_d                (gf_engine_pass_start_d         ),
    .gf_en_read                     (gf_engine_en_read              ),
    .gf_en_write                    (gf_engine_en_write             ),
    .rx_dq_capture_en               (gf_engine_rx_dq_capture_en     ),
    .gf_err_flag                    (gf_engine_err_flag             ),
    .gf_cnt_read_value              (gf_engine_cnt_read             ),
    .gf_cnt_write_value             (gf_engine_cnt_write            ),
    .gf_compare_window              (gf_compare_window              ),
    .gf_compare_mismatch_odd        (gf_compare_mismatch_odd        ),
    .gf_compare_mismatch_even       (gf_compare_mismatch_even       ),
    .gf_access_addr                 (gf_addr                        ),
    .gf_read_expected_beat          (gf_read_expected_beat           ),
    .gf_cnt_ba                      (gf_engine_cnt_ba               ),
    .gf_cnt_bg                      (gf_engine_cnt_bg               ),
    .gf_cnt_row                     (gf_engine_cnt_row              ),
    .gf_cnt_col                     (gf_engine_cnt_col              ),
    .gf_cnt_row_ns                  (gf_engine_cnt_row_ns           ),
    .ascii_state                    (gf_ascii_state                 ),
    .wave_ck_a_run_en               (gf_wave_ck_a_run_en            ),
    .wave_cs_a_0_rise              (gf_wave_cs_a_0_rise            ),
    .wave_cs_a_0_fall              (gf_wave_cs_a_0_fall            ),
    .wave_ca_a_rise                (gf_wave_ca_a_rise              ),
    .wave_ca_a_fall                (gf_wave_ca_a_fall              ),
    .wave_wck_a_run_en             (gf_wave_wck_a_run_en           ),
    .wave_wck_a_phase              (gf_wave_wck_a_phase            ),
    .wave_dq_a_tx_word              (gf_wave_dq_a_tx_word           ),
    .wave_dq_oe                     (gf_wave_dq_oe                  )
);

assign idd_done = idd_ref_done;

// =========================================================================
//  Input Pipeline
// =========================================================================

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        idd_en_r                        <= 10'd0;
        idd_en_r_2                      <= 1'b0;
    end
    else begin
        idd_en_r                        <= idd_en;
        idd_en_r_2                      <= idd_en_r[0];
    end
end

// Latch the host IDD request until the scheduler can accept it.  This follows
// the LP4 lock style and prevents a one-cycle IDD start from being lost while
// INIT/MR/GF still owns the channel.
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        idd_req_pending  <= 1'b0;
        idd_req_inflight <= 1'b0;
    end
    else if (!idd_en_r[0]) begin
        idd_req_pending  <= 1'b0;
        idd_req_inflight <= 1'b0;
    end
    else begin
        if (schedule_idd_req) begin
            idd_req_pending  <= 1'b0;
            idd_req_inflight <= 1'b1;
        end
        else if ((idd_edge_detect || !idd_req_inflight) && !idd_req_pending) begin
            idd_req_pending <= 1'b1;
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fail_row_count <= 4'd0;
        fail_addr0     <= 28'd0;
        fail_addr1     <= 28'd0;
        fail_addr2     <= 28'd0;
    end
    else if (gf_total_start_rise) begin
        fail_row_count <= 4'd0;
        fail_addr0     <= 28'd0;
        fail_addr1     <= 28'd0;
        fail_addr2     <= 28'd0;
    end
    else if (gf_fail_now && !fail_row_seen && (fail_row_count < 4'd3)) begin
        if (fail_row_count == 4'd0)
            fail_addr0 <= gf_addr;
        else if (fail_row_count == 4'd1)
            fail_addr1 <= gf_addr;
        else if (fail_row_count == 4'd2)
            fail_addr2 <= gf_addr;

        if (fail_row_count != 4'hF)
            fail_row_count <= fail_row_count + 4'd1;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mrw_r_1                     <= 24'd0;
        mrw_r_2                     <= 24'd0;
        mrr_r_1                     <= 32'd0;
        mrr_r_2                     <= 32'd0;
        gf_total_start_d            <= 1'b0;
    end
    else begin
        mrw_r_1                     <= mrw_cmd_mux;
        mrw_r_2                     <= mrw_r_1;
        mrr_r_1                     <= init_rdc_train_mrr_r;
        mrr_r_2                     <= mrr_r_1;
        gf_total_start_d            <= gf_total_start;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        mrw_r_2_up_flag <= 1'b0;
    else if (mrw_edge_detect)
        mrw_r_2_up_flag <= 1'b1;
    else
        mrw_r_2_up_flag <= 1'b0;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        mrr_r_2_up_flag <= 1'b0;
    else if (rdc_edge_detect)
        mrr_r_2_up_flag <= 1'b1;
    else
        mrr_r_2_up_flag <= 1'b0;
end

// =========================================================================
//  ILA
// =========================================================================

// ASCII state display for ILA
always @(*) begin
    if (init_busy) begin
        ASCII_STC = init_ascii_state;
    end
    else if (idd_busy) begin
        ASCII_STC = idd_ascii_state;
    end
    else if (init_runtime_mr_busy) begin
        ASCII_STC = init_ascii_state;
    end
    else begin
        ASCII_STC = gf_ascii_state;
    end
end

endmodule
