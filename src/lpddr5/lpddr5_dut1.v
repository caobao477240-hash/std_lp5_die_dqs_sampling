`timescale 1ns / 1ps

// =========================================================================
//  LPDDR5 DUT1 Wrapper
// =========================================================================
// Connects BAR-driven test requests to the LPDDR5 channel path:
//   - lpddr5_gf sequences full GF test steps.
//   - lpddr5_test_scheduler arbitrates INIT, IDD, GF, and runtime MR waves.
//   - lpddr5_channel converts the selected edge waveform to device pins.
module lpddr5_dut1 (
    // Clock / Reset
    input               i_clk_core_200m             ,
    input               i_clk_dq_tx_400m            ,
    input               i_clk_ca_wck_400m           ,
    input               i_clk_dq_rx_400m            ,
    input               i_serdes_reset_n            ,
    input               rst_n_in                    ,

    input               GF_total_en                 ,
    output              GF_total_done               ,
    output     [95:0]   GF_result_data              ,
    output     [95:0]   GF_fail_aux_result          ,

    // LPDDR5 channel A pads
    output              reset_n_a                   ,
    output              ck_t_a                      ,
    output              ck_c_a                      ,
    output              cs0_a                       ,
    output     [6:0]    ca_a                        ,
    inout      [15:0]   dq_a                        ,
    output     [1:0]    wck_t_a                     ,
    output     [1:0]    wck_c_a                     ,
    inout      [1:0]    rdqs_t_a                    ,
    inout      [1:0]    rdqs_c_a                    ,
    inout      [1:0]    dmi_a                       ,

    // INIT / MRW / runtime RDC
    input               init_en                     ,
    output              init_done                   ,
    output              init_fail                   ,
    input      [23:0]   mrw_r                       ,

    // IDD
    input      [9:0]    idd_en                      ,
    output              idd_done                    ,

    // Calibration / readback
    input      [7:0]    read_capture_start_cnt      ,
    input      [7:0]    gf_capture_start_cnt        ,
    input      [3:0]    init_beat_offset            ,
    input      [3:0]    gf_beat_offset              ,
    input      [9:0]    gf_rd_wck_start_cnt         ,
    input      [9:0]    gf_rd_wck_last_cnt          ,
    input      [9:0]    gf_wr_wck_start_cnt         ,
    input      [9:0]    gf_wr_wck_last_cnt          ,
    input      [9:0]    gf_read_done_cnt            ,
    input      [9:0]    gf_write_done_cnt           ,
    input      [9:0]    gf_act_cmd_gap_cnt          ,
    input      [9:0]    gf_rd_cmd_gap_cnt           ,
    input      [9:0]    gf_wr_cmd_gap_cnt           ,
    input      [9:0]    gf_pre_cmd_gap_cnt          ,
    input      [2:0]    gf_refresh_batch_num        ,
    input      [1:0]    gf_pattern_mode_cfg         ,
    output     [7:0]    die_message                 ,
    output     [7:0]    err_block_cnt               ,
    output     [63:0]   err_block_message           ,
    output     [15:0]   rdc_err_bitmap              ,
    output              rdc_check_valid             ,
    output              rdc_check_pass              ,
    input               rdc_train_init_en           ,
    input               rdc_train_apply_best_cfg    ,
    input               rdc_train_dual_pattern_cfg  ,
    input      [3:0]    rdc_train_dq_start_cfg      ,
    input      [3:0]    rdc_train_dq_end_cfg        ,
    input      [8:0]    rdc_train_tap_start_cfg     ,
    input      [8:0]    rdc_train_tap_stop_cfg      ,
    input      [8:0]    rdc_train_tap_step_cfg      ,
    input               rdc_train_dq_delay_l_we     ,
    input               rdc_train_dq_delay_h_we     ,
    input      [95:0]   rdc_train_dq_delay_wdat     ,
    input      [8:0]    rdc_train_scan_tap_sel      ,
    output     [3:0]    rdc_train_state             ,
    output              rdc_train_busy              ,
    output              rdc_train_done              ,
    output              rdc_train_apply_best        ,
    output     [3:0]    rdc_train_dq_start          ,
    output     [8:0]    rdc_train_tap               ,
    output     [9:0]    rdc_train_status_best_len   ,
    output     [15:0]   rdc_train_pass_mask         ,
    output     [15:0]   rdc_train_fail_mask         ,
    output     [15:0]   rdc_train_last_err_bitmap   ,
    output              rdc_train_init_ready        ,
    output              rdc_train_pass_all          ,
    output     [143:0]  rdc_train_best_flat         ,
    output     [143:0]  rdc_train_left_flat         ,
    output     [143:0]  rdc_train_right_flat        ,
    output     [15:0]   rdc_train_scan_pass_bitmap  ,
    input               RDY                         ,

    // IDELAY controls
    output     [143:0]  delay_value_dq_a
);

// =========================================================================
//  Internal Wires
// =========================================================================

    wire                dut1_init_done_cha;
    wire                dut1_init_fail_cha;
    wire                idd_done_cha;

    wire                gf_step_start;
    wire                gf_step_done;
    wire [5:0]          gf_step_start_col;
    wire [5:0]          gf_step_end_col;
    wire [17:0]         gf_step_start_row;
    wire [17:0]         gf_step_end_row;
    wire [1:0]          gf_step_start_bg;
    wire [1:0]          gf_step_end_bg;
    wire [1:0]          gf_step_start_ba;
    wire [1:0]          gf_step_end_ba;
    wire [31:0]         gf_error_count;

    wire [1:0]          gf_op_mode;
    wire                gf_read_data_sel;
    wire                gf_write_data_sel;
    wire                gf_march_y_mode;

    wire                channel_ck_a_run_en;
    wire                channel_reset_n_a;
    wire                channel_cs_a_0_rise;
    wire                channel_cs_a_0_fall;
    wire [6:0]          channel_ca_a_rise;
    wire [6:0]          channel_ca_a_fall;
    wire [1:0]          channel_wck_a_run_en;
    wire [1:0]          channel_wck_a_phase;
    wire [63:0]         channel_dq_a_tx_word;
    wire [7:0]          channel_dmi_a_tx_word;
    wire [1:0]          channel_rdqs_t_a_in_dh;
    wire [1:0]          channel_rdqs_t_a_in_dl;
    wire                channel_dq_oe;
    wire                channel_rdqs_oe;
    wire                channel_rx_dq_capture_en;
    wire [63:0]         dq_a_word_flat;
    wire                dq_a_word_valid;
    wire [111:0]        dbg_ascii_stc;
    wire                dbg_init_busy;
    wire                dbg_gf_inner_en;
    wire                dbg_gf_total_start;
    wire                dbg_init_done;
    wire                dbg_gf_inner_done;
    wire                dbg_gf_en_read;
    wire                dbg_gf_en_write;
    wire [2:0]          dbg_chn_state;
    wire [10:0]         init_mr_cnt;
    wire [27:0]         gf_addr;
    wire [9:0]          gf_cnt_read;
    wire [9:0]          gf_cnt_write;
    wire [20:0]         gf_state;
    wire [255:0]        dq_a_burst_flat;
    wire                dq_a_burst_valid;
    wire [3:0]          rx_burst_beat_offset;
    wire [63:0]         dbg_dq_word_raw;
    wire [1:0]          dbg_gf_op_mode;
    wire                dbg_gf_read_data_sel;
    wire                dbg_gf_write_data_sel;
    wire                dbg_gf_march_y_mode;
    wire [15:0]         dbg_gf_read_expected_beat;
    wire                dbg_gf_compare_window;
    wire                dbg_gf_compare_mismatch_odd;
    wire                dbg_gf_compare_mismatch_even;
    wire                dbg_gf_err_flag;
    wire                dbg_gf_fail_now;

// =========================================================================
//  GF Control
// =========================================================================

lpddr5_gf U_lpddr5_gf (
    .cha_core_clk       (i_clk_core_200m       ),
    .cha_phy_rst_n      (rst_n_in              ),
    .clk_200m           (i_clk_core_200m       ),
    .rst_n              (rst_n_in              ),

    .die_message        (die_message           ),
    .gf_op_mode         (gf_op_mode            ),
    .gf_read_data_sel   (gf_read_data_sel      ),
    .gf_write_data_sel  (gf_write_data_sel     ),
    .march_y_sequence   (gf_march_y_mode       ),

    .GF_total_en        (GF_total_en           ),
    .GF_total_done      (GF_total_done         ),
    .GF_result_data     (GF_result_data        ),

    .cha_GF_inner_en    (gf_step_start         ),
    .cha_GF_inner_done  (gf_step_done          ),
    .cha_err_cnt_GF     (gf_error_count        ),
    .cha_GF_start_col   (gf_step_start_col     ),
    .cha_GF_end_col     (gf_step_end_col       ),
    .cha_GF_start_row   (gf_step_start_row     ),
    .cha_GF_end_row     (gf_step_end_row       ),
    .cha_GF_start_bg    (gf_step_start_bg      ),
    .cha_GF_end_bg      (gf_step_end_bg        ),
    .cha_GF_start_ba    (gf_step_start_ba      ),
    .cha_GF_end_ba      (gf_step_end_ba        )
);

// =========================================================================
//  LPDDR5 Test Scheduler
// =========================================================================

lpddr5_test_scheduler U_lpddr5_test_scheduler (
    .clk                             (i_clk_core_200m                  ),
    .rst_n_in                        (rst_n_in                         ),
    .channel_ck_a_run_en             (channel_ck_a_run_en              ),
    .channel_reset_n_a               (channel_reset_n_a                ),
    .channel_cs_a_0_rise            (channel_cs_a_0_rise             ),
    .channel_cs_a_0_fall            (channel_cs_a_0_fall             ),
    .channel_ca_a_rise              (channel_ca_a_rise               ),
    .channel_ca_a_fall              (channel_ca_a_fall               ),
    .channel_wck_a_run_en           (channel_wck_a_run_en            ),
    .channel_wck_a_phase            (channel_wck_a_phase             ),
    .channel_dq_a_tx_word            (channel_dq_a_tx_word             ),
    .channel_dmi_a_tx_word           (channel_dmi_a_tx_word            ),
    .channel_rdqs_t_a_in_dh          (channel_rdqs_t_a_in_dh           ),
    .channel_rdqs_t_a_in_dl          (channel_rdqs_t_a_in_dl           ),
    .channel_dq_oe                   (channel_dq_oe                    ),
    .channel_rdqs_oe                 (channel_rdqs_oe                  ),
    .channel_rx_dq_capture_en        (channel_rx_dq_capture_en         ),
    .dq_a_word_flat                  (dq_a_word_flat                   ),
    .dq_a_word_valid                 (dq_a_word_valid                  ),
    .dq_a_burst_flat                 (dq_a_burst_flat                  ),
    .dq_a_burst_valid                (dq_a_burst_valid                 ),

    .init_en                         (init_en                          ),
    .init_done                       (dut1_init_done_cha               ),
    .init_fail                       (dut1_init_fail_cha               ),
    .mrw_r                           (mrw_r                            ),
    .idd_en                          (idd_en                           ),
    .idd_done                        (idd_done_cha                     ),

    .rdc_err_bitmap                  (rdc_err_bitmap                   ),
    .rdc_check_valid                 (rdc_check_valid                  ),
    .rdc_check_pass                  (rdc_check_pass                   ),
    .rdc_train_init_en               (rdc_train_init_en                ),
    .rdc_train_apply_best_cfg        (rdc_train_apply_best_cfg         ),
    .rdc_train_dual_pattern_cfg      (rdc_train_dual_pattern_cfg       ),
    .rdc_train_dq_start_cfg          (rdc_train_dq_start_cfg           ),
    .rdc_train_dq_end_cfg            (rdc_train_dq_end_cfg             ),
    .rdc_train_tap_start_cfg         (rdc_train_tap_start_cfg          ),
    .rdc_train_tap_stop_cfg          (rdc_train_tap_stop_cfg           ),
    .rdc_train_tap_step_cfg          (rdc_train_tap_step_cfg           ),
    .rdc_train_dq_delay_l_we         (rdc_train_dq_delay_l_we          ),
    .rdc_train_dq_delay_h_we         (rdc_train_dq_delay_h_we          ),
    .rdc_train_dq_delay_wdat         (rdc_train_dq_delay_wdat          ),
    .rdc_train_scan_tap_sel          (rdc_train_scan_tap_sel           ),
    .rdc_dq_delay_flat               (delay_value_dq_a                 ),
    .rdc_train_state                 (rdc_train_state                  ),
    .rdc_train_busy                  (rdc_train_busy                   ),
    .rdc_train_done                  (rdc_train_done                   ),
    .rdc_train_apply_best            (rdc_train_apply_best             ),
    .rdc_train_dq_start              (rdc_train_dq_start               ),
    .rdc_train_tap                   (rdc_train_tap                    ),
    .rdc_train_status_best_len       (rdc_train_status_best_len        ),
    .rdc_train_pass_mask             (rdc_train_pass_mask              ),
    .rdc_train_fail_mask             (rdc_train_fail_mask              ),
    .rdc_train_last_err_bitmap       (rdc_train_last_err_bitmap        ),
    .rdc_train_init_ready            (rdc_train_init_ready             ),
    .rdc_train_pass_all              (rdc_train_pass_all               ),
    .rdc_train_best_flat             (rdc_train_best_flat              ),
    .rdc_train_left_flat             (rdc_train_left_flat              ),
    .rdc_train_right_flat            (rdc_train_right_flat             ),
    .rdc_train_scan_pass_bitmap      (rdc_train_scan_pass_bitmap       ),

    .read_capture_start_cnt          (read_capture_start_cnt           ),
    .gf_capture_start_cnt            (gf_capture_start_cnt             ),
    .init_beat_offset                (init_beat_offset                 ),
    .gf_beat_offset                  (gf_beat_offset                   ),
    .rx_burst_beat_offset            (rx_burst_beat_offset             ),
    .gf_rd_wck_start_cnt             (gf_rd_wck_start_cnt              ),
    .gf_rd_wck_last_cnt              (gf_rd_wck_last_cnt               ),
    .gf_wr_wck_start_cnt             (gf_wr_wck_start_cnt              ),
    .gf_wr_wck_last_cnt              (gf_wr_wck_last_cnt               ),
    .gf_read_done_cnt                (gf_read_done_cnt                 ),
    .gf_write_done_cnt               (gf_write_done_cnt                ),
    .gf_act_cmd_gap_cnt              (gf_act_cmd_gap_cnt               ),
    .gf_rd_cmd_gap_cnt               (gf_rd_cmd_gap_cnt                ),
    .gf_wr_cmd_gap_cnt               (gf_wr_cmd_gap_cnt                ),
    .gf_pre_cmd_gap_cnt              (gf_pre_cmd_gap_cnt               ),
    .gf_refresh_batch_num            (gf_refresh_batch_num             ),
    .gf_pattern_mode_cfg             (gf_pattern_mode_cfg              ),
    .die_message                     (die_message                      ),

    .gf_start_col                    (gf_step_start_col                ),
    .gf_end_col                      (gf_step_end_col                  ),
    .gf_start_row                    (gf_step_start_row                ),
    .gf_end_row                      (gf_step_end_row                  ),
    .gf_start_bg                     (gf_step_start_bg                 ),
    .gf_end_bg                       (gf_step_end_bg                   ),
    .gf_start_ba                     (gf_step_start_ba                 ),
    .gf_end_ba                       (gf_step_end_ba                   ),
    .gf_error_count                  (gf_error_count                   ),
    .err_block_cnt                   (err_block_cnt                    ),
    .err_block_message               (err_block_message                ),
    .gf_total_start                  (GF_total_en                      ),
    .gf_inner_start                  (gf_step_start                    ),
    .gf_inner_done                   (gf_step_done                     ),
    .gf_op_mode                      (gf_op_mode                       ),
    .gf_read_data_sel                (gf_read_data_sel                 ),
    .gf_write_data_sel               (gf_write_data_sel                ),
    .gf_march_y_mode                 (gf_march_y_mode                  ),
    .gf_fail_aux_result              (GF_fail_aux_result               ),

    .dbg_ascii_stc                   (dbg_ascii_stc                    ),
    .dbg_init_busy                   (dbg_init_busy                    ),
    .dbg_gf_inner_en                 (dbg_gf_inner_en                  ),
    .dbg_gf_total_start              (dbg_gf_total_start               ),
    .dbg_init_done                   (dbg_init_done                    ),
    .dbg_gf_inner_done               (dbg_gf_inner_done                ),
    .dbg_gf_en_read                  (dbg_gf_en_read                   ),
    .dbg_gf_en_write                 (dbg_gf_en_write                  ),
    .dbg_chn_state                   (dbg_chn_state                    ),
    .dbg_init_mr_cnt                 (init_mr_cnt                      ),
    .dbg_gf_addr                     (gf_addr                          ),
    .dbg_gf_cnt_read                 (gf_cnt_read                      ),
    .dbg_gf_cnt_write                (gf_cnt_write                     ),
    .dbg_gf_state                    (gf_state                         ),
    .dbg_gf_op_mode                  (dbg_gf_op_mode                   ),
    .dbg_gf_read_data_sel            (dbg_gf_read_data_sel             ),
    .dbg_gf_write_data_sel           (dbg_gf_write_data_sel            ),
    .dbg_gf_march_y_mode             (dbg_gf_march_y_mode              ),
    .dbg_gf_read_expected_beat       (dbg_gf_read_expected_beat        ),
    .dbg_gf_compare_window           (dbg_gf_compare_window            ),
    .dbg_gf_compare_mismatch_odd     (dbg_gf_compare_mismatch_odd      ),
    .dbg_gf_compare_mismatch_even    (dbg_gf_compare_mismatch_even     ),
    .dbg_gf_err_flag                 (dbg_gf_err_flag                  ),
    .dbg_gf_fail_now                 (dbg_gf_fail_now                  )
);

// =========================================================================
//  LPDDR5 Channel A PHY
// =========================================================================

lpddr5_channel U_lpddr5_channel (
    .i_clk_core_200m                 (i_clk_core_200m                  ),
    .i_clk_dq_tx_400m                (i_clk_dq_tx_400m                 ),
    .i_clk_ca_wck_400m               (i_clk_ca_wck_400m                ),
    .i_clk_dq_rx_400m                (i_clk_dq_rx_400m                 ),
    .i_serdes_reset_n                (i_serdes_reset_n                 ),
    .rst_n                           (rst_n_in                         ),

    .reset_n_a                       (reset_n_a                        ),
    .ck_t_a                          (ck_t_a                           ),
    .ck_c_a                          (ck_c_a                           ),
    .cs0_a                           (cs0_a                            ),
    .ca_a                            (ca_a                             ),
    .dq_a                            (dq_a                             ),
    .wck_t_a                         (wck_t_a                          ),
    .wck_c_a                         (wck_c_a                          ),
    .rdqs_t_a                        (rdqs_t_a                         ),
    .rdqs_c_a                        (rdqs_c_a                         ),
    .dmi_a                           (dmi_a                            ),

    .ck_a_run_en                     (channel_ck_a_run_en              ),
    .wck_a_run_en                    (channel_wck_a_run_en             ),
    .wck_a_phase                     (channel_wck_a_phase              ),
    .reset_n_a_level                 (channel_reset_n_a                ),
    .cs_a_0_rise                     (channel_cs_a_0_rise              ),
    .cs_a_0_fall                     (channel_cs_a_0_fall              ),
    .ca_a_rise                       (channel_ca_a_rise                ),
    .ca_a_fall                       (channel_ca_a_fall                ),
    .dq_a_tx_word                    (channel_dq_a_tx_word             ),
    .dmi_a_tx_word                   (channel_dmi_a_tx_word            ),
    .dq_a_word_flat                  (dq_a_word_flat                   ),
    .dq_a_word_valid                 (dq_a_word_valid                  ),
    .dq_a_burst_flat                 (dq_a_burst_flat                  ),
    .dq_a_burst_valid                (dq_a_burst_valid                 ),
    .rdqs_t_a_in_dh                  (channel_rdqs_t_a_in_dh           ),
    .rdqs_t_a_in_dl                  (channel_rdqs_t_a_in_dl           ),
    .dq_a_tx_oe                      (channel_dq_oe                    ),
    .cha_group_0_strobe_out_en       (channel_rdqs_oe                  ),
    .rx_dq_capture_en                (channel_rx_dq_capture_en         ),
    .rx_burst_beat_offset            (rx_burst_beat_offset             ),
    .dbg_dq_word_raw                 (dbg_dq_word_raw                  ),
    .RDY                             (RDY                              ),
    .delay_value_dq_a                (delay_value_dq_a                 )
);

// =========================================================================
//  800M GF/DQ Debug ILA
// =========================================================================

ila_0 ila_lp5_prod_debug (
    .clk     (i_clk_core_200m),
    .probe0  (dbg_ascii_stc),
    .probe1  (dbg_chn_state),
    .probe2  (dbg_init_busy),
    .probe3  (dbg_init_done),
    .probe4  (init_mr_cnt),
    .probe5  (die_message),
    .probe6  (rdc_train_pass_mask),
    .probe7  (rdc_train_pass_all),
    .probe8  (read_capture_start_cnt),
    .probe9  (channel_rx_dq_capture_en),
    .probe10 (dbg_dq_word_raw),
    .probe11 (dq_a_burst_valid),
    .probe12 (dq_a_burst_flat),
    .probe13 (rdc_check_valid),
    .probe14 (rdc_check_pass),
    .probe15 (rdc_err_bitmap),
    .probe16 (dbg_gf_total_start),
    .probe17 (GF_total_done),
    .probe18 (dbg_gf_inner_en),
    .probe19 (dbg_gf_inner_done),
    .probe20 (gf_state),
    .probe21 (gf_addr),
    .probe22 (dbg_gf_op_mode),
    .probe23 (dbg_gf_march_y_mode),
    .probe24 (dbg_gf_write_data_sel),
    .probe25 (dbg_gf_read_data_sel),
    .probe26 (dbg_gf_en_write),
    .probe27 (gf_cnt_write),
    .probe28 (channel_dq_oe),
    .probe29 (channel_dq_a_tx_word),
    .probe30 (dbg_gf_en_read),
    .probe31 (gf_cnt_read),
    .probe32 (dbg_gf_read_expected_beat),
    .probe33 (dbg_gf_compare_window),
    .probe34 (dbg_gf_compare_mismatch_odd),
    .probe35 (dbg_gf_compare_mismatch_even),
    .probe36 (gf_error_count),
    .probe37 (dbg_gf_err_flag),
    .probe38 (dbg_gf_fail_now),
    .probe39 (dq_a_word_valid)
);

// =========================================================================
//  Single-DUT Done Aggregation
// =========================================================================

    assign init_done = dut1_init_done_cha;
    assign init_fail = dut1_init_fail_cha;
    assign idd_done  = idd_done_cha;

endmodule
