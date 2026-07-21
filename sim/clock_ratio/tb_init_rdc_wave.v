`timescale 1ps / 1ps

module tb_init_rdc_wave;

/***************parameter*************/
localparam integer P_INIT_TIMEOUT_CYCLES = 100000;

/***************reg*******************/
reg                 clk_200m;
reg                 clk_400m;
reg                 rst_n;
reg                 init_en;
reg  [ 63:0]        dq_a_word_flat;
reg                 dq_a_word_valid;
reg  [255:0]        dq_a_burst_flat;
reg                 dq_a_burst_valid;
reg                 r_init_word_pending;
reg                 r_rdc_burst_pending;
reg                 r_init_fail_seen;

integer             r_init_wait_cycles;
integer             r_init_word_count;
integer             r_rdc_capture_count;
integer             r_rdc_result_count;
integer             r_error_count;

/***************wire******************/
wire                channel_ck_a_run_en;
wire                channel_reset_n_a;
wire                channel_cs_a_0_rise;
wire                channel_cs_a_0_fall;
wire [  6:0]        channel_ca_a_rise;
wire [  6:0]        channel_ca_a_fall;
wire [  1:0]        channel_wck_a_run_en;
wire [  1:0]        channel_wck_a_phase;
wire [ 63:0]        channel_dq_a_tx_word;
wire [  7:0]        channel_dmi_a_tx_word;
wire [  1:0]        channel_rdqs_t_a_in_dh;
wire [  1:0]        channel_rdqs_t_a_in_dl;
wire                channel_dq_oe;
wire                channel_rdqs_oe;
wire                channel_rx_dq_capture_en;

wire                init_done;
wire                init_fail;
wire [ 15:0]        rdc_err_bitmap;
wire                rdc_check_valid;
wire                rdc_check_pass;
wire [143:0]        rdc_dq_delay_flat;
wire [  3:0]        rdc_train_state;
wire                rdc_train_busy;
wire                rdc_train_done;
wire                rdc_train_apply_best;
wire [  3:0]        rdc_train_dq_start;
wire [  8:0]        rdc_train_tap;
wire [  9:0]        rdc_train_status_best_len;
wire [ 15:0]        rdc_train_pass_mask;
wire [ 15:0]        rdc_train_fail_mask;
wire [ 15:0]        rdc_train_last_err_bitmap;
wire                rdc_train_init_ready;
wire                rdc_train_pass_all;
wire [143:0]        rdc_train_best_flat;
wire [143:0]        rdc_train_left_flat;
wire [143:0]        rdc_train_right_flat;
wire [ 15:0]        rdc_train_scan_pass_bitmap;
wire [  3:0]        rx_burst_beat_offset;
wire [  7:0]        die_message;

wire [111:0]        dbg_ascii_stc;
wire                dbg_init_busy;
wire [  2:0]        dbg_chn_state;
wire [ 10:0]        dbg_init_mr_cnt;

wire                reset_n_a_out;
wire                ck_a_out;
wire                cs_a_out;
wire [  6:0]        ca_a_out;
wire [  1:0]        wck_a_out;

genvar              ca_idx;
genvar              wck_idx;

/***************component*************/
lpddr5_test_scheduler U_SCHEDULER (
    .clk                            (clk_200m                      ),
    .rst_n_in                       (rst_n                         ),
    .channel_ck_a_run_en            (channel_ck_a_run_en           ),
    .channel_reset_n_a              (channel_reset_n_a             ),
    .channel_cs_a_0_rise            (channel_cs_a_0_rise           ),
    .channel_cs_a_0_fall            (channel_cs_a_0_fall           ),
    .channel_ca_a_rise              (channel_ca_a_rise             ),
    .channel_ca_a_fall              (channel_ca_a_fall             ),
    .channel_wck_a_run_en           (channel_wck_a_run_en          ),
    .channel_wck_a_phase            (channel_wck_a_phase           ),
    .channel_dq_a_tx_word           (channel_dq_a_tx_word          ),
    .channel_dmi_a_tx_word          (channel_dmi_a_tx_word         ),
    .channel_rdqs_t_a_in_dh         (channel_rdqs_t_a_in_dh        ),
    .channel_rdqs_t_a_in_dl         (channel_rdqs_t_a_in_dl        ),
    .channel_dq_oe                  (channel_dq_oe                 ),
    .channel_rdqs_oe                (channel_rdqs_oe               ),
    .channel_rx_dq_capture_en       (channel_rx_dq_capture_en      ),
    .dq_a_word_flat                 (dq_a_word_flat                ),
    .dq_a_word_valid                (dq_a_word_valid               ),
    .dq_a_burst_flat                (dq_a_burst_flat               ),
    .dq_a_burst_valid               (dq_a_burst_valid              ),
    .init_en                        (init_en                       ),
    .init_done                      (init_done                     ),
    .init_fail                      (init_fail                     ),
    .mrw_r                          (24'd0                         ),
    .idd_en                         (10'd0                         ),
    .idd_done                       (                              ),
    .rdc_err_bitmap                 (rdc_err_bitmap                ),
    .rdc_check_valid                (rdc_check_valid               ),
    .rdc_check_pass                 (rdc_check_pass                ),
    .rdc_train_init_en              (1'b1                          ),
    .rdc_train_apply_best_cfg       (1'b1                          ),
    .rdc_train_dual_pattern_cfg     (1'b1                          ),
    .rdc_train_dq_start_cfg         (4'd0                          ),
    .rdc_train_dq_end_cfg           (4'd15                         ),
    .rdc_train_tap_start_cfg        (9'd0                          ),
    .rdc_train_tap_stop_cfg         (9'd3                          ),
    .rdc_train_tap_step_cfg         (9'd1                          ),
    .rdc_train_dq_delay_l_we        (1'b0                          ),
    .rdc_train_dq_delay_h_we        (1'b0                          ),
    .rdc_train_dq_delay_wdat        (96'd0                         ),
    .rdc_train_scan_tap_sel         (rdc_train_tap                 ),
    .rdc_dq_delay_flat              (rdc_dq_delay_flat             ),
    .rdc_train_state                (rdc_train_state               ),
    .rdc_train_busy                 (rdc_train_busy                ),
    .rdc_train_done                 (rdc_train_done                ),
    .rdc_train_apply_best           (rdc_train_apply_best          ),
    .rdc_train_dq_start             (rdc_train_dq_start            ),
    .rdc_train_tap                  (rdc_train_tap                 ),
    .rdc_train_status_best_len      (rdc_train_status_best_len     ),
    .rdc_train_pass_mask            (rdc_train_pass_mask           ),
    .rdc_train_fail_mask            (rdc_train_fail_mask           ),
    .rdc_train_last_err_bitmap      (rdc_train_last_err_bitmap     ),
    .rdc_train_init_ready           (rdc_train_init_ready          ),
    .rdc_train_pass_all             (rdc_train_pass_all            ),
    .rdc_train_best_flat            (rdc_train_best_flat           ),
    .rdc_train_left_flat            (rdc_train_left_flat           ),
    .rdc_train_right_flat           (rdc_train_right_flat          ),
    .rdc_train_scan_pass_bitmap     (rdc_train_scan_pass_bitmap    ),
    .read_capture_start_cnt         (8'd17                         ),
    .gf_capture_start_cnt           (8'd17                         ),
    .init_beat_offset               (4'd1                          ),
    .gf_beat_offset                 (4'd1                          ),
    .rx_burst_beat_offset           (rx_burst_beat_offset          ),
    .gf_rd_wck_start_cnt            (10'd5                         ),
    .gf_rd_wck_last_cnt             (10'd20                        ),
    .gf_wr_wck_start_cnt            (10'd5                         ),
    .gf_wr_wck_last_cnt             (10'd18                        ),
    .gf_read_done_cnt               (10'd18                        ),
    .gf_write_done_cnt              (10'd18                        ),
    .gf_act_cmd_gap_cnt             (10'd6                         ),
    .gf_rd_cmd_gap_cnt              (10'd11                        ),
    .gf_wr_cmd_gap_cnt              (10'd11                        ),
    .gf_pre_cmd_gap_cnt             (10'd7                         ),
    .gf_refresh_batch_num           (3'd1                          ),
    .gf_pattern_mode_cfg            (2'd0                          ),
    .die_message                    (die_message                   ),
    .gf_start_col                   (6'd0                          ),
    .gf_end_col                     (6'd0                          ),
    .gf_start_row                   (18'd0                         ),
    .gf_end_row                     (18'd0                         ),
    .gf_start_bg                    (2'd0                          ),
    .gf_end_bg                      (2'd0                          ),
    .gf_start_ba                    (2'd0                          ),
    .gf_end_ba                      (2'd0                          ),
    .gf_error_count                 (                              ),
    .err_block_cnt                  (                              ),
    .err_block_message              (                              ),
    .gf_total_start                 (1'b0                          ),
    .gf_inner_start                 (1'b0                          ),
    .gf_inner_done                  (                              ),
    .gf_op_mode                     (2'd0                          ),
    .gf_read_data_sel               (1'b0                          ),
    .gf_write_data_sel              (1'b0                          ),
    .gf_march_y_mode                (1'b0                          ),
    .gf_fail_aux_result             (                              ),
    .dbg_ascii_stc                  (dbg_ascii_stc                 ),
    .dbg_init_busy                  (dbg_init_busy                 ),
    .dbg_gf_inner_en                (                              ),
    .dbg_gf_total_start             (                              ),
    .dbg_init_done                  (                              ),
    .dbg_gf_inner_done              (                              ),
    .dbg_gf_en_read                 (                              ),
    .dbg_gf_en_write                (                              ),
    .dbg_chn_state                  (dbg_chn_state                 ),
    .dbg_init_mr_cnt                (dbg_init_mr_cnt               ),
    .dbg_gf_addr                    (                              ),
    .dbg_gf_cnt_read                (                              ),
    .dbg_gf_cnt_write               (                              ),
    .dbg_gf_state                   (                              ),
    .dbg_gf_op_mode                 (                              ),
    .dbg_gf_read_data_sel           (                              ),
    .dbg_gf_write_data_sel          (                              ),
    .dbg_gf_march_y_mode            (                              ),
    .dbg_gf_read_expected_beat      (                              ),
    .dbg_gf_compare_window          (                              ),
    .dbg_gf_compare_mismatch_odd    (                              ),
    .dbg_gf_compare_mismatch_even   (                              ),
    .dbg_gf_err_flag                (                              ),
    .dbg_gf_fail_now                (                              )
);

lpddr5_serdes_ddr_1bit U_RESET_SERDES (
    .clk_200m                       (clk_200m                      ),
    .clk_400m                       (clk_400m                      ),
    .rst_n                          (rst_n                         ),
    .data_rise                      (channel_reset_n_a             ),
    .data_fall                      (channel_reset_n_a             ),
    .out_q                          (reset_n_a_out                 )
);

lpddr5_serdes_ck_1bit U_CK_SERDES (
    .clk_200m                       (clk_200m                      ),
    .clk_400m                       (clk_400m                      ),
    .rst_n                          (rst_n                         ),
    .ck_run_en                      (channel_ck_a_run_en           ),
    .out_q                          (ck_a_out                      )
);

lpddr5_serdes_ddr_1bit U_CS_SERDES (
    .clk_200m                       (clk_200m                      ),
    .clk_400m                       (clk_400m                      ),
    .rst_n                          (rst_n                         ),
    .data_rise                      (channel_cs_a_0_rise           ),
    .data_fall                      (channel_cs_a_0_fall           ),
    .out_q                          (cs_a_out                      )
);

generate
    for (ca_idx = 0; ca_idx < 7; ca_idx = ca_idx + 1) begin : GEN_CA_SERDES
        lpddr5_serdes_ddr_1bit U_CA_SERDES (
            .clk_200m                   (clk_200m                      ),
            .clk_400m                   (clk_400m                      ),
            .rst_n                      (rst_n                         ),
            .data_rise                  (channel_ca_a_rise[ca_idx]      ),
            .data_fall                  (channel_ca_a_fall[ca_idx]      ),
            .out_q                      (ca_a_out[ca_idx]              )
        );
    end

    for (wck_idx = 0; wck_idx < 2; wck_idx = wck_idx + 1) begin : GEN_WCK_SERDES
        lpddr5_serdes_wck_1bit U_WCK_SERDES (
            .clk_200m                   (clk_200m                      ),
            .clk_400m                   (clk_400m                      ),
            .rst_n                      (rst_n                         ),
            .run_en                     (channel_wck_a_run_en[wck_idx]  ),
            .phase                      (channel_wck_a_phase[wck_idx]   ),
            .out_q                      (wck_a_out[wck_idx]            )
        );
    end
endgenerate

/***************assign****************/

/***************always****************/
always #2500 clk_200m = ~clk_200m;
always #1250 clk_400m = ~clk_400m;

// The DRAM model returns MR8 during base initialization and returns the exact
// pattern expected by the scheduler for each RDC capture request.
always @(posedge clk_200m or negedge rst_n) begin
    if (rst_n == 1'b0) begin
        dq_a_word_flat     <= 64'd0;
        dq_a_word_valid    <= 1'b0;
        dq_a_burst_flat    <= 256'd0;
        dq_a_burst_valid   <= 1'b0;
        r_init_word_pending <= 1'b0;
        r_rdc_burst_pending <= 1'b0;
    end
    else begin
        r_init_word_pending <=
            channel_rx_dq_capture_en && !U_SCHEDULER.init_rdc_sample_en;
        r_rdc_burst_pending <=
            channel_rx_dq_capture_en && U_SCHEDULER.init_rdc_sample_en;

        dq_a_word_valid  <= 1'b0;
        dq_a_burst_valid <= 1'b0;

        if (r_init_word_pending == 1'b1) begin
            dq_a_word_flat  <= 64'h0000_0019_0019_0019;
            dq_a_word_valid <= 1'b1;
        end
        else begin
            dq_a_word_flat <= dq_a_word_flat;
        end

        if (r_rdc_burst_pending == 1'b1) begin
            dq_a_burst_flat  <= U_SCHEDULER.rdc_expect_burst;
            dq_a_burst_valid <= 1'b1;
        end
        else begin
            dq_a_burst_flat <= dq_a_burst_flat;
        end
    end
end

always @(posedge clk_200m or negedge rst_n) begin
    if (rst_n == 1'b0) begin
        r_init_fail_seen    <= 1'b0;
        r_init_word_count   <= 0;
        r_rdc_capture_count <= 0;
        r_rdc_result_count  <= 0;
    end
    else begin
        if (init_fail == 1'b1)
            r_init_fail_seen <= 1'b1;
        else
            r_init_fail_seen <= r_init_fail_seen;

        if (dq_a_word_valid == 1'b1)
            r_init_word_count <= r_init_word_count + 1;
        else
            r_init_word_count <= r_init_word_count;

        if (r_rdc_burst_pending == 1'b1)
            r_rdc_capture_count <= r_rdc_capture_count + 1;
        else
            r_rdc_capture_count <= r_rdc_capture_count;

        if (dq_a_burst_valid == 1'b1)
            r_rdc_result_count <= r_rdc_result_count + 1;
        else
            r_rdc_result_count <= r_rdc_result_count;
    end
end

initial begin
    clk_200m           = 1'b0;
    clk_400m           = 1'b0;
    rst_n              = 1'b0;
    init_en            = 1'b0;
    dq_a_word_flat     = 64'd0;
    dq_a_word_valid    = 1'b0;
    dq_a_burst_flat    = 256'd0;
    dq_a_burst_valid   = 1'b0;
    r_init_wait_cycles = 0;
    r_error_count      = 0;

    repeat (8) @(posedge clk_200m);
    rst_n = 1'b1;

    // Start after the Xilinx global set/reset interval so external SERDES pins
    // show the complete initialization sequence from its first command.
    repeat (20) @(posedge clk_200m);
    init_en = 1'b1;
    @(posedge clk_200m);
    init_en = 1'b0;

    while ((init_done != 1'b1) &&
           (r_init_wait_cycles < P_INIT_TIMEOUT_CYCLES)) begin
        @(posedge clk_200m);
        r_init_wait_cycles = r_init_wait_cycles + 1;
    end

    if (init_done != 1'b1) begin
        $display("SIM FAIL: INIT+RDC timeout state=%0d rdc_state=%0d tap=%0d pattern=%0d",
                 U_SCHEDULER.U_lpddr5_init.r_init_state,
                 rdc_train_state,
                 rdc_train_tap,
                 U_SCHEDULER.init_rdc_train_pattern_sel);
        r_error_count = r_error_count + 1;
    end

    repeat (16) @(posedge clk_200m);

    if (r_init_fail_seen != 1'b0) begin
        $display("SIM FAIL: init_fail was asserted");
        r_error_count = r_error_count + 1;
    end
    if (rdc_train_done != 1'b1 || rdc_train_pass_all != 1'b1) begin
        $display("SIM FAIL: RDC done/pass mismatch done=%0d pass_all=%0d",
                 rdc_train_done, rdc_train_pass_all);
        r_error_count = r_error_count + 1;
    end
    if (rdc_train_pass_mask != 16'hffff ||
        rdc_train_fail_mask != 16'h0000) begin
        $display("SIM FAIL: RDC mask pass=%04h fail=%04h",
                 rdc_train_pass_mask, rdc_train_fail_mask);
        r_error_count = r_error_count + 1;
    end
    if (die_message != 8'h19) begin
        $display("SIM FAIL: MR8 die_message=%02h expected=19", die_message);
        r_error_count = r_error_count + 1;
    end
    if (r_rdc_capture_count < 18) begin
        $display("SIM FAIL: RDC capture count=%0d expected at least 18",
                 r_rdc_capture_count);
        r_error_count = r_error_count + 1;
    end

    $display("SIM INFO: init_cycles=%0d init_words=%0d rdc_captures=%0d rdc_results=%0d",
             r_init_wait_cycles,
             r_init_word_count,
             r_rdc_capture_count,
             r_rdc_result_count);
    $display("SIM INFO: RDC tap=%0d best_len=%0d pass=%04h fail=%04h",
             rdc_train_tap,
             rdc_train_status_best_len,
             rdc_train_pass_mask,
             rdc_train_fail_mask);

    if (r_error_count == 0)
        $display("SIM PASS: complete INIT plus limited dual-pattern RDC waveform");
    else
        $display("SIM FAIL: error_count=%0d", r_error_count);

    $finish;
end

initial begin
    #1000000000;
    $display("SIM FAIL: absolute timeout");
    $finish;
end

endmodule
