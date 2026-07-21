`timescale 1ps / 1ps

// =========================================================================
// LPDDR5 INIT + short RDC waveform testbench
// =========================================================================
// Only the board reference clock, board reset, and INIT request are generated
// by the testbench. All 200/400 MHz clocks, their phase relationship, PHY
// startup reset sequence, command waveforms, and physical pins come from the
// production clock/LPDDR5 RTL and Xilinx primitive simulation models.
module tb_init_pll_phy_wave #(
    parameter integer P_DRAM_RDC_START_BEAT  = 10,
    parameter integer P_INIT_TIMEOUT_CYCLES  = 200000
);

/***************parameter*************/
localparam [  7:0] P_MR8_DENSITY         = 8'h19;
localparam [ 15:0] P_MR8_PIN_WORD        = 16'h1919;

/***************reg*******************/
reg                 r_sys_clk_p;
reg                 r_sys_reset;
reg                 r_init_en;

reg  [ 15:0]        r_dram_dq_word;
reg                 r_dram_dq_oe;
reg                 r_dram_wck_active;
integer             r_dram_beat_index;

reg                 r_init_fail_seen;
integer             r_init_wait_cycles;
integer             r_capture_count;
integer             r_rdc_result_count;
integer             r_ck_edge_count;
integer             r_wck_edge_count;
integer             r_burst_count;
integer             r_error_count;

/***************wire******************/
wire                w_sys_clk_n;
wire                w_clk_periph_40m;
wire                w_clk_core_200m;
wire                w_clk_dq_tx_400m;
wire                w_clk_ca_wck_400m;
wire                w_clk_dq_rx_400m;
wire                w_core_reset_n;
wire                w_serdes_reset_n;
wire                w_idelayctrl_reset;
wire                w_phy_ready;
wire                w_mmcm_locked;
wire                w_idelayctrl_ready;

wire                w_reset_n_a;
wire                w_ck_t_a;
wire                w_ck_c_a;
wire                w_cs0_a;
wire [  6:0]        w_ca_a;
wire [ 15:0]        w_dq_a;
wire [  1:0]        w_wck_t_a;
wire [  1:0]        w_wck_c_a;
wire [  1:0]        w_rdqs_t_a;
wire [  1:0]        w_rdqs_c_a;
wire [  1:0]        w_dmi_a;

wire                w_init_done;
wire                w_init_fail;
wire [  7:0]        w_die_message;
wire [ 15:0]        w_rdc_err_bitmap;
wire                w_rdc_check_valid;
wire                w_rdc_check_pass;
wire [  3:0]        w_rdc_train_state;
wire                w_rdc_train_busy;
wire                w_rdc_train_done;
wire                w_rdc_train_apply_best;
wire [  3:0]        w_rdc_train_dq_start;
wire [  8:0]        w_rdc_train_tap;
wire [  9:0]        w_rdc_train_status_best_len;
wire [ 15:0]        w_rdc_train_pass_mask;
wire [ 15:0]        w_rdc_train_fail_mask;
wire [ 15:0]        w_rdc_train_last_err_bitmap;
wire                w_rdc_train_init_ready;
wire                w_rdc_train_pass_all;
wire [143:0]        w_rdc_train_best_flat;
wire [143:0]        w_rdc_train_left_flat;
wire [143:0]        w_rdc_train_right_flat;
wire [ 15:0]        w_rdc_train_scan_pass_bitmap;
wire [143:0]        w_delay_value_dq_a;

wire [  1:0]        w_channel_wck_a_run_en;
wire                w_init_rdc_read_active;
wire                w_init_rdc_pattern_sel;

/***************function**************/
function [15:0] f_rdc_pin_beat;
    input               pattern_sel;
    input [  3:0]       beat_index;
    reg   [ 15:0]       pattern_bits;
    begin
        // MR33 is sent first, followed by MR34; each byte is read LSB first.
        pattern_bits = (pattern_sel == 1'b1) ? 16'hc33c : 16'ha55a;
        f_rdc_pin_beat = (pattern_bits[beat_index] == 1'b1) ?
                         16'haaaa : 16'h5555;
    end
endfunction

/***************component*************/
clock_manage_top U_CLOCK_MANAGE_TOP (
    .i_sys_clk_p                (r_sys_clk_p          ),
    .i_sys_clk_n                (w_sys_clk_n          ),
    .i_reset                    (r_sys_reset          ),
    .i_idelayctrl_ready         (w_idelayctrl_ready   ),
    .o_clk_periph_40m           (w_clk_periph_40m     ),
    .o_clk_core_200m            (w_clk_core_200m      ),
    .o_core_reset_n             (w_core_reset_n       ),
    .o_clk_lp5_dq_tx_400m       (w_clk_dq_tx_400m     ),
    .o_clk_lp5_ca_wck_400m      (w_clk_ca_wck_400m    ),
    .o_clk_lp5_dq_rx_400m       (w_clk_dq_rx_400m     ),
    .o_lp5_serdes_reset_n       (w_serdes_reset_n     ),
    .o_lp5_idelayctrl_reset     (w_idelayctrl_reset   ),
    .o_lp5_phy_ready            (w_phy_ready          ),
    .o_mmcm_locked              (w_mmcm_locked        )
);

IDELAYCTRL #(
    .SIM_DEVICE                 ("ULTRASCALE"         )
) U_IDELAYCTRL (
    .RDY                        (w_idelayctrl_ready    ),
    .REFCLK                     (w_clk_core_200m       ),
    .RST                        (w_idelayctrl_reset    )
);

lpddr5_dut1 U_DUT (
    .i_clk_core_200m            (w_clk_core_200m      ),
    .i_clk_dq_tx_400m           (w_clk_dq_tx_400m     ),
    .i_clk_ca_wck_400m          (w_clk_ca_wck_400m    ),
    .i_clk_dq_rx_400m           (w_clk_dq_rx_400m     ),
    .i_serdes_reset_n           (w_serdes_reset_n     ),
    .rst_n_in                   (w_phy_ready          ),

    .GF_total_en                (1'b0                 ),
    .GF_total_done              (                     ),
    .GF_result_data             (                     ),
    .GF_fail_aux_result         (                     ),

    .reset_n_a                  (w_reset_n_a          ),
    .ck_t_a                     (w_ck_t_a             ),
    .ck_c_a                     (w_ck_c_a             ),
    .cs0_a                      (w_cs0_a              ),
    .ca_a                       (w_ca_a               ),
    .dq_a                       (w_dq_a               ),
    .wck_t_a                    (w_wck_t_a            ),
    .wck_c_a                    (w_wck_c_a            ),
    .rdqs_t_a                   (w_rdqs_t_a           ),
    .rdqs_c_a                   (w_rdqs_c_a           ),
    .dmi_a                      (w_dmi_a              ),

    .init_en                    (r_init_en            ),
    .init_done                  (w_init_done          ),
    .init_fail                  (w_init_fail          ),
    .mrw_r                      (24'd0                ),

    .idd_en                     (10'd0                ),
    .idd_done                   (                     ),

    .read_capture_start_cnt     (8'd17                ),
    .gf_capture_start_cnt       (8'd17                ),
    .init_beat_offset           (4'd1                 ),
    .gf_beat_offset             (4'd1                 ),
    .gf_rd_wck_start_cnt        (10'd5                ),
    .gf_rd_wck_last_cnt         (10'd20               ),
    .gf_wr_wck_start_cnt        (10'd5                ),
    .gf_wr_wck_last_cnt         (10'd18               ),
    .gf_read_done_cnt           (10'd18               ),
    .gf_write_done_cnt          (10'd18               ),
    .gf_act_cmd_gap_cnt         (10'd6                ),
    .gf_rd_cmd_gap_cnt          (10'd11               ),
    .gf_wr_cmd_gap_cnt          (10'd11               ),
    .gf_pre_cmd_gap_cnt         (10'd7                ),
    .gf_refresh_batch_num       (3'd8                 ),
    .gf_pattern_mode_cfg        (2'd0                 ),
    .die_message                (w_die_message        ),
    .err_block_cnt              (                     ),
    .err_block_message          (                     ),
    .rdc_err_bitmap             (w_rdc_err_bitmap     ),
    .rdc_check_valid            (w_rdc_check_valid    ),
    .rdc_check_pass             (w_rdc_check_pass     ),

    .rdc_train_init_en          (1'b1                 ),
    .rdc_train_apply_best_cfg   (1'b1                 ),
    .rdc_train_dual_pattern_cfg (1'b1                 ),
    .rdc_train_dq_start_cfg     (4'd0                 ),
    .rdc_train_dq_end_cfg       (4'd15                ),
    .rdc_train_tap_start_cfg    (9'd0                 ),
    .rdc_train_tap_stop_cfg     (9'd3                 ),
    .rdc_train_tap_step_cfg     (9'd1                 ),
    .rdc_train_dq_delay_l_we    (1'b0                 ),
    .rdc_train_dq_delay_h_we    (1'b0                 ),
    .rdc_train_dq_delay_wdat    (96'd0                ),
    .rdc_train_scan_tap_sel     (w_rdc_train_tap      ),
    .rdc_train_state            (w_rdc_train_state    ),
    .rdc_train_busy             (w_rdc_train_busy     ),
    .rdc_train_done             (w_rdc_train_done     ),
    .rdc_train_apply_best       (w_rdc_train_apply_best),
    .rdc_train_dq_start         (w_rdc_train_dq_start ),
    .rdc_train_tap              (w_rdc_train_tap      ),
    .rdc_train_status_best_len  (w_rdc_train_status_best_len),
    .rdc_train_pass_mask        (w_rdc_train_pass_mask),
    .rdc_train_fail_mask        (w_rdc_train_fail_mask),
    .rdc_train_last_err_bitmap  (w_rdc_train_last_err_bitmap),
    .rdc_train_init_ready       (w_rdc_train_init_ready),
    .rdc_train_pass_all         (w_rdc_train_pass_all ),
    .rdc_train_best_flat        (w_rdc_train_best_flat),
    .rdc_train_left_flat        (w_rdc_train_left_flat),
    .rdc_train_right_flat       (w_rdc_train_right_flat),
    .rdc_train_scan_pass_bitmap (w_rdc_train_scan_pass_bitmap),
    .RDY                        (w_idelayctrl_ready   ),
    .delay_value_dq_a           (w_delay_value_dq_a  )
);

/***************assign****************/
assign w_sys_clk_n = ~r_sys_clk_p;

// The DRAM-side fixture only drives read pins. FPGA command/data outputs and
// every clock remain connected exclusively to the production PHY.
assign w_dq_a     = (r_dram_dq_oe == 1'b1) ? r_dram_dq_word : 16'hzzzz;
assign w_rdqs_t_a = (r_dram_dq_oe == 1'b1) ? {2{w_wck_t_a[0]}} : 2'bzz;
assign w_rdqs_c_a = (r_dram_dq_oe == 1'b1) ? {2{w_wck_c_a[0]}} : 2'bzz;
assign w_dmi_a    = 2'bzz;

assign w_channel_wck_a_run_en = U_DUT.channel_wck_a_run_en;
assign w_init_rdc_read_active =
    (U_DUT.U_lpddr5_test_scheduler.U_lpddr5_init.r_rt_mr_state == 2'd2);
assign w_init_rdc_pattern_sel =
    U_DUT.U_lpddr5_test_scheduler.init_rdc_train_pattern_sel;

/***************always****************/
// Board reference clock: 200 MHz differential input. This is the only clock
// created by the testbench; clk_wiz_0 creates all internal clocks.
always #2500 r_sys_clk_p = ~r_sys_clk_p;

// Ideal DRAM read responder. It advances one DQ beat on each physical WCK
// transition, so the production PLL phase and serialized WCK determine the
// data timing seen by the production IDELAYE3/ISERDESE3 receive path.
always @(w_wck_t_a[0] or w_channel_wck_a_run_en[0] or negedge w_phy_ready) begin
    if (w_phy_ready == 1'b0) begin
        r_dram_dq_word    = 16'h0000;
        r_dram_dq_oe      = 1'b0;
        r_dram_wck_active = 1'b0;
        r_dram_beat_index = P_DRAM_RDC_START_BEAT;
    end
    else if (w_channel_wck_a_run_en[0] == 1'b0) begin
        r_dram_dq_word    = 16'h0000;
        r_dram_dq_oe      = 1'b0;
        r_dram_wck_active = 1'b0;
        r_dram_beat_index = P_DRAM_RDC_START_BEAT;
    end
    else if (r_dram_wck_active == 1'b0) begin
        r_dram_dq_oe      = 1'b1;
        r_dram_wck_active = 1'b1;
        r_dram_beat_index = P_DRAM_RDC_START_BEAT;
        if (w_init_rdc_read_active == 1'b1)
            r_dram_dq_word = f_rdc_pin_beat(
                w_init_rdc_pattern_sel,
                r_dram_beat_index[3:0]
            );
        else
            r_dram_dq_word = P_MR8_PIN_WORD;
    end
    else begin
        #50;
        if (w_init_rdc_read_active == 1'b1) begin
            if (r_dram_beat_index >= 15)
                r_dram_beat_index = 0;
            else
                r_dram_beat_index = r_dram_beat_index + 1;
            r_dram_dq_word = f_rdc_pin_beat(
                w_init_rdc_pattern_sel,
                r_dram_beat_index[3:0]
            );
        end
        else begin
            r_dram_dq_word = P_MR8_PIN_WORD;
        end
    end
end

always @(posedge w_clk_core_200m or negedge w_phy_ready) begin
    if (w_phy_ready == 1'b0) begin
        r_init_fail_seen  <= 1'b0;
        r_capture_count   <= 0;
        r_rdc_result_count <= 0;
    end
    else begin
        if (w_init_fail == 1'b1)
            r_init_fail_seen <= 1'b1;
        else
            r_init_fail_seen <= r_init_fail_seen;

        if (U_DUT.channel_rx_dq_capture_en == 1'b1)
            r_capture_count <= r_capture_count + 1;
        else
            r_capture_count <= r_capture_count;

        if ((U_DUT.dq_a_burst_valid == 1'b1) &&
            (w_init_rdc_read_active == 1'b1))
            r_rdc_result_count <= r_rdc_result_count + 1;
        else
            r_rdc_result_count <= r_rdc_result_count;

        if (U_DUT.dq_a_burst_valid == 1'b1) begin
            r_burst_count <= r_burst_count + 1;
            if (r_burst_count < 16) begin
                $display("RDC_BURST t=%0t idx=%0d pattern=%0d tap=%0d",
                         $time,
                         r_burst_count,
                         w_init_rdc_pattern_sel,
                         w_rdc_train_tap);
                $display("RDC_GOT    %064h", U_DUT.dq_a_burst_flat);
                $display("RDC_EXPECT %064h", U_DUT.U_lpddr5_test_scheduler.rdc_expect_burst);
            end
        end
        else begin
            r_burst_count <= r_burst_count;
        end
    end
end

always @(w_ck_t_a) begin
    if (w_phy_ready == 1'b1 && w_ck_t_a !== 1'bx)
        r_ck_edge_count = r_ck_edge_count + 1;
end

always @(w_wck_t_a[0]) begin
    if (w_phy_ready == 1'b1 && w_wck_t_a[0] !== 1'bx)
        r_wck_edge_count = r_wck_edge_count + 1;
end

/***************initial***************/
initial begin
    r_sys_clk_p        = 1'b0;
    r_sys_reset        = 1'b1;
    r_init_en          = 1'b0;
    r_dram_dq_word     = 16'h0000;
    r_dram_dq_oe       = 1'b0;
    r_dram_wck_active  = 1'b0;
    r_dram_beat_index  = P_DRAM_RDC_START_BEAT;
    r_init_fail_seen   = 1'b0;
    r_init_wait_cycles = 0;
    r_capture_count    = 0;
    r_rdc_result_count = 0;
    r_ck_edge_count    = 0;
    r_wck_edge_count   = 0;
    r_burst_count      = 0;
    r_error_count      = 0;

    repeat (8) @(posedge r_sys_clk_p);
    r_sys_reset = 1'b0;

    wait (w_phy_ready == 1'b1);
    repeat (8) @(posedge w_clk_core_200m);

    r_init_en = 1'b1;
    @(posedge w_clk_core_200m);
    r_init_en = 1'b0;

    while ((w_init_done != 1'b1) &&
           (r_init_wait_cycles < P_INIT_TIMEOUT_CYCLES)) begin
        @(posedge w_clk_core_200m);
        r_init_wait_cycles = r_init_wait_cycles + 1;
    end

    if (w_init_done != 1'b1) begin
        $display("SIM FAIL: INIT timeout init_state=%0d rdc_state=%0d tap=%0d",
                 U_DUT.U_lpddr5_test_scheduler.U_lpddr5_init.r_init_state,
                 w_rdc_train_state,
                 w_rdc_train_tap);
        r_error_count = r_error_count + 1;
    end

    repeat (16) @(posedge w_clk_core_200m);

    if (w_mmcm_locked != 1'b1 ||
        w_idelayctrl_ready != 1'b1 ||
        w_phy_ready != 1'b1) begin
        $display("SIM FAIL: startup lock/RDY/ready mismatch locked=%0d rdy=%0d ready=%0d",
                 w_mmcm_locked, w_idelayctrl_ready, w_phy_ready);
        r_error_count = r_error_count + 1;
    end
    if (r_init_fail_seen != 1'b0) begin
        $display("SIM FAIL: init_fail was asserted");
        r_error_count = r_error_count + 1;
    end
    if (w_die_message != P_MR8_DENSITY) begin
        $display("SIM FAIL: MR8 density=%02h expected=%02h",
                 w_die_message, P_MR8_DENSITY);
        r_error_count = r_error_count + 1;
    end
    if (w_rdc_train_done != 1'b1 || w_rdc_train_pass_all != 1'b1) begin
        $display("SIM FAIL: RDC done/pass mismatch done=%0d pass=%0d",
                 w_rdc_train_done, w_rdc_train_pass_all);
        r_error_count = r_error_count + 1;
    end
    if (w_rdc_train_pass_mask != 16'hffff ||
        w_rdc_train_fail_mask != 16'h0000) begin
        $display("SIM FAIL: RDC masks pass=%04h fail=%04h last_err=%04h",
                 w_rdc_train_pass_mask,
                 w_rdc_train_fail_mask,
                 w_rdc_train_last_err_bitmap);
        r_error_count = r_error_count + 1;
    end
    if (r_ck_edge_count < 100 || r_wck_edge_count < 100) begin
        $display("SIM FAIL: external clock activity CK=%0d WCK=%0d",
                 r_ck_edge_count, r_wck_edge_count);
        r_error_count = r_error_count + 1;
    end

    $display("SIM INFO: startup locked=%0d idelay_rdy=%0d phy_ready=%0d",
             w_mmcm_locked, w_idelayctrl_ready, w_phy_ready);
    $display("SIM INFO: init_cycles=%0d capture_pulses=%0d rdc_results=%0d",
             r_init_wait_cycles, r_capture_count, r_rdc_result_count);
    $display("SIM INFO: RDC tap=%0d best_len=%0d pass=%04h fail=%04h",
             w_rdc_train_tap,
             w_rdc_train_status_best_len,
             w_rdc_train_pass_mask,
             w_rdc_train_fail_mask);
    $display("SIM INFO: external CK_edges=%0d WCK_edges=%0d MR8=%02h",
             r_ck_edge_count, r_wck_edge_count, w_die_message);

    if (r_error_count == 0)
        $display("SIM PASS: real PLL/startup/PHY INIT plus limited dual-pattern RDC");
    else
        $display("SIM FAIL: error_count=%0d", r_error_count);

    $finish;
end

initial begin
    #1500000000;
    $display("SIM FAIL: absolute timeout");
    $finish;
end

endmodule
