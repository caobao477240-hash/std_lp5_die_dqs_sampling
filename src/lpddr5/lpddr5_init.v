`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
// Create Date:
// Design Name:     LPDDR5 init controller
// Module Name:     lpddr5_init
// Project Name:    std_lp5_die_dqs_sampling
// Target Devices:  Xilinx UltraScale
// Tool Versions:   Vivado 2022.x
// Description:
//   LPDDR5 power-on init, fixed MR write table, MR8 readback, RDC command, and
//   runtime MRW/MRR/RDC waveform generation.
// Revision:        v0.2
//////////////////////////////////////////////////////////////////////////////////

module lpddr5_init #(
`ifdef LP5_SIM_FAST
    parameter       T_INIT0                         = 2,
    parameter       T_INIT1                         = 2,
    parameter       T_INIT2                         = 2,
    parameter       T_INIT3                         = 2,
    parameter       T_INIT4                         = 2,
    parameter       T_INIT5                         = 2,
    parameter       T_ZQCAL4                        = 3,
    parameter       T_ZQLAT                         = 3,
    parameter       T_MRR                           = 60,
    parameter       T_MRW                           = 8,
    parameter       T_TOTAL                         = 140
`else
    parameter       T_INIT0     = 4_000_050         ,
    parameter       T_INIT1     = 40_050            ,
    parameter       T_INIT2     = 12                ,
    parameter       T_INIT3     = 400_050           ,
    parameter       T_INIT4     = 10                ,
    parameter       T_INIT5     = 400_050           ,
    parameter       T_ZQCAL4    = 30                ,
    parameter       T_ZQLAT     = 30                ,
    parameter       T_MRR       = 40                ,
    parameter       T_MRW       = 20                ,
    parameter       T_TOTAL     = 1000
`endif
) (
    input                               clk                        ,
    input                               rst_n                      ,

    input                               init_en                    ,

    input                               start_mrw                  ,
    input                [  23: 0]      mrw_cmd                    ,
    input                               start_rdc                  ,
    input                               rdc_train_init_en          ,
    input                               rdc_train_apply_best_cfg   ,
    input                               rdc_train_dual_pattern_cfg ,
    input                [   3: 0]      rdc_train_dq_start_cfg     ,
    input                [   3: 0]      rdc_train_dq_end_cfg       ,
    input                [   8: 0]      rdc_train_tap_start_cfg    ,
    input                [   8: 0]      rdc_train_tap_stop_cfg     ,
    input                [   8: 0]      rdc_train_tap_step_cfg     ,
    input                               rdc_train_dq_delay_l_we    ,
    input                               rdc_train_dq_delay_h_we    ,
    input                [  95: 0]      rdc_train_dq_delay_wdat    ,
    input                [   8: 0]      rdc_train_scan_tap_sel     ,
    input                [  15: 0]      rdc_err_bitmap             ,
    input                               rdc_check_valid            ,
    input                [   7: 0]      read_capture_start_cnt     ,
    input                [  63: 0]      dq_a_word_flat             ,
    input                               dq_a_word_valid            ,

    output reg                          init_busy                  ,
    output reg                          init_done                  ,
    output                              init_fail                  ,
    output               [   2: 0]      init_state                 ,
    output                              runtime_mr_busy            ,
    output                              rdc_sample_en              ,
    output                              rx_dq_capture_en           ,
    output reg           [ 111: 0]      ascii_state                ,
    output reg           [   7: 0]      die_message                ,
    output               [  10: 0]      init_mr_cnt                ,
    output               [ 143: 0]      rdc_dq_delay_flat          ,
    output               [  23: 0]      rdc_train_mrw_r            ,
    output               [  31: 0]      rdc_train_mrr_r            ,
    output               [   3: 0]      rdc_train_state            ,
    output                              rdc_train_busy             ,
    output                              rdc_train_done             ,
    output                              rdc_train_apply_best       ,
    output               [   3: 0]      rdc_train_dq_start         ,
    output               [   8: 0]      rdc_train_tap              ,
    output                              rdc_train_pattern_sel      ,
    output               [   9: 0]      rdc_train_status_best_len  ,
    output               [  15: 0]      rdc_train_pass_mask        ,
    output               [  15: 0]      rdc_train_fail_mask        ,
    output               [  15: 0]      rdc_train_last_err_bitmap  ,
    output                              rdc_train_init_ready       ,
    output                              rdc_train_pass_all         ,
    output               [ 143: 0]      rdc_train_best_flat        ,
    output               [ 143: 0]      rdc_train_left_flat        ,
    output               [ 143: 0]      rdc_train_right_flat       ,
    output               [  15: 0]      rdc_train_scan_pass_bitmap ,

    // INIT waveform output
    output reg                          wave_reset_n_a             ,
    output reg                          wave_cs_a_0_rise           ,
    output reg                          wave_cs_a_0_fall           ,
    output reg           [   6: 0]      wave_ca_a_rise             ,
    output reg           [   6: 0]      wave_ca_a_fall             ,
    output reg           [   1: 0]      wave_wck_a_run_en
);

/***************function**************/
function is_valid_density;
    input [7:0] value;
    begin
        case (value)
            8'h0C,
            8'h0D,
            8'h10,
            8'h11,
            8'h14,
            8'h15,
            8'h18,
            8'h19: begin
                is_valid_density = 1'b1;
            end
            default: begin
                is_valid_density = 1'b0;
            end
        endcase
    end
endfunction

function [20:0] f_mrw_init_table;
    input [4:0] slot;
    begin
        case (slot)
            5'd0: begin
                f_mrw_init_table = {7'h10, 7'h08, 7'h40};
            end
            // MR1=0x29 with current MR3=0x16 selects WL6.
            5'd1: begin
                f_mrw_init_table = {7'h01, 7'h08, 7'h29};
            end
            // MR2: OP[3:0]=1 selects RL=8 nCK, OP[7:4]=1 selects nWR=10 nCK.
            5'd2: begin
                f_mrw_init_table = {7'h02, 7'h08, 7'h11};
            end
            5'd3: begin
                f_mrw_init_table = {7'h03, 7'h08, 7'h16};
            end
            5'd4: begin
                f_mrw_init_table = {7'h0a, 7'h08, 7'h00};
            end
            5'd5: begin
                f_mrw_init_table = {7'h0b, 7'h08, 7'h33};
            end
            5'd6: begin
                f_mrw_init_table = {7'h0c, 7'h08, 7'h50};
            end
            5'd7: begin
                f_mrw_init_table = {7'h0d, 7'h08, 7'h20};
            end
            5'd8: begin
                f_mrw_init_table = {7'h0e, 7'h08, 7'h50};
            end
            5'd9: begin
                f_mrw_init_table = {7'h0f, 7'h08, 7'h50};
            end
            5'd10: begin
                f_mrw_init_table = {7'h11, 7'h08, 7'h0b};
            end
            // MR18: OP[7]=1 is the board-proven CKR/WCK setting.
            5'd11: begin
                f_mrw_init_table = {7'h12, 7'h48, 7'h03};
            end
            // MR20: board-proven RDQS/WCK readback setting.
            5'd12: begin
                f_mrw_init_table = {7'h14, 7'h08, 7'h02};
            end
            // MR33: RDC pattern 0, first 8 beats = 0x5A.
            5'd13: begin
                f_mrw_init_table = {7'h21, 7'h08, 7'h5a};
            end
            // MR34: RDC pattern 0, second 8 beats = 0xA5.
            5'd14: begin
                f_mrw_init_table = {7'h22, 7'h48, 7'h25};
            end
            5'd15: begin
                f_mrw_init_table = {7'h18, 7'h08, 7'h00};
            end
            5'd16: begin
                f_mrw_init_table = {7'h1c, 7'h08, 7'h20};
            end
            5'd17: begin
                f_mrw_init_table = {7'h29, 7'h08, 7'h00};
            end
            // MR19: OP[1:0]=0 keeps DVFSC/Enhanced DVFSC disabled.
            5'd18: begin
                f_mrw_init_table = {7'h13, 7'h08, 7'h00};
            end
            // MR31: RDC invert mask low byte. 0x55 is the JEDEC default;
            // write it explicitly so the even-DQ inversion assumed by the
            // scheduler expect burst never depends on power-on state.
            5'd19: begin
                f_mrw_init_table = {7'h1f, 7'h08, 7'h55};
            end
            // MR32: RDC invert mask high byte, same 0x55 as MR31.
            5'd20: begin
                f_mrw_init_table = {7'h20, 7'h08, 7'h55};
            end
            default: begin
                f_mrw_init_table = {7'h00, 7'h08, 7'h00};
            end
        endcase
    end
endfunction

/***************parameter*************/
localparam      P_INIT_POWER_ON                   = 3'd0;
localparam      P_INIT_MR_INIT_W                  = 3'd1;
localparam      P_INIT_ZQLATCH                    = 3'd2;
localparam      P_INIT_MR_INIT_R                  = 3'd3;
localparam      P_INIT_RDC_TRAIN_START            = 3'd4;
localparam      P_INIT_RDC_TRAIN_WAIT             = 3'd5;
localparam      P_INIT_IDLE                       = 3'd6;

localparam      P_RT_MR_IDLE                      = 2'd0;
localparam      P_RT_MRW                          = 2'd1;
localparam      P_RT_RDC                          = 2'd2;

localparam      P_MR_LAST_SLOT                    = 5'd20;
localparam      P_MR_CMD_PHASE_A                  = 7'd3;
localparam      P_MR_CMD_PHASE_B                  = 7'd4;
localparam      P_WCK_START_CNT                   = 11'd5;
localparam      P_WCK_LAST_CNT                    = 11'd36;
localparam      P_WCK_OFF_CNT                     = 11'd37;

localparam [28:0] P_INIT_TOTAL_LAST               = (T_INIT0 + T_INIT1 + T_INIT2 + T_INIT3 + T_INIT4 + T_INIT5) - 29'd1;
localparam [28:0] P_INIT_RESET_KEEP_LOW_CNT       = T_INIT0;
localparam [28:0] P_INIT_RESET_RELEASE_CNT        = T_INIT0 + T_INIT1;
localparam [28:0] P_INIT_CS_ASSERT_START_CNT      = T_INIT0 + T_INIT1 + T_INIT2 + T_INIT3 + T_INIT4;
localparam [28:0] P_INIT_CS_ASSERT_LAST_CNT       = T_INIT0 + T_INIT1 + T_INIT2 + T_INIT3 + T_INIT4 + 29'd3;
localparam [11:0] P_MR_INIT_W_LAST                = T_TOTAL - 12'd1;
localparam [10:0] P_ZQCAL_LAST                    = (T_ZQCAL4 + T_ZQLAT) - 11'd1;
localparam [10:0] P_MRR_LAST                      = T_MRR - 11'd1;
localparam [10:0] P_MRW_LAST                      = T_MRW - 11'd1;
localparam [ 6:0] P_MRW_PHASE_LAST                = T_MRW - 7'd1;

/***************port******************/
/***************mechine***************/
/***************reg*******************/
reg                 ri_init_en;
reg                 ri_init_en_dly;
reg                 r_init_run;

reg                 r_power_on_cnt_en;
reg                 r_mr_init_w_cnt_en;
reg                 r_zqcal_cnt_en;
reg                 r_mr_init_r_cnt_en;

reg  [  2:0]        r_init_state;
reg  [  2:0]        r_init_state_next;
reg  [ 28:0]        r_cnt_init;
reg  [ 11:0]        r_cnt_mr_init_w;
reg  [ 10:0]        r_cnt_zqcal;
reg  [ 10:0]        r_cnt_mr_init_r;
reg                 r_init_base_done;
reg                 r_init_rdc_train_en;
reg                 r_init_fail_reported;

reg  [  6:0]        r_mr_phase;
reg  [  4:0]        r_mr_slot;
reg                 r_die_message_captured;

reg  [  1:0]        r_rt_mr_state;
reg  [ 10:0]        r_cnt_rt_mrw;
reg                 r_rt_mrw_cnt_en;
reg  [ 23:0]        r_mrw_cmd;
reg  [ 10:0]        r_cnt_rt_rdc;
reg                 r_rt_rdc_cnt_en;

/***************wire******************/
wire                w_init_start;

wire        [10:0]  w_read_sample_start_cnt;
wire                w_init_mrr_capture_start;
wire                w_rt_rdc_capture_start;
wire                w_init_base_done_now;
wire                w_init_finish_no_train;
wire                w_init_finish_train;
wire                w_init_fail_now;
wire                w_auto_rdc_train_start;
wire                w_rdc_train_start;
wire                w_rdc_train_clear;
wire                w_rt_mrw_wave_en;
wire                w_rt_rdc_wave_en;

wire        [ 7:0]  w_mrr_msg_beat0;
wire        [ 7:0]  w_mrr_msg_beat1;
wire        [ 7:0]  w_mrr_msg_beat2;
wire        [ 7:0]  w_mrr_msg_beat3;
wire                w_mrr_msg_triplet0_valid;
wire                w_mrr_msg_triplet1_valid;
wire                w_mrr_msg_word_valid;
wire        [ 7:0]  w_mrr_msg_word_data;

wire        [20:0]  w_mr_table_data;
wire        [ 6:0]  w_mr_addr_value;
wire        [ 6:0]  w_mr_op_value;
wire        [ 6:0]  w_mr_data_value;

wire                w_wck_open_window;
wire                w_wck_close_window;

/***************component*************/
rdc_train rdc_train_u0 (
    .clk                            (clk                            ),
    .rst_n                          (rst_n                          ),
    .train_start                    (w_rdc_train_start              ),
    .train_clear                    (w_rdc_train_clear              ),
    .train_apply_best_cfg           (rdc_train_apply_best_cfg       ),
    .train_dual_pattern_cfg         (rdc_train_dual_pattern_cfg     ),
    .train_dq_start_cfg             (rdc_train_dq_start_cfg         ),
    .train_dq_end_cfg               (rdc_train_dq_end_cfg           ),
    .train_tap_start_cfg            (rdc_train_tap_start_cfg        ),
    .train_tap_stop_cfg             (rdc_train_tap_stop_cfg         ),
    .train_tap_step_cfg             (rdc_train_tap_step_cfg         ),
    .dq_delay_l_we                  (rdc_train_dq_delay_l_we        ),
    .dq_delay_h_we                  (rdc_train_dq_delay_h_we        ),
    .dq_delay_wdat                  (rdc_train_dq_delay_wdat        ),
    .train_init_ready_in            (r_init_base_done               ),
    .runtime_mr_busy                (runtime_mr_busy                ),
    .rdc_err_bitmap                 (rdc_err_bitmap                 ),
    .rdc_check_valid                (rdc_check_valid                ),
    .train_scan_tap_sel             (rdc_train_scan_tap_sel         ),
    .dq_delay_flat                  (rdc_dq_delay_flat              ),
    .mrw_r                          (rdc_train_mrw_r                ),
    .mrr_r                          (rdc_train_mrr_r                ),
    .train_state                    (rdc_train_state                ),
    .train_busy                     (rdc_train_busy                 ),
    .train_done                     (rdc_train_done                 ),
    .train_apply_best               (rdc_train_apply_best           ),
    .train_dq_start                 (rdc_train_dq_start             ),
    .train_tap                      (rdc_train_tap                  ),
    .train_pattern_sel              (rdc_train_pattern_sel          ),
    .train_status_best_len          (rdc_train_status_best_len      ),
    .train_pass_mask                (rdc_train_pass_mask            ),
    .train_fail_mask                (rdc_train_fail_mask            ),
    .train_last_err_bitmap          (rdc_train_last_err_bitmap      ),
    .train_init_ready               (rdc_train_init_ready           ),
    .train_pass_all                 (rdc_train_pass_all             ),
    .train_best_flat                (rdc_train_best_flat            ),
    .train_left_flat                (rdc_train_left_flat            ),
    .train_right_flat               (rdc_train_right_flat           ),
    .train_scan_pass_bitmap         (rdc_train_scan_pass_bitmap     )
);

/***************assign****************/
assign init_state                  = r_init_state;
assign runtime_mr_busy             = (r_rt_mr_state != P_RT_MR_IDLE);
assign rdc_sample_en               = w_rt_rdc_capture_start;
assign rx_dq_capture_en            = w_init_mrr_capture_start || w_rt_rdc_capture_start;
assign init_mr_cnt                 = r_cnt_mr_init_r;
assign w_init_start                = ri_init_en && !ri_init_en_dly;
assign w_read_sample_start_cnt     = {3'b000, read_capture_start_cnt};
assign w_init_mrr_capture_start    = (r_init_state == P_INIT_MR_INIT_R) && (r_cnt_mr_init_r == w_read_sample_start_cnt);
assign w_rt_rdc_capture_start      =
    (r_rt_mr_state == P_RT_RDC) &&
    (r_cnt_rt_rdc == w_read_sample_start_cnt);

assign w_init_base_done_now        =
    (r_init_state == P_INIT_MR_INIT_R) &&
    (r_mr_init_r_cnt_en == 1'b1) &&
    (r_cnt_mr_init_r >= P_MRR_LAST);
assign w_init_finish_no_train      =
    (w_init_base_done_now == 1'b1) &&
    (r_init_rdc_train_en == 1'b0);
assign w_init_finish_train         =
    (r_init_state == P_INIT_RDC_TRAIN_WAIT) &&
    (rdc_train_done == 1'b1) &&
    (rdc_train_pass_all == 1'b1);
assign w_init_fail_now             =
    (r_init_rdc_train_en == 1'b1) &&
    (r_init_state == P_INIT_RDC_TRAIN_WAIT) &&
    (rdc_train_done == 1'b1) &&
    (rdc_train_pass_all == 1'b0);
// Report one failure pulse; BAR04 latches it as the 9C result.
assign init_fail                   = w_init_fail_now && !r_init_fail_reported;
assign w_auto_rdc_train_start      = (r_init_state == P_INIT_RDC_TRAIN_START);
assign w_rdc_train_start           = w_auto_rdc_train_start;
assign w_rdc_train_clear           = w_init_start && rdc_train_init_en;
assign w_rt_mrw_wave_en            = (r_init_state == P_INIT_IDLE) || (r_init_state == P_INIT_RDC_TRAIN_WAIT);
assign w_rt_rdc_wave_en            =
    (r_init_state == P_INIT_IDLE) ||
    (r_init_state == P_INIT_RDC_TRAIN_WAIT);

// MRR OP code is carried on DQ[7:0] of each UI; ignore the upper byte.
assign w_mrr_msg_beat0             = dq_a_word_flat[ 7: 0];
assign w_mrr_msg_beat1             = dq_a_word_flat[23:16];
assign w_mrr_msg_beat2             = dq_a_word_flat[39:32];
assign w_mrr_msg_beat3             = dq_a_word_flat[55:48];
assign w_mrr_msg_triplet0_valid    =
    (w_mrr_msg_beat0 == w_mrr_msg_beat1) &&
    (w_mrr_msg_beat1 == w_mrr_msg_beat2) &&
    is_valid_density(w_mrr_msg_beat0);
assign w_mrr_msg_triplet1_valid    =
    (w_mrr_msg_beat1 == w_mrr_msg_beat2) &&
    (w_mrr_msg_beat2 == w_mrr_msg_beat3) &&
    is_valid_density(w_mrr_msg_beat1);
assign w_mrr_msg_word_valid        =
    (r_init_state == P_INIT_MR_INIT_R) &&
    dq_a_word_valid &&
    (w_mrr_msg_triplet0_valid || w_mrr_msg_triplet1_valid);
assign w_mrr_msg_word_data         =
    w_mrr_msg_triplet0_valid ? w_mrr_msg_beat0 : w_mrr_msg_beat1;

assign w_mr_table_data             = f_mrw_init_table(r_mr_slot);
assign w_mr_addr_value             = w_mr_table_data[20:14];
assign w_mr_op_value               = w_mr_table_data[13: 7];
assign w_mr_data_value             = w_mr_table_data[ 6: 0];

assign w_wck_open_window           =
    ((r_cnt_mr_init_r >= P_WCK_START_CNT) && (r_cnt_mr_init_r <= P_WCK_LAST_CNT)) ||
    ((r_cnt_rt_rdc    >= P_WCK_START_CNT) && (r_cnt_rt_rdc    <= P_WCK_LAST_CNT));
assign w_wck_close_window          =
    (r_cnt_mr_init_r >= P_WCK_OFF_CNT) ||
    (r_cnt_rt_rdc    >= P_WCK_OFF_CNT) ||
    (r_init_state == P_INIT_IDLE);

/***************always****************/
always @(*) begin
    if (r_rt_mr_state == P_RT_RDC) begin
        ascii_state = "RT_RDC        ";
    end
    else if (runtime_mr_busy) begin
        ascii_state = "MRW           ";
    end
    else begin
        case (r_init_state)
            P_INIT_POWER_ON: begin
                ascii_state = "POWER_ON      ";
            end
            P_INIT_MR_INIT_W: begin
                ascii_state = "MR_INIT_W     ";
            end
            P_INIT_ZQLATCH: begin
                ascii_state = "ZQLATCH       ";
            end
            P_INIT_MR_INIT_R: begin
                ascii_state = "MR_INIT_R     ";
            end
            P_INIT_RDC_TRAIN_START: begin
                ascii_state = "RDC_TR_START  ";
            end
            P_INIT_RDC_TRAIN_WAIT: begin
                ascii_state = "RDC_TR_WAIT   ";
            end
            default: begin
                ascii_state = "INIT          ";
            end
        endcase
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ri_init_en     <= 1'b0;
        ri_init_en_dly <= 1'b0;
    end
    else begin
        ri_init_en     <= init_en;
        ri_init_en_dly <= ri_init_en;
    end
end

always @(*) begin
    r_init_state_next = r_init_state;

    case (r_init_state)
        P_INIT_POWER_ON: begin
            if (r_power_on_cnt_en && r_init_run && (r_cnt_init >= P_INIT_TOTAL_LAST)) begin
                r_init_state_next = P_INIT_MR_INIT_W;
            end
        end
        P_INIT_MR_INIT_W: begin
            if (r_mr_init_w_cnt_en && (r_cnt_mr_init_w >= P_MR_INIT_W_LAST)) begin
                r_init_state_next = P_INIT_ZQLATCH;
            end
        end
        P_INIT_ZQLATCH: begin
            if (r_zqcal_cnt_en && (r_cnt_zqcal >= P_ZQCAL_LAST)) begin
                r_init_state_next = P_INIT_MR_INIT_R;
            end
        end
        P_INIT_MR_INIT_R: begin
            if (r_mr_init_r_cnt_en && (r_cnt_mr_init_r >= P_MRR_LAST)) begin
                if (r_init_rdc_train_en == 1'b1) begin
                    r_init_state_next = P_INIT_RDC_TRAIN_START;
                end
                else begin
                    r_init_state_next = P_INIT_IDLE;
                end
            end
        end
        P_INIT_RDC_TRAIN_START: begin
            r_init_state_next = P_INIT_RDC_TRAIN_WAIT;
        end
        P_INIT_RDC_TRAIN_WAIT: begin
            if ((rdc_train_done == 1'b1) &&
                (rdc_train_pass_all == 1'b1)) begin
                r_init_state_next = P_INIT_IDLE;
            end
        end
        P_INIT_IDLE: begin
            if (w_init_start) begin
                r_init_state_next = P_INIT_POWER_ON;
            end
        end
        default: begin
            r_init_state_next = P_INIT_POWER_ON;
        end
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_init_state <= P_INIT_POWER_ON;
    end
    else if (w_init_start) begin
        r_init_state <= P_INIT_POWER_ON;
    end
    else begin
        r_init_state <= r_init_state_next;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_init_run <= 1'b0;
    end
    else if (w_init_start) begin
        r_init_run <= 1'b1;
    end
    else if ((w_init_finish_no_train == 1'b1) || (w_init_finish_train == 1'b1)) begin
        r_init_run <= 1'b0;
    end
    else begin
        r_init_run <= r_init_run;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        init_busy <= 1'b0;
    end
    else if (w_init_start) begin
        init_busy <= 1'b1;
    end
    else if ((w_init_finish_no_train == 1'b1) || (w_init_finish_train == 1'b1)) begin
        init_busy <= 1'b0;
    end
    else begin
        init_busy <= init_busy;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        init_done <= 1'b0;
    end
    else if (w_init_start) begin
        init_done <= 1'b0;
    end
    else if ((w_init_finish_no_train == 1'b1) ||
             (w_init_finish_train == 1'b1)) begin
        init_done <= 1'b1;
    end
    else begin
        init_done <= 1'b0;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_init_base_done <= 1'b0;
    end
    else if (w_init_start) begin
        r_init_base_done <= 1'b0;
    end
    else if (w_init_base_done_now == 1'b1) begin
        r_init_base_done <= 1'b1;
    end
    else begin
        r_init_base_done <= r_init_base_done;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_init_rdc_train_en <= 1'b0;
    end
    else if (w_init_start) begin
        r_init_rdc_train_en <= rdc_train_init_en;
    end
    else begin
        r_init_rdc_train_en <= r_init_rdc_train_en;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_init_fail_reported <= 1'b0;
    end
    else if (w_init_start) begin
        r_init_fail_reported <= 1'b0;
    end
    else if (w_init_fail_now) begin
        r_init_fail_reported <= 1'b1;
    end
    else begin
        r_init_fail_reported <= r_init_fail_reported;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        die_message <= 8'h00;
    end
    else if (w_init_start) begin
        die_message <= 8'h00;
    end
    else if (!r_die_message_captured && w_mrr_msg_word_valid) begin
        die_message <= w_mrr_msg_word_data;
    end
    else begin
        die_message <= die_message;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_die_message_captured <= 1'b0;
    end
    else if (w_init_start) begin
        r_die_message_captured <= 1'b0;
    end
    else if (w_mrr_msg_word_valid) begin
        r_die_message_captured <= 1'b1;
    end
    else begin
        r_die_message_captured <= r_die_message_captured;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_cnt_init <= 29'd0;
    end
    else if (w_init_start) begin
        r_cnt_init <= 29'd0;
    end
    else if ((r_init_state == P_INIT_POWER_ON) && r_power_on_cnt_en && r_init_run && (r_cnt_init >= P_INIT_TOTAL_LAST)) begin
        r_cnt_init <= 29'd0;
    end
    else if ((r_init_state == P_INIT_POWER_ON) && r_power_on_cnt_en && r_init_run) begin
        r_cnt_init <= r_cnt_init + 29'd1;
    end
    else begin
        r_cnt_init <= r_cnt_init;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_power_on_cnt_en <= 1'b0;
    end
    else if (w_init_start) begin
        r_power_on_cnt_en <= 1'b0;
    end
    else if ((r_init_state == P_INIT_POWER_ON) && r_power_on_cnt_en && r_init_run && (r_cnt_init >= P_INIT_TOTAL_LAST)) begin
        r_power_on_cnt_en <= 1'b0;
    end
    else if (r_init_state == P_INIT_POWER_ON) begin
        r_power_on_cnt_en <= 1'b1;
    end
    else begin
        r_power_on_cnt_en <= r_power_on_cnt_en;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_cnt_mr_init_w <= 12'd0;
    end
    else if (w_init_start) begin
        r_cnt_mr_init_w <= 12'd0;
    end
    else if ((r_init_state == P_INIT_MR_INIT_W) && r_mr_init_w_cnt_en && (r_cnt_mr_init_w >= P_MR_INIT_W_LAST)) begin
        r_cnt_mr_init_w <= 12'd0;
    end
    else if ((r_init_state == P_INIT_MR_INIT_W) && r_mr_init_w_cnt_en) begin
        r_cnt_mr_init_w <= r_cnt_mr_init_w + 12'd1;
    end
    else begin
        r_cnt_mr_init_w <= r_cnt_mr_init_w;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_mr_phase <= 7'd0;
        r_mr_slot  <= 5'd0;
    end
    else if (w_init_start) begin
        r_mr_phase <= 7'd0;
        r_mr_slot  <= 5'd0;
    end
    else if ((r_init_state == P_INIT_MR_INIT_W) && r_mr_init_w_cnt_en && (r_cnt_mr_init_w >= P_MR_INIT_W_LAST)) begin
        r_mr_phase <= 7'd0;
        r_mr_slot  <= 5'd0;
    end
    else if ((r_init_state == P_INIT_MR_INIT_W) && r_mr_init_w_cnt_en && (r_mr_phase >= P_MRW_PHASE_LAST)) begin
        r_mr_phase <= 7'd0;
        r_mr_slot  <= r_mr_slot + 5'd1;
    end
    else if ((r_init_state == P_INIT_MR_INIT_W) && r_mr_init_w_cnt_en) begin
        r_mr_phase <= r_mr_phase + 7'd1;
        r_mr_slot  <= r_mr_slot;
    end
    else begin
        r_mr_phase <= r_mr_phase;
        r_mr_slot  <= r_mr_slot;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_mr_init_w_cnt_en <= 1'b0;
    end
    else if (w_init_start) begin
        r_mr_init_w_cnt_en <= 1'b0;
    end
    else if ((r_init_state == P_INIT_MR_INIT_W) && r_mr_init_w_cnt_en && (r_cnt_mr_init_w >= P_MR_INIT_W_LAST)) begin
        r_mr_init_w_cnt_en <= 1'b0;
    end
    else if (r_init_state == P_INIT_MR_INIT_W) begin
        r_mr_init_w_cnt_en <= 1'b1;
    end
    else begin
        r_mr_init_w_cnt_en <= r_mr_init_w_cnt_en;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_cnt_zqcal <= 11'd0;
    end
    else if (w_init_start) begin
        r_cnt_zqcal <= 11'd0;
    end
    else if ((r_init_state == P_INIT_ZQLATCH) && r_zqcal_cnt_en && (r_cnt_zqcal >= P_ZQCAL_LAST)) begin
        r_cnt_zqcal <= 11'd0;
    end
    else if ((r_init_state == P_INIT_ZQLATCH) && r_zqcal_cnt_en) begin
        r_cnt_zqcal <= r_cnt_zqcal + 11'd1;
    end
    else begin
        r_cnt_zqcal <= r_cnt_zqcal;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_zqcal_cnt_en <= 1'b0;
    end
    else if (w_init_start) begin
        r_zqcal_cnt_en <= 1'b0;
    end
    else if ((r_init_state == P_INIT_ZQLATCH) && r_zqcal_cnt_en && (r_cnt_zqcal >= P_ZQCAL_LAST)) begin
        r_zqcal_cnt_en <= 1'b0;
    end
    else if (r_init_state == P_INIT_ZQLATCH) begin
        r_zqcal_cnt_en <= 1'b1;
    end
    else begin
        r_zqcal_cnt_en <= r_zqcal_cnt_en;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_cnt_mr_init_r <= 11'd0;
    end
    else if (w_init_start) begin
        r_cnt_mr_init_r <= 11'd0;
    end
    else if ((r_init_state == P_INIT_MR_INIT_R) && r_mr_init_r_cnt_en && (r_cnt_mr_init_r >= P_MRR_LAST)) begin
        r_cnt_mr_init_r <= 11'd0;
    end
    else if ((r_init_state == P_INIT_MR_INIT_R) && r_mr_init_r_cnt_en) begin
        r_cnt_mr_init_r <= r_cnt_mr_init_r + 11'd1;
    end
    else begin
        r_cnt_mr_init_r <= r_cnt_mr_init_r;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_mr_init_r_cnt_en <= 1'b0;
    end
    else if (w_init_start) begin
        r_mr_init_r_cnt_en <= 1'b0;
    end
    else if ((r_init_state == P_INIT_MR_INIT_R) && r_mr_init_r_cnt_en && (r_cnt_mr_init_r >= P_MRR_LAST)) begin
        r_mr_init_r_cnt_en <= 1'b0;
    end
    else if (r_init_state == P_INIT_MR_INIT_R) begin
        r_mr_init_r_cnt_en <= 1'b1;
    end
    else begin
        r_mr_init_r_cnt_en <= r_mr_init_r_cnt_en;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_rt_mr_state <= P_RT_MR_IDLE;
        r_mrw_cmd     <= 24'd0;
    end
    else if (w_init_start) begin
        r_rt_mr_state <= P_RT_MR_IDLE;
        r_mrw_cmd     <= 24'd0;
    end
    else begin
        case (r_rt_mr_state)
            P_RT_MR_IDLE: begin
                if (start_mrw) begin
                    r_rt_mr_state <= P_RT_MRW;
                    r_mrw_cmd     <= mrw_cmd;
                end
                else if (start_rdc) begin
                    r_rt_mr_state <= P_RT_RDC;
                    r_mrw_cmd     <= r_mrw_cmd;
                end
                else begin
                    r_rt_mr_state <= r_rt_mr_state;
                    r_mrw_cmd     <= r_mrw_cmd;
                end
            end
            P_RT_MRW: begin
                if (r_rt_mrw_cnt_en && (r_cnt_rt_mrw >= P_MRW_LAST)) begin
                    r_rt_mr_state <= P_RT_MR_IDLE;
                end
                else begin
                    r_rt_mr_state <= r_rt_mr_state;
                end
                r_mrw_cmd <= r_mrw_cmd;
            end
            P_RT_RDC: begin
                if (r_rt_rdc_cnt_en && (r_cnt_rt_rdc >= P_MRR_LAST)) begin
                    r_rt_mr_state <= P_RT_MR_IDLE;
                end
                else begin
                    r_rt_mr_state <= r_rt_mr_state;
                end
                r_mrw_cmd <= r_mrw_cmd;
            end
            default: begin
                r_rt_mr_state <= P_RT_MR_IDLE;
                r_mrw_cmd     <= r_mrw_cmd;
            end
        endcase
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_cnt_rt_mrw <= 11'd0;
    end
    else if (w_init_start) begin
        r_cnt_rt_mrw <= 11'd0;
    end
    else if ((r_rt_mr_state == P_RT_MRW) && r_rt_mrw_cnt_en && (r_cnt_rt_mrw >= P_MRW_LAST)) begin
        r_cnt_rt_mrw <= 11'd0;
    end
    else if ((r_rt_mr_state == P_RT_MRW) && r_rt_mrw_cnt_en) begin
        r_cnt_rt_mrw <= r_cnt_rt_mrw + 11'd1;
    end
    else begin
        r_cnt_rt_mrw <= r_cnt_rt_mrw;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_rt_mrw_cnt_en <= 1'b0;
    end
    else if (w_init_start) begin
        r_rt_mrw_cnt_en <= 1'b0;
    end
    else if ((r_rt_mr_state == P_RT_MRW) && r_rt_mrw_cnt_en && (r_cnt_rt_mrw >= P_MRW_LAST)) begin
        r_rt_mrw_cnt_en <= 1'b0;
    end
    else if (r_rt_mr_state == P_RT_MRW) begin
        r_rt_mrw_cnt_en <= 1'b1;
    end
    else begin
        r_rt_mrw_cnt_en <= r_rt_mrw_cnt_en;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_cnt_rt_rdc <= 11'd0;
    end
    else if (w_init_start) begin
        r_cnt_rt_rdc <= 11'd0;
    end
    else if ((r_rt_mr_state == P_RT_RDC) && r_rt_rdc_cnt_en && (r_cnt_rt_rdc >= P_MRR_LAST)) begin
        r_cnt_rt_rdc <= 11'd0;
    end
    else if ((r_rt_mr_state == P_RT_RDC) && r_rt_rdc_cnt_en) begin
        r_cnt_rt_rdc <= r_cnt_rt_rdc + 11'd1;
    end
    else begin
        r_cnt_rt_rdc <= r_cnt_rt_rdc;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_rt_rdc_cnt_en <= 1'b0;
    end
    else if (w_init_start) begin
        r_rt_rdc_cnt_en <= 1'b0;
    end
    else if ((r_rt_mr_state == P_RT_RDC) && r_rt_rdc_cnt_en && (r_cnt_rt_rdc >= P_MRR_LAST)) begin
        r_rt_rdc_cnt_en <= 1'b0;
    end
    else if (r_rt_mr_state == P_RT_RDC) begin
        r_rt_rdc_cnt_en <= 1'b1;
    end
    else begin
        r_rt_rdc_cnt_en <= r_rt_rdc_cnt_en;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        wave_reset_n_a <= 1'b0;
    else if (w_init_start)
        wave_reset_n_a <= 1'b0;
    else if ((r_init_state == P_INIT_POWER_ON) && (r_cnt_init == P_INIT_RESET_KEEP_LOW_CNT))
        wave_reset_n_a <= 1'b0;
    else if ((r_init_state == P_INIT_POWER_ON) && (r_cnt_init == P_INIT_RESET_RELEASE_CNT))
        wave_reset_n_a <= 1'b1;
    else
        wave_reset_n_a <= wave_reset_n_a;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wave_cs_a_0_fall <= 1'b0;
        wave_cs_a_0_rise <= 1'b0;
    end
    else if (w_init_start) begin
        wave_cs_a_0_fall <= 1'b0;
        wave_cs_a_0_rise <= 1'b0;
    end
    else if ((r_init_state == P_INIT_POWER_ON)&&(r_cnt_init >= P_INIT_CS_ASSERT_START_CNT)&&(r_cnt_init <= P_INIT_CS_ASSERT_LAST_CNT)) begin
        wave_cs_a_0_fall <= 1'b1;
        wave_cs_a_0_rise <= 1'b1;
    end
    else if (
        (r_init_state == P_INIT_MR_INIT_W) &&
        (r_mr_slot <= P_MR_LAST_SLOT) &&
        ((r_mr_phase == P_MR_CMD_PHASE_A) || (r_mr_phase == P_MR_CMD_PHASE_B))
    ) begin
        wave_cs_a_0_fall <= 1'b1;
        wave_cs_a_0_rise <= 1'b1;
    end
    else if ((r_init_state == P_INIT_ZQLATCH) && (r_cnt_zqcal == 11'd3)) begin
        wave_cs_a_0_fall <= 1'b1;
        wave_cs_a_0_rise <= 1'b1;
    end
    else if ((r_init_state == P_INIT_MR_INIT_R) && ((r_cnt_mr_init_r == 11'd3) || (r_cnt_mr_init_r == 11'd4))) begin
        wave_cs_a_0_fall <= 1'b1;
        wave_cs_a_0_rise <= 1'b1;
    end
    else if ((w_rt_mrw_wave_en == 1'b1) && (r_rt_mr_state == P_RT_MRW) && ((r_cnt_rt_mrw == 11'd3) || (r_cnt_rt_mrw == 11'd4))) begin
        wave_cs_a_0_fall <= 1'b1;
        wave_cs_a_0_rise <= 1'b1;
    end
    else if ((w_rt_rdc_wave_en == 1'b1) && (r_rt_mr_state == P_RT_RDC) && ((r_cnt_rt_rdc == 11'd3) || (r_cnt_rt_rdc == 11'd4))) begin
        wave_cs_a_0_fall <= 1'b1;
        wave_cs_a_0_rise <= 1'b1;
    end
    else begin
        wave_cs_a_0_fall <= 1'b0;
        wave_cs_a_0_rise <= 1'b0;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wave_ca_a_fall <= 7'h00;
        wave_ca_a_rise <= 7'h00;
    end
    else if (w_init_start) begin
        wave_ca_a_fall <= 7'h00;
        wave_ca_a_rise <= 7'h00;
    end
    else if ((r_init_state == P_INIT_MR_INIT_W) && (r_mr_slot <= P_MR_LAST_SLOT) && (r_mr_phase == P_MR_CMD_PHASE_A)) begin
        wave_ca_a_fall <= w_mr_addr_value;
        wave_ca_a_rise <= 7'h58;
    end
    else if ((r_init_state == P_INIT_MR_INIT_W) && (r_mr_slot <= P_MR_LAST_SLOT) && (r_mr_phase == P_MR_CMD_PHASE_B)) begin
        wave_ca_a_fall <= w_mr_data_value;
        wave_ca_a_rise <= w_mr_op_value;
    end
    else if ((r_init_state == P_INIT_ZQLATCH) && (r_cnt_zqcal == 11'd3)) begin
        wave_ca_a_fall <= 7'h06;
        wave_ca_a_rise <= 7'h70;
    end
    else if ((r_init_state == P_INIT_MR_INIT_R) && (r_cnt_mr_init_r == 11'd3)) begin
        wave_ca_a_fall <= 7'b0000000;
        wave_ca_a_rise <= 7'b0101100;
    end
    else if ((r_init_state == P_INIT_MR_INIT_R) && (r_cnt_mr_init_r == 11'd4)) begin
        wave_ca_a_fall <= 7'b0001000;
        wave_ca_a_rise <= 7'b0011000;
    end
    else if ((w_rt_mrw_wave_en == 1'b1) && (r_rt_mr_state == P_RT_MRW) && (r_cnt_rt_mrw == 11'd3)) begin
        wave_ca_a_fall <= r_mrw_cmd[6:0];
        wave_ca_a_rise <= 7'h58;
    end
    else if ((w_rt_mrw_wave_en == 1'b1) && (r_rt_mr_state == P_RT_MRW) && (r_cnt_rt_mrw == 11'd4)) begin
        wave_ca_a_fall <= r_mrw_cmd[14:8];
        wave_ca_a_rise <= {r_mrw_cmd[15], 6'h08};
    end
    else if ((w_rt_rdc_wave_en == 1'b1) && (r_rt_mr_state == P_RT_RDC) && (r_cnt_rt_rdc == 11'd3)) begin
        wave_ca_a_fall <= 7'b0000000;
        wave_ca_a_rise <= 7'b0101100;
    end
    else if ((w_rt_rdc_wave_en == 1'b1) && (r_rt_mr_state == P_RT_RDC) && (r_cnt_rt_rdc == 11'd4)) begin
        wave_ca_a_fall <= 7'b0000000;
        wave_ca_a_rise <= 7'b1010000;
    end
    else begin
        wave_ca_a_fall <= 7'h00;
        wave_ca_a_rise <= 7'h00;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        wave_wck_a_run_en <= 2'b00;
    else if (w_init_start)
        wave_wck_a_run_en <= 2'b00;
    else if (w_wck_open_window)
        wave_wck_a_run_en <= 2'b11;
    else if (w_wck_close_window)
        wave_wck_a_run_en <= 2'b00;
    else
        wave_wck_a_run_en <= wave_wck_a_run_en;
end

endmodule
