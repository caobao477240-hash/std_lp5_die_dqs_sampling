`timescale 1ps / 1ps

module tb_init_gf_pinout #(
    parameter [9:0] GF_RD_GAP_TEST = 10'd12,
    parameter [1:0] GF_PATTERN_MODE = 2'd0
);

localparam integer START_CHECK_PS    = 30000;
localparam integer GF_WAIT_CYCLES    = 200000;
localparam integer INIT_WAIT_CYCLES  = 20000;
localparam integer CENTER_MIN_PS     = 575;
localparam integer CENTER_MAX_PS     = 675;
localparam integer PIN_DQ_SAMPLE_MAX = 131072;

reg         sys_clk_p = 1'b0;
reg         pll_reset = 1'b1;
wire        sys_clk_n;
wire        clk_unused_20m;
wire        clk_periph_40m;
wire        clk_core_200m;
wire        clk_dq_tx_400m;
wire        clk_ca_wck_400m;
wire        clk_dq_rx_400m;
wire        pll_locked;
wire        rst_n;
reg         init_en = 1'b0;
reg         gf_total_en = 1'b0;
reg  [23:0] mrw_r = 24'd0;
reg  [9:0]  idd_en = 10'd0;

wire        reset_n_a;
wire        ck_t_a;
wire        ck_c_a;
wire        cs0_a;
wire [6:0]  ca_a;
wire [15:0] dq_a;
wire [1:0]  wck_t_a;
wire [1:0]  wck_c_a;
wire [1:0]  rdqs_t_a;
wire [1:0]  rdqs_c_a;
wire [1:0]  dmi_a;

wire        gf_total_done;
wire [95:0] gf_result_data;
wire [95:0] gf_fail_aux_result;
wire        init_done;
wire        idd_done;
wire [7:0]  die_message;
wire [7:0]  err_block_cnt;
wire [63:0] err_block_message;
wire [15:0] rdc_err_bitmap;
wire        rdc_check_valid;
wire        rdc_check_pass;
reg         rdc_train_init_en = 1'b0;
reg         rdc_train_apply_best_cfg = 1'b0;
reg         rdc_train_dual_pattern_cfg = 1'b1;
reg  [3:0]  rdc_train_dq_start_cfg = 4'd0;
reg  [3:0]  rdc_train_dq_end_cfg = 4'd15;
reg  [8:0]  rdc_train_tap_start_cfg = 9'd0;
reg  [8:0]  rdc_train_tap_stop_cfg = 9'd300;
reg  [8:0]  rdc_train_tap_step_cfg = 9'd2;
reg         rdc_train_dq_delay_l_we = 1'b0;
reg         rdc_train_dq_delay_h_we = 1'b0;
reg  [95:0] rdc_train_dq_delay_wdat = 96'd0;
wire [3:0]  rdc_train_state;
wire        rdc_train_busy;
wire        rdc_train_done;
wire        rdc_train_apply_best;
wire [3:0]  rdc_train_dq_start;
wire [8:0]  rdc_train_tap;
wire [9:0]  rdc_train_status_best_len;
wire [15:0] rdc_train_pass_mask;
wire [15:0] rdc_train_fail_mask;
wire [15:0] rdc_train_last_err_bitmap;
wire        rdc_train_init_ready;
wire        rdc_train_pass_all;
wire [143:0] rdc_train_best_flat;
wire [143:0] rdc_train_left_flat;
wire [143:0] rdc_train_right_flat;
wire [143:0] delay_value_dq_a;

`ifdef LP5_SIM_RX_PACKER_CHECK
wire        rx_capture_pulse;
wire [63:0] rx_raw_word;
wire [255:0] rx_burst_flat;
wire        rx_burst_valid;
reg  [15:0] sim_rx_dq_word;
reg  [5:0]  rx_capture_req_pipe_ref;
reg  [63:0] rx_ref_word0;
reg  [63:0] rx_ref_word1;
reg  [63:0] rx_ref_word2;
reg  [63:0] rx_ref_word3;
reg  [63:0] rx_ref_word4;
reg  [63:0] rx_ref_word5;
reg  [255:0] rx_expected_burst;
reg          rx_expected_valid;
reg          rx_capture_seen_in_stream;
integer      rx_capture_count;
integer      rx_burst_count;
integer      rx_data_mismatch_count;
integer      rx_gap_error_count;
integer      rx_cycle_count;
integer      rx_last_capture_cycle;
`endif

`ifdef LP5_SIM_ISERDES_CAPTURE_VIEW
reg  [15:0] sim_iserdes_dq_beat = 16'h1111;
reg  [ 1:0] sim_iserdes_beat_slot = 2'd0;
integer     sim_iserdes_beat_index = 0;
`endif

assign rdqs_t_a = 2'bzz;
assign rdqs_c_a = 2'bzz;
assign dmi_a    = 2'bzz;

`ifdef LP5_SIM_RX_PACKER_CHECK
assign rx_capture_pulse = u_dut.channel_rx_dq_capture_en;
assign rx_raw_word =
    u_dut.U_lpddr5_channel.U_lpddr5_ch_a_phy_io.
    U_lpddr5_dqs_serdes_phy.dq_q_word_full;
assign rx_burst_flat  = u_dut.dq_a_burst_flat;
assign rx_burst_valid = u_dut.dq_a_burst_valid;
`endif

integer error_count;
integer init_wait;
integer gf_wait;
integer ck_edges;
integer wck_edges;
integer ck_last_ps;
integer wck_last_ps;
integer ck_period_sum_ps;
integer wck_period_sum_ps;
integer cs_high_events;
integer ca_transition_count;
integer mr18_stage;
integer mr18_seen;
integer gf_write_cmd_stage;
integer gf_write_cmd_seen;
integer gf_write_cmd_count;
integer gf_read_cmd_stage;
integer gf_read_cmd_seen;
integer gf_read_cmd_count;
integer gf_write_start_count;
integer gf_read_start_count;
integer dq_word_count;
integer dq_march0_burst_seen;
integer dq_march1_burst_seen;
integer dq_bad_word_count;
integer pin_dq_sample_count;
integer pin_dq_march0_best_matches;
integer pin_dq_march0_best_start;
integer pin_dq_march1_best_matches;
integer pin_dq_march1_best_start;
integer wck_center_edges;
integer wck_same_edge_edges;
integer wck_checked_edges;
integer dq0_edges;
integer last_dq0_edge_ps;
integer last_wck_edge_ps;
integer first_gf_write_ps;
integer first_gf_read_ps;
integer cmd_ck_edge_print_count;

reg [63:0] dq_word_now;
reg [63:0] expected_word_now;
reg [15:0] pin_dq_samples [0:PIN_DQ_SAMPLE_MAX-1];
reg        pin_dq_data_sel_samples [0:PIN_DQ_SAMPLE_MAX-1];
reg        prev_dq_oe;
reg        prev_gf_read;
reg        prev_gf_write;
reg [6:0]  cmd_last_ca;
integer    cmd_last_sample_ps;

function formal_gf_word_repeat_match;
    input [63:0] word;
    reg [15:0]   beat0;
    reg [15:0]   beat1;
    reg [15:0]   beat2;
    reg [15:0]   beat3;
    begin
        formal_gf_word_repeat_match = 1'b0;
        beat0 = word[15:0];
        beat1 = word[31:16];
        beat2 = word[47:32];
        beat3 = word[63:48];
        if ((beat0 == beat1) &&
            (beat0 == beat2) &&
            (beat0 == beat3)) begin
            formal_gf_word_repeat_match = 1'b1;
        end
    end
endfunction

function formal_gf_word_ramp_match;
    input [63:0] word;
    reg [15:0]   beat0;
    reg [15:0]   beat1;
    reg [15:0]   beat2;
    reg [15:0]   beat3;
    begin
        beat0 = word[15:0];
        beat1 = word[31:16];
        beat2 = word[47:32];
        beat3 = word[63:48];

        formal_gf_word_ramp_match =
            (beat1 == (beat0 + 16'd1)) &&
            (beat2 == (beat0 + 16'd2)) &&
            (beat3 == (beat0 + 16'd3));
    end
endfunction

function formal_gf_word_toggle_match;
    input [63:0] word;
    reg [15:0]   beat0;
    reg [15:0]   beat1;
    reg [15:0]   beat2;
    reg [15:0]   beat3;
    begin
        beat0 = word[15:0];
        beat1 = word[31:16];
        beat2 = word[47:32];
        beat3 = word[63:48];
        formal_gf_word_toggle_match =
            (beat1 == ~beat0) &&
            (beat2 ==  beat0) &&
            (beat3 == ~beat0);
    end
endfunction

wire       gf_en_write;
wire       gf_en_read;
wire       gf_dq_oe;
wire [9:0] gf_cnt_write;
wire [9:0] gf_cnt_read;
wire [63:0] gf_tx_word;
wire        gf_write_data_sel;

assign gf_en_write    = u_dut.U_lpddr5_test_scheduler.gf_engine_en_write;
assign gf_en_read     = u_dut.U_lpddr5_test_scheduler.gf_engine_en_read;
assign gf_dq_oe       = u_dut.U_lpddr5_test_scheduler.gf_wave_dq_oe;
assign gf_cnt_write   = u_dut.U_lpddr5_test_scheduler.gf_engine_cnt_write;
assign gf_cnt_read    = u_dut.U_lpddr5_test_scheduler.gf_engine_cnt_read;
assign gf_tx_word     = u_dut.U_lpddr5_test_scheduler.gf_wave_dq_a_tx_word;
assign gf_write_data_sel = u_dut.U_lpddr5_test_scheduler.gf_write_data_sel;

`ifdef LP5_SIM_ISERDES_CAPTURE_VIEW
assign dq_a = (gf_dq_oe == 1'b0) ? sim_iserdes_dq_beat : 16'hzzzz;
`elsif LP5_SIM_RX_PACKER_CHECK
assign dq_a = (gf_dq_oe == 1'b0) ? sim_rx_dq_word : 16'hzzzz;
`endif

always #2500 sys_clk_p = ~sys_clk_p;

assign sys_clk_n = ~sys_clk_p;
assign rst_n     = pll_locked;

initial begin
    repeat (8) @(posedge sys_clk_p);
    pll_reset = 1'b0;
end

`ifdef LP5_SIM_ISERDES_CAPTURE_VIEW
// Change the pin data halfway between adjacent 400M DDR sample edges. Each
// 16-bit value is one visible LPDDR beat, so four consecutive values show the
// exact ISERDES 1:4 grouping in dq_q_beat0..dq_q_beat3.
always @(posedge clk_dq_rx_400m or negedge clk_dq_rx_400m) begin
    #625;
    if (rst_n == 1'b0) begin
        sim_iserdes_beat_index = 0;
        sim_iserdes_beat_slot  = 2'd0;
        sim_iserdes_dq_beat    = 16'h1111;
    end
    else if (gf_dq_oe == 1'b0) begin
        sim_iserdes_beat_index = sim_iserdes_beat_index + 1;
        sim_iserdes_beat_slot  = sim_iserdes_beat_slot + 1'b1;
        case (sim_iserdes_beat_slot)
            2'd0: sim_iserdes_dq_beat = 16'h1111;
            2'd1: sim_iserdes_dq_beat = 16'h2222;
            2'd2: sim_iserdes_dq_beat = 16'h4444;
            2'd3: sim_iserdes_dq_beat = 16'h8888;
        endcase
    end
end
`endif

`ifdef LP5_SIM_RX_PACKER_CHECK
always @(posedge clk_core_200m or negedge rst_n) begin
    if (rst_n == 1'b0) begin
        sim_rx_dq_word               <= 16'h0101;
        rx_capture_req_pipe_ref      <= 6'b000000;
        rx_ref_word0                 <= 64'h0;
        rx_ref_word1                 <= 64'h0;
        rx_ref_word2                 <= 64'h0;
        rx_ref_word3                 <= 64'h0;
        rx_ref_word4                 <= 64'h0;
        rx_ref_word5                 <= 64'h0;
        rx_expected_burst            <= 256'h0;
        rx_expected_valid            <= 1'b0;
        rx_capture_seen_in_stream    <= 1'b0;
        rx_capture_count             <= 0;
        rx_gap_error_count           <= 0;
        rx_cycle_count               <= 0;
        rx_last_capture_cycle        <= 0;
    end
    else begin
        sim_rx_dq_word          <= sim_rx_dq_word + 16'h0101;
        rx_cycle_count          <= rx_cycle_count + 1;
        rx_capture_req_pipe_ref <= {
            rx_capture_req_pipe_ref[4:0],
            rx_capture_pulse && gf_en_read
        };
        rx_ref_word0 <= rx_ref_word1;
        rx_ref_word1 <= rx_ref_word2;
        rx_ref_word2 <= rx_ref_word3;
        rx_ref_word3 <= rx_ref_word4;
        rx_ref_word4 <= rx_ref_word5;
        rx_ref_word5 <= rx_raw_word;
        rx_expected_valid <= rx_capture_req_pipe_ref[5];

        if (rx_capture_req_pipe_ref[5] == 1'b1)
            rx_expected_burst <= {
                rx_ref_word3,
                rx_ref_word2,
                rx_ref_word1,
                rx_ref_word0
            };
        else
            rx_expected_burst <= rx_expected_burst;

        if (gf_en_read == 1'b0)
            rx_capture_seen_in_stream <= 1'b0;
        else if (rx_capture_pulse == 1'b1) begin
            rx_capture_count <= rx_capture_count + 1;
            if (rx_capture_seen_in_stream == 1'b1) begin
                if ((rx_cycle_count - rx_last_capture_cycle) !=
                    GF_RD_GAP_TEST)
                    rx_gap_error_count <= rx_gap_error_count + 1;
            end
            rx_capture_seen_in_stream <= 1'b1;
            rx_last_capture_cycle     <= rx_cycle_count;
        end
        else begin
            rx_capture_seen_in_stream <= rx_capture_seen_in_stream;
        end
    end
end

always @(negedge clk_core_200m or negedge rst_n) begin
    if (rst_n == 1'b0) begin
        rx_burst_count         <= 0;
        rx_data_mismatch_count <= 0;
    end
    else begin
        if ((rx_burst_valid == 1'b1) && (gf_en_read == 1'b1))
            rx_burst_count <= rx_burst_count + 1;
        else
            rx_burst_count <= rx_burst_count;

        if (rx_expected_valid == 1'b1) begin
            if ((rx_burst_valid != 1'b1) ||
                (rx_burst_flat !== rx_expected_burst))
                rx_data_mismatch_count <= rx_data_mismatch_count + 1;
        end
        else if ((rx_burst_valid == 1'b1) && (gf_en_read == 1'b1)) begin
            rx_data_mismatch_count <= rx_data_mismatch_count + 1;
        end
        else begin
            rx_data_mismatch_count <= rx_data_mismatch_count;
        end
    end
end
`endif

clk_wiz_0 u_clk_wiz (
    .clk_out1  (clk_unused_20m),
    .clk_out2  (clk_periph_40m),
    .clk_out3  (clk_core_200m),
    .clk_out4  (clk_dq_tx_400m),
    .clk_out5  (clk_ca_wck_400m),
    .clk_out6  (clk_dq_rx_400m),
    .reset     (pll_reset),
    .locked    (pll_locked),
    .clk_in1_p (sys_clk_p),
    .clk_in1_n (sys_clk_n)
);

lpddr5_dut1 u_dut (
    .i_clk_core_200m     (clk_core_200m),
    .i_clk_dq_tx_400m    (clk_dq_tx_400m),
    .i_clk_ca_wck_400m   (clk_ca_wck_400m),
    .i_clk_dq_rx_400m    (clk_dq_rx_400m),
    .i_serdes_reset_n    (rst_n),
    .rst_n_in            (rst_n),
    .GF_total_en         (gf_total_en),
    .GF_total_done       (gf_total_done),
    .GF_result_data      (gf_result_data),
    .GF_fail_aux_result  (gf_fail_aux_result),
    .reset_n_a           (reset_n_a),
    .ck_t_a              (ck_t_a),
    .ck_c_a              (ck_c_a),
    .cs0_a               (cs0_a),
    .ca_a                (ca_a),
    .dq_a                (dq_a),
    .wck_t_a             (wck_t_a),
    .wck_c_a             (wck_c_a),
    .rdqs_t_a            (rdqs_t_a),
    .rdqs_c_a            (rdqs_c_a),
    .dmi_a               (dmi_a),
    .init_en             (init_en),
    .init_done           (init_done),
    .mrw_r               (mrw_r),
    .idd_en              (idd_en),
    .idd_done            (idd_done),
    .read_capture_start_cnt (8'h11),
    .gf_capture_start_cnt   (8'h11),
    .init_beat_offset       (4'd0),
    .gf_beat_offset         (4'd0),
    .gf_rd_wck_start_cnt    (10'd5),
    .gf_rd_wck_last_cnt     (10'd25),
    .gf_wr_wck_start_cnt    (10'd5),
    .gf_wr_wck_last_cnt     (10'd18),
    .gf_read_done_cnt       (10'd27),
    .gf_write_done_cnt      (10'd25),
    .gf_act_cmd_gap_cnt     (10'd16),
    .gf_rd_cmd_gap_cnt      (GF_RD_GAP_TEST),
    .gf_wr_cmd_gap_cnt      (10'd10),
    .gf_pre_cmd_gap_cnt     (10'd16),
    .gf_refresh_batch_num   (3'd4),
    .gf_pattern_mode_cfg    (GF_PATTERN_MODE),
    .die_message         (die_message),
    .err_block_cnt       (err_block_cnt),
    .err_block_message   (err_block_message),
    .rdc_err_bitmap      (rdc_err_bitmap),
    .rdc_check_valid     (rdc_check_valid),
    .rdc_check_pass      (rdc_check_pass),
    .rdc_train_init_en   (rdc_train_init_en),
    .rdc_train_apply_best_cfg (rdc_train_apply_best_cfg),
    .rdc_train_dual_pattern_cfg (rdc_train_dual_pattern_cfg),
    .rdc_train_dq_start_cfg (rdc_train_dq_start_cfg),
    .rdc_train_dq_end_cfg (rdc_train_dq_end_cfg),
    .rdc_train_tap_start_cfg (rdc_train_tap_start_cfg),
    .rdc_train_tap_stop_cfg (rdc_train_tap_stop_cfg),
    .rdc_train_tap_step_cfg (rdc_train_tap_step_cfg),
    .rdc_train_dq_delay_l_we (rdc_train_dq_delay_l_we),
    .rdc_train_dq_delay_h_we (rdc_train_dq_delay_h_we),
    .rdc_train_dq_delay_wdat (rdc_train_dq_delay_wdat),
    .rdc_train_scan_tap_sel  (9'd0),
    .rdc_train_state     (rdc_train_state),
    .rdc_train_busy      (rdc_train_busy),
    .rdc_train_done      (rdc_train_done),
    .rdc_train_apply_best (rdc_train_apply_best),
    .rdc_train_dq_start  (rdc_train_dq_start),
    .rdc_train_tap       (rdc_train_tap),
    .rdc_train_status_best_len (rdc_train_status_best_len),
    .rdc_train_pass_mask (rdc_train_pass_mask),
    .rdc_train_fail_mask (rdc_train_fail_mask),
    .rdc_train_last_err_bitmap (rdc_train_last_err_bitmap),
    .rdc_train_init_ready (rdc_train_init_ready),
    .rdc_train_pass_all  (rdc_train_pass_all),
    .rdc_train_best_flat (rdc_train_best_flat),
    .rdc_train_left_flat (rdc_train_left_flat),
    .rdc_train_right_flat (rdc_train_right_flat),
    .rdc_train_scan_pass_bitmap(),
    .RDY                 (1'b1),
    .delay_value_dq_a    (delay_value_dq_a)
);

initial begin
    error_count          = 0;
    init_wait            = 0;
    gf_wait              = 0;
    ck_edges             = 0;
    wck_edges            = 0;
    ck_last_ps           = 0;
    wck_last_ps          = 0;
    ck_period_sum_ps     = 0;
    wck_period_sum_ps    = 0;
    cs_high_events       = 0;
    ca_transition_count  = 0;
    mr18_stage           = 0;
    mr18_seen            = 0;
    gf_write_cmd_stage   = 0;
    gf_write_cmd_seen    = 0;
    gf_write_cmd_count   = 0;
    gf_read_cmd_stage    = 0;
    gf_read_cmd_seen     = 0;
    gf_read_cmd_count    = 0;
    gf_write_start_count = 0;
    gf_read_start_count  = 0;
    dq_word_count        = 0;
    dq_march0_burst_seen = 0;
    dq_march1_burst_seen = 0;
    dq_bad_word_count    = 0;
    pin_dq_sample_count  = 0;
    pin_dq_march0_best_matches = 0;
    pin_dq_march0_best_start   = 0;
    pin_dq_march1_best_matches = 0;
    pin_dq_march1_best_start   = 0;
    wck_center_edges     = 0;
    wck_same_edge_edges  = 0;
    wck_checked_edges    = 0;
    dq0_edges            = 0;
    last_dq0_edge_ps     = 0;
    last_wck_edge_ps     = 0;
    first_gf_write_ps    = 0;
    first_gf_read_ps     = 0;
    cmd_ck_edge_print_count = 0;
    prev_dq_oe           = 1'b0;
    prev_gf_read         = 1'b0;
    prev_gf_write        = 1'b0;
    cmd_last_ca          = 7'h7f;
    cmd_last_sample_ps   = 0;

    wait (pll_locked == 1'b1);
    repeat (8) @(posedge clk_core_200m);

    rdc_train_dq_delay_wdat = {24'd0, {8{9'h100}}};
    rdc_train_dq_delay_l_we = 1'b1;
    @(posedge clk_core_200m);
    rdc_train_dq_delay_l_we = 1'b0;
    rdc_train_dq_delay_h_we = 1'b1;
    @(posedge clk_core_200m);
    rdc_train_dq_delay_h_we = 1'b0;

    repeat (4) @(posedge clk_core_200m);

    init_en = 1'b1;

    while (!init_done && init_wait < INIT_WAIT_CYCLES) begin
        @(posedge clk_core_200m);
        init_wait = init_wait + 1;
    end

    if (!init_done) begin
        $display("SIM FAIL: init_done timeout, init_state=%0d init_mr_cnt=%0d",
                 u_dut.U_lpddr5_test_scheduler.init_state,
                 u_dut.U_lpddr5_test_scheduler.init_mr_cnt);
        error_count = error_count + 1;
    end

    repeat (16) @(posedge clk_core_200m);
    gf_total_en = 1'b1;

    while (!gf_total_done && gf_wait < GF_WAIT_CYCLES) begin
        @(posedge clk_core_200m);
        gf_wait = gf_wait + 1;
    end

    if (!gf_total_done) begin
        $display("SIM FAIL: GF did not complete within pinout timeout, state=%h cntW=%0d cntR=%0d",
                 u_dut.U_lpddr5_test_scheduler.gf_engine_state,
                 gf_cnt_write,
                 gf_cnt_read);
        error_count = error_count + 1;
    end

    repeat (8) @(posedge clk_core_200m);

`ifdef LP5_SIM_RX_PACKER_CHECK
    if (rx_capture_count < 16) begin
        $display("SIM FAIL: RX capture count too small: %0d", rx_capture_count);
        error_count = error_count + 1;
    end
    if (rx_burst_count != rx_capture_count) begin
        $display("SIM FAIL: RX capture/burst count mismatch capture=%0d burst=%0d",
                 rx_capture_count, rx_burst_count);
        error_count = error_count + 1;
    end
    if (rx_data_mismatch_count != 0) begin
        $display("SIM FAIL: RX sliding-window mismatches=%0d",
                 rx_data_mismatch_count);
        error_count = error_count + 1;
    end
    if (rx_gap_error_count != 0) begin
        $display("SIM FAIL: RX capture gap errors=%0d expected_gap=%0d",
                 rx_gap_error_count, GF_RD_GAP_TEST);
        error_count = error_count + 1;
    end
`endif

    if (!mr18_seen) begin
        $display("SIM FAIL: MR18 2:1 sequence 58-12-48-03 not observed on serialized CS/CA");
        error_count = error_count + 1;
    end
    score_pin_dq_samples();

    if (!gf_write_cmd_seen || gf_write_cmd_count < 2) begin
        $display("SIM FAIL: expected two GF WRITE command sequences, seen=%0d", gf_write_cmd_count);
        error_count = error_count + 1;
    end
    if (!gf_read_cmd_seen || gf_read_cmd_count < 2) begin
        $display("SIM FAIL: expected two GF READ command sequences, seen=%0d", gf_read_cmd_count);
        error_count = error_count + 1;
    end
    if (gf_write_start_count < 2 || gf_read_start_count < 2) begin
        $display("SIM FAIL: expected two GF write/read engine starts, write=%0d read=%0d",
                 gf_write_start_count, gf_read_start_count);
        error_count = error_count + 1;
    end
    if (!dq_march0_burst_seen) begin
        $display("SIM FAIL: GF DQ March-0 TX burst not observed at PHY boundary");
        error_count = error_count + 1;
    end
    if (!dq_march1_burst_seen) begin
        $display("SIM FAIL: GF DQ March-1 TX burst not observed at PHY boundary");
        error_count = error_count + 1;
    end
    if (pin_dq_march0_best_matches < 16) begin
        $display("SIM FAIL: external DQ pins do not contain clean March-0 window, samples=%0d best=%0d start=%0d",
                 pin_dq_sample_count, pin_dq_march0_best_matches,
                 pin_dq_march0_best_start);
        error_count = error_count + 1;
    end
    if (pin_dq_march1_best_matches < 16) begin
        $display("SIM FAIL: external DQ pins do not contain clean March-1 window, samples=%0d best=%0d start=%0d",
                 pin_dq_sample_count, pin_dq_march1_best_matches,
                 pin_dq_march1_best_start);
        error_count = error_count + 1;
    end
    if (dq_bad_word_count != 0) begin
        $display("SIM FAIL: bad GF DQ TX words=%0d", dq_bad_word_count);
        error_count = error_count + 1;
    end
    if (wck_center_edges < 8) begin
        $display("SIM FAIL: WCK center edges too few: center=%0d checked=%0d same=%0d",
                 wck_center_edges, wck_checked_edges, wck_same_edge_edges);
        error_count = error_count + 1;
    end
    if (ck_edges < 20 || wck_edges < 20) begin
        $display("SIM FAIL: clock activity too low, ck_edges=%0d wck_edges=%0d",
                 ck_edges, wck_edges);
        error_count = error_count + 1;
    end

    $display("SUMMARY init_done=%0d init_wait_cycles=%0d die_message=%02h", init_done, init_wait, die_message);
    $display("SUMMARY gf_done=%0d gf_wait_cycles=%0d gf_result=%024h", gf_total_done, gf_wait, gf_result_data);
    $display("SUMMARY CK edges=%0d avg_edge_delta_ps=%0d", ck_edges,
             (ck_edges > 1) ? (ck_period_sum_ps / (ck_edges - 1)) : 0);
    $display("SUMMARY WCK edges=%0d avg_edge_delta_ps=%0d", wck_edges,
             (wck_edges > 1) ? (wck_period_sum_ps / (wck_edges - 1)) : 0);
    $display("SUMMARY MR18_seen=%0d GF_WRITE_seen=%0d count=%0d GF_READ_seen=%0d count=%0d CS_events=%0d CA_transitions=%0d",
             mr18_seen, gf_write_cmd_seen, gf_write_cmd_count,
             gf_read_cmd_seen, gf_read_cmd_count, cs_high_events, ca_transition_count);
    $display("SUMMARY GF engine starts write=%0d read=%0d", gf_write_start_count, gf_read_start_count);
    $display("SUMMARY DQ_words=%0d march0_seen=%0d march1_seen=%0d bad_words=%0d",
             dq_word_count, dq_march0_burst_seen, dq_march1_burst_seen, dq_bad_word_count);
    $display("SUMMARY PIN_DQ samples=%0d march0_best=%0d march0_start=%0d march1_best=%0d march1_start=%0d",
             pin_dq_sample_count, pin_dq_march0_best_matches,
             pin_dq_march0_best_start, pin_dq_march1_best_matches,
             pin_dq_march1_best_start);
    $display("SUMMARY WCK_DQ center_625ps=%0d same_edge=%0d checked=%0d dq0_edges=%0d",
             wck_center_edges, wck_same_edge_edges, wck_checked_edges, dq0_edges);
`ifdef LP5_SIM_RX_PACKER_CHECK
    $display("SUMMARY RX_PACKER gap=%0d capture=%0d burst=%0d mismatch=%0d gap_error=%0d",
             GF_RD_GAP_TEST, rx_capture_count, rx_burst_count,
             rx_data_mismatch_count, rx_gap_error_count);
`endif

    if (error_count == 0)
        $display("SIM PASS: init-to-GF pinout command/clock/write-data checks passed");
    else
        $display("SIM FAIL: error_count=%0d", error_count);

    $finish;
end

task score_pin_dq_samples;
    integer start_idx;
    integer idx;
    integer fwd_match_count;
    integer rev_match_count;
    reg [15:0] expected_fwd;
    reg [15:0] expected_rev;
    begin
        pin_dq_march0_best_matches = 0;
        pin_dq_march0_best_start   = 0;
        pin_dq_march1_best_matches = 0;
        pin_dq_march1_best_start   = 0;
        if (pin_dq_sample_count >= 16) begin
            for (start_idx = 0; start_idx <= (pin_dq_sample_count - 16); start_idx = start_idx + 1) begin
                fwd_match_count = 0;
                rev_match_count = 0;
                for (idx = 0; idx < 16; idx = idx + 1) begin
                    expected_fwd = (idx[0] == 1'b1) ?
                                   ~pin_dq_samples[start_idx] :
                                    pin_dq_samples[start_idx];
                    expected_rev = (idx[0] == 1'b1) ?
                                   ~pin_dq_samples[start_idx] :
                                    pin_dq_samples[start_idx];
                    if ((pin_dq_data_sel_samples[start_idx] == 1'b0) &&
                        (pin_dq_data_sel_samples[start_idx + idx] == 1'b0) &&
                        (pin_dq_samples[start_idx + idx] === expected_fwd))
                        fwd_match_count = fwd_match_count + 1;
                    if ((pin_dq_data_sel_samples[start_idx] == 1'b1) &&
                        (pin_dq_data_sel_samples[start_idx + idx] == 1'b1) &&
                        (pin_dq_samples[start_idx + idx] === expected_rev))
                        rev_match_count = rev_match_count + 1;
                end
                if (fwd_match_count > pin_dq_march0_best_matches) begin
                    pin_dq_march0_best_matches = fwd_match_count;
                    pin_dq_march0_best_start   = start_idx;
                end
                if (rev_match_count > pin_dq_march1_best_matches) begin
                    pin_dq_march1_best_matches = rev_match_count;
                    pin_dq_march1_best_start   = start_idx;
                end
            end
        end
    end
endtask

always @(ck_t_a) begin
    if (rst_n && $time > START_CHECK_PS && ck_t_a !== 1'bx) begin
        if (ck_last_ps != 0)
            ck_period_sum_ps = ck_period_sum_ps + ($time - ck_last_ps);
        ck_last_ps = $time;
        ck_edges = ck_edges + 1;
    end
end

always @(wck_t_a[0]) begin
    integer delta_ps;
    if (rst_n && $time > START_CHECK_PS && wck_t_a[0] !== 1'bx) begin
        if (wck_last_ps != 0)
            wck_period_sum_ps = wck_period_sum_ps + ($time - wck_last_ps);
        wck_last_ps = $time;
        wck_edges = wck_edges + 1;

        if (gf_dq_oe && last_dq0_edge_ps != 0) begin
            delta_ps = $time - last_dq0_edge_ps;
            wck_checked_edges = wck_checked_edges + 1;
            if (delta_ps == 0)
                wck_same_edge_edges = wck_same_edge_edges + 1;
            if (delta_ps >= CENTER_MIN_PS && delta_ps <= CENTER_MAX_PS)
                wck_center_edges = wck_center_edges + 1;
        end

        if (gf_dq_oe && pin_dq_sample_count < PIN_DQ_SAMPLE_MAX &&
            ^dq_a !== 1'bx && dq_a !== 16'hzzzz) begin
            pin_dq_samples[pin_dq_sample_count] = dq_a;
            pin_dq_data_sel_samples[pin_dq_sample_count] = gf_write_data_sel;
            if (pin_dq_sample_count < 24)
                $display("PIN_DQ_SAMPLE t=%0t idx=%0d dq=%04h",
                         $time, pin_dq_sample_count, dq_a);
            pin_dq_sample_count = pin_dq_sample_count + 1;
        end
    end
end

always @(dq_a[0]) begin
    if (rst_n && gf_dq_oe && $time > START_CHECK_PS && dq_a[0] !== 1'bx) begin
        last_dq0_edge_ps = $time;
        dq0_edges = dq0_edges + 1;
    end
end

always @(posedge clk_core_200m) begin
    prev_gf_write <= gf_en_write;
    prev_gf_read  <= gf_en_read;
    prev_dq_oe    <= gf_dq_oe;

    if (gf_en_write && !prev_gf_write) begin
        first_gf_write_ps = $time;
        gf_write_start_count = gf_write_start_count + 1;
        $display("GF_WRITE_START t=%0t cntW=%0d", $time, gf_cnt_write);
    end

    if (gf_en_read && !prev_gf_read) begin
        first_gf_read_ps = $time;
        gf_read_start_count = gf_read_start_count + 1;
        $display("GF_READ_START t=%0t cntR=%0d", $time, gf_cnt_read);
    end

    if (gf_dq_oe && gf_tx_word !== 64'h0) begin
        dq_word_now = gf_tx_word;
        dq_word_count = dq_word_count + 1;

        if (formal_gf_word_repeat_match(gf_tx_word) ||
            formal_gf_word_toggle_match(gf_tx_word) ||
            formal_gf_word_ramp_match(gf_tx_word)) begin
            if (gf_write_data_sel == 1'b0)
                dq_march0_burst_seen = 1;
            else
                dq_march1_burst_seen = 1;

            if (dq_word_count <= 16)
                $display("GF_DQ_ADDR_WORD t=%0t cntW=%0d sel=%0d word=%016h",
                         $time, gf_cnt_write, gf_write_data_sel, gf_tx_word);
        end
        else begin
            dq_bad_word_count = dq_bad_word_count + 1;
            if (dq_bad_word_count <= 4)
                $display("BAD_GF_DQ_WORD t=%0t cntW=%0d word=%016h",
                         $time, gf_cnt_write, gf_tx_word);
        end
    end
end

always @(ck_t_a) begin
    #20;
    if (rst_n && cs0_a === 1'b1 && ^ca_a !== 1'bx &&
        cmd_ck_edge_print_count < 96 &&
        (((first_gf_write_ps != 0) &&
          ($time >= first_gf_write_ps - 10000) &&
          ($time <= first_gf_write_ps + 80000)) ||
         ((first_gf_read_ps != 0) &&
          ($time >= first_gf_read_ps - 10000) &&
          ($time <= first_gf_read_ps + 80000)))) begin
        $display("CK_CA_EDGE t=%0t ck=%b cs=%b ca=%02h cntW=%0d cntR=%0d gfW=%b gfR=%b",
                 $time, ck_t_a, cs0_a, ca_a, gf_cnt_write, gf_cnt_read,
                 gf_en_write, gf_en_read);
        cmd_ck_edge_print_count = cmd_ck_edge_print_count + 1;
    end
end

always @(ca_a or cs0_a) begin
    #300;
    if (rst_n && cs0_a === 1'b1 && ^ca_a !== 1'bx) begin
        if (!(ca_a == cmd_last_ca && ($time - cmd_last_sample_ps) < 1000)) begin
            cmd_last_ca = ca_a;
            cmd_last_sample_ps = $time;
            cs_high_events = cs_high_events + 1;
            case (mr18_stage)
                0: begin
                    if (ca_a == 7'h58)
                        mr18_stage = 1;
                end
                1: begin
                    if (ca_a == 7'h12)
                        mr18_stage = 2;
                    else if (ca_a != 7'h58)
                        mr18_stage = 0;
                end
                2: begin
                    if (ca_a == 7'h48)
                        mr18_stage = 3;
                    else
                        mr18_stage = 0;
                end
                3: begin
                    if (ca_a == 7'h03) begin
                        mr18_seen = 1;
                        $display("MR18_CKR2_EXT t=%0t sequence=58_12_48_03", $time);
                    end
                    mr18_stage = 0;
                end
            endcase

            case (gf_write_cmd_stage)
                0: if (ca_a == 7'b0011100) gf_write_cmd_stage = 1;
                1: if (ca_a == 7'b0000000) gf_write_cmd_stage = 2; else gf_write_cmd_stage = 0;
                2: if (ca_a[2:0] == 3'b110) gf_write_cmd_stage = 3; else gf_write_cmd_stage = 0;
                3: begin
                    gf_write_cmd_seen = 1;
                    gf_write_cmd_count = gf_write_cmd_count + 1;
                    $display("GF_WRITE_CMD_EXT t=%0t ca=%02h", $time, ca_a);
                    gf_write_cmd_stage = 0;
                end
            endcase

            case (gf_read_cmd_stage)
                0: if (ca_a == 7'b0101100) gf_read_cmd_stage = 1;
                1: if (ca_a == 7'b0000000) gf_read_cmd_stage = 2; else gf_read_cmd_stage = 0;
                2: if (ca_a[2:0] == 3'b001) gf_read_cmd_stage = 3; else gf_read_cmd_stage = 0;
                3: begin
                    gf_read_cmd_seen = 1;
                    gf_read_cmd_count = gf_read_cmd_count + 1;
                    $display("GF_READ_CMD_EXT t=%0t ca=%02h", $time, ca_a);
                    gf_read_cmd_stage = 0;
                end
            endcase
        end
    end
end

always @(ca_a) begin
    if (rst_n && $time > START_CHECK_PS && ^ca_a !== 1'bx)
        ca_transition_count = ca_transition_count + 1;
end

`ifdef LP5_CMD_TRACE
always @(ca_a or cs0_a) begin
    #1;
    if (rst_n && cs0_a === 1'b1 && ^ca_a !== 1'bx)
        $display("CMD_TRACE t=%0t cs0=%b ck=%b ca=%02h stage_mr18=%0d wr=%0d rd=%0d",
                 $time, cs0_a, ck_t_a, ca_a, mr18_stage,
                 gf_write_cmd_stage, gf_read_cmd_stage);
end
`endif

endmodule
