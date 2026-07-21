`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
// Create Date:     2026/07/02
// Design Name:     LPDDR5 GF Engine
// Module Name:     lpddr5_gf_engine
// Project Name:    std_lp5_die_clk800M
// Target Devices:  Xilinx UltraScale
// Tool Versions:   Vivado 2022.2
// Description:
//   LPDDR5 GF channel-A transaction engine. This module owns GF command timing,
//   WCK timing, DQ transmit word generation, DQ receive comparison, address
//   traversal, and error reporting.
// Dependencies:
//   BLOCK64
// Revision:        v0.1
//////////////////////////////////////////////////////////////////////////////////
/***************module**************/
module lpddr5_gf_engine #(
    parameter T_RCD         = 12,
    parameter T_READ        = 40,
    parameter T_WRITE       = 28,
    parameter T_RPab        = 12,
    parameter TRFCab        = 64,
    parameter T_REFI_CYCLES = 781
) (
    input               clk                             ,
    input               rst_n                           ,
    input               engine_inhibit                  ,
    input               idd_ck_stop                     ,

    input       [5:0]   GF_start_col                    ,
    input       [5:0]   GF_end_col                      ,
    input       [17:0]  GF_start_row                    ,
    input       [17:0]  GF_end_row                      ,
    input       [1:0]   GF_start_bg                     ,
    input       [1:0]   GF_end_bg                       ,
    input       [1:0]   GF_start_ba                     ,
    input       [1:0]   GF_end_ba                       ,
    input               gf_test_en                      ,
    input               gf_pass_start                   ,
    input       [1:0]   gf_op_mode                      ,
    input               gf_read_data_sel                 ,
    input               gf_write_data_sel                ,
    input               march_y_sequence                ,
    input       [7:0]   die_message                     ,
    input       [7:0]   read_capture_start_cnt          ,
    input       [9:0]   gf_rd_wck_start_cnt             ,
    input       [9:0]   gf_rd_wck_last_cnt              ,
    input       [9:0]   gf_wr_wck_start_cnt             ,
    input       [9:0]   gf_wr_wck_last_cnt              ,
    input       [9:0]   gf_read_done_cnt                ,
    input       [9:0]   gf_write_done_cnt               ,
    input       [9:0]   gf_act_cmd_gap_cnt              ,
    input       [9:0]   gf_rd_cmd_gap_cnt               ,
    input       [9:0]   gf_wr_cmd_gap_cnt               ,
    input       [9:0]   gf_pre_cmd_gap_cnt              ,
    input       [2:0]   gf_refresh_batch_num            ,
    input       [1:0]   gf_pattern_mode_cfg             ,
    input       [255:0] dq_a_burst_flat                 ,
    input               dq_a_burst_valid                ,

    output reg  [31:0]  err_cnt_GF                      ,
    output      [7:0]   err_block_cnt                   ,
    output      [63:0]  err_block_message               ,
    output reg          gf_pass_done                    ,

    output      [20:0]  gf_state                        ,
    output reg          gf_pass_start_d                 ,
    output reg          gf_en_read                      ,
    output reg          gf_en_write                     ,
    output              rx_dq_capture_en                ,
    output reg          gf_err_flag                     ,
    output      [9:0]   gf_cnt_read_value               ,
    output      [9:0]   gf_cnt_write_value              ,
    output              gf_compare_window               ,
    output              gf_compare_mismatch_odd         ,
    output              gf_compare_mismatch_even        ,
    output      [27:0]  gf_access_addr                  ,
    output      [15:0]  gf_read_expected_beat           ,
    output reg  [1:0]   gf_cnt_ba                       ,
    output reg  [1:0]   gf_cnt_bg                       ,
    output reg  [17:0]  gf_cnt_row                      ,
    output reg  [5:0]   gf_cnt_col                      ,
    output reg  [17:0]  gf_cnt_row_ns                   ,
    output reg  [111:0] ascii_state                     ,

    output reg          wave_ck_a_run_en                ,
    output reg          wave_cs_a_0_rise                 ,
    output reg          wave_cs_a_0_fall                 ,
    output reg  [6:0]   wave_ca_a_rise                   ,
    output reg  [6:0]   wave_ca_a_fall                   ,
    output reg  [1:0]   wave_wck_a_run_en                ,
    output reg  [1:0]   wave_wck_a_phase                 ,
    output reg  [63:0]  wave_dq_a_tx_word               ,
    output reg          wave_dq_oe
);

/******************************function*****************************/
function [15:0] gf_addr_beat;
    input                [  17: 0]      addr_row                   ;
    input                [   1: 0]      addr_bg                    ;
    input                [   1: 0]      addr_ba                    ;
    input                [   5: 0]      addr_col                   ;
    begin
        gf_addr_beat = {addr_row[5:0], addr_bg, addr_ba, addr_col} ;
    end
endfunction

function [15:0] gf_march_beat;
    input                               data_sel                   ;
    input                [  17: 0]      addr_row                   ;
    input                [   1: 0]      addr_bg                    ;
    input                [   1: 0]      addr_ba                    ;
    input                [   5: 0]      addr_col                   ;
    reg                  [  15: 0]      addr_beat                  ;
    begin
        addr_beat = gf_addr_beat(addr_row, addr_bg, addr_ba, addr_col);

        // March logical data is address-dependent to avoid a flat fixed pattern.
        if (data_sel == addr_beat[0])
            gf_march_beat = addr_beat  ;
        else
            gf_march_beat = ~addr_beat ;
    end
endfunction

function [15:0] gf_pattern_beat;
    input                [   1: 0]      pattern_mode               ;
    input                               data_sel                   ;
    input                [  17: 0]      addr_row                   ;
    input                [   1: 0]      addr_bg                    ;
    input                [   1: 0]      addr_ba                    ;
    input                [   5: 0]      addr_col                   ;
    input                [  15: 0]      beat_index                 ;
    reg                  [  15: 0]      addr_pattern               ;
    begin
        addr_pattern = gf_march_beat(data_sel, addr_row, addr_bg,
                                     addr_ba, addr_col);

        case (pattern_mode)
            2'd0: begin
                if (beat_index[0] == 1'b1)
                    gf_pattern_beat = ~addr_pattern;
                else
                    gf_pattern_beat = addr_pattern;
            end

            2'd1: begin
                // Maximum write stress: every DQ toggles on every beat.
                gf_pattern_beat = {16{data_sel ^ beat_index[0]}};
            end

            default: begin
                gf_pattern_beat = addr_pattern;
            end
        endcase
    end
endfunction

function [63:0] gf_pattern_word;
    input                [   1: 0]      pattern_mode               ;
    input                               data_sel                   ;
    input                [  17: 0]      addr_row                   ;
    input                [   1: 0]      addr_bg                    ;
    input                [   1: 0]      addr_ba                    ;
    input                [   5: 0]      addr_col                   ;
    input                [   9: 0]      payload_cnt                ;
    reg                  [  15: 0]      beat0                      ;
    begin
        if (payload_cnt <= 10'd4) begin
            beat0 = {4'b0000, payload_cnt, 2'b00} - 16'd1;
            gf_pattern_word = {
                gf_pattern_beat(pattern_mode, data_sel, addr_row,
                                addr_bg, addr_ba, addr_col, beat0 + 16'd3),
                gf_pattern_beat(pattern_mode, data_sel, addr_row,
                                addr_bg, addr_ba, addr_col, beat0 + 16'd2),
                gf_pattern_beat(pattern_mode, data_sel, addr_row,
                                addr_bg, addr_ba, addr_col, beat0 + 16'd1),
                gf_pattern_beat(pattern_mode, data_sel, addr_row,
                                addr_bg, addr_ba, addr_col, beat0)
            };
        end
        else begin
            gf_pattern_word = 64'h0000_0000_0000_0000;
        end
    end
endfunction

function [3:0] gf_bank_index;
    input                [   1: 0]      addr_bg                    ;
    input                [   1: 0]      addr_ba                    ;
    begin
        gf_bank_index = {addr_bg, addr_ba};
    end
endfunction

function [1:0] gf_bank_bg;
    input                [   3: 0]      bank_index                 ;
    begin
        gf_bank_bg = bank_index[3:2];
    end
endfunction

function [1:0] gf_bank_ba;
    input                [   3: 0]      bank_index                 ;
    begin
        gf_bank_ba = bank_index[1:0];
    end
endfunction

function [3:0] gf_stream_bank_index;
    input                               bank_reverse               ;
    input                [   3: 0]      bank_start_index           ;
    input                [   3: 0]      bank_end_index             ;
    input                [   4: 0]      bank_slot                  ;
    reg                  [   3: 0]      linear_index               ;
    begin
        if (bank_reverse == 1'b1)
            linear_index = bank_end_index - bank_slot[3:0];
        else
            linear_index = bank_start_index + bank_slot[3:0];

        // Rotate bank groups first so one BG is revisited every four slots.
        if ((bank_start_index == 4'd0) &&
            (bank_end_index == 4'd15))
            gf_stream_bank_index = {linear_index[1:0],
                                    linear_index[3:2]};
        else
            gf_stream_bank_index = linear_index;
    end
endfunction

function [63:0] gf_dbg_write_word;
    input                [   9: 0]      cnt_write_value            ;
    reg                  [  15: 0]      beat_base                  ;
    begin
        beat_base = {4'b0000, cnt_write_value, 2'b00};
        gf_dbg_write_word = {
            beat_base + 16'd3,
            beat_base + 16'd2,
            beat_base + 16'd1,
            beat_base
        };
    end
endfunction

function [63:0] gf_write_window_word;
    input                [   9: 0]      cnt_write_value            ;
    reg                  [  15: 0]      beat0                      ;
    begin
        if ((cnt_write_value >= 10'd10) && (cnt_write_value <= 10'd14)) begin
            beat0 = ((cnt_write_value - 10'd10) << 2) - 16'd1;

            gf_write_window_word = {
                beat0 + 16'd3,
                beat0 + 16'd2,
                beat0 + 16'd1,
                beat0
            };

            // gf_write_window_word = {16'h5555, 16'haaaa, 16'h5555, 16'haaaa};
        end
        else begin
            gf_write_window_word = 64'h0000_0000_0000_0000;
        end
    end
endfunction

function gf_pattern_mismatch;
    input                [ 255: 0]      burst_data                 ;
    input                [   1: 0]      pattern_mode               ;
    input                               data_sel                   ;
    input                [  17: 0]      addr_row                   ;
    input                [   1: 0]      addr_bg                    ;
    input                [   1: 0]      addr_ba                    ;
    input                [   5: 0]      addr_col                   ;
    input                               odd_sel                    ;
    integer                             beat                       ;
    begin
        gf_pattern_mismatch = 1'b0;
        for (beat = 0; beat < 16; beat = beat + 1) begin
            if ((beat[0] == odd_sel) &&
                (burst_data[(16 * beat) +: 16] !=
                 gf_pattern_beat(pattern_mode, data_sel, addr_row,
                                 addr_bg, addr_ba, addr_col, beat[15:0])))
                gf_pattern_mismatch = 1'b1;
        end
    end
endfunction

/******************************parameter*****************************/
    localparam    [  20: 0]      GF_IDLE                     = 21'b0_0000_0000_0000_1000_0000;
    localparam    [  20: 0]      GF_SCHED                    = 21'b0_0000_0000_0000_1000_0001;
    localparam    [  20: 0]      GF_ACTIVATING               = 21'b0_0000_0000_0001_0000_0000;
    localparam    [  20: 0]      GF_WRITE                    = 21'b0_0000_0000_0010_0000_0000;
    localparam    [  20: 0]      GF_READ                     = 21'b0_0000_0000_0100_0000_0000;
    localparam    [  20: 0]      GF_WRITE_AFTER_READ         = 21'b0_0000_0000_0100_0000_0001;
    localparam    [  20: 0]      GF_WTR_WAIT                 = 21'b0_0000_0000_0100_0000_0010;
    localparam    [  20: 0]      GF_PRECHARGING              = 21'b0_0000_0000_1000_0000_0000;
    localparam    [  20: 0]      GF_REFRESH                  = 21'b0_0000_0000_1000_0000_0001;
    localparam    [  20: 0]      GF_PRE_REFRESH              = 21'b0_0000_0000_1000_0000_0010;

    localparam                   GF_WCK_INVERT               = 1'b0                 ;
    localparam    [   1: 0]      GF_OP_WRITE_ONLY            = 2'd0                 ;
    localparam    [   1: 0]      GF_OP_READ_ONLY             = 2'd1                 ;
    localparam    [   1: 0]      GF_OP_READ_WRITE            = 2'd2                 ;
    localparam    [   1: 0]      GF_PATTERN_ADDR_TOGGLE      = 2'd0                 ;
    localparam    [   1: 0]      GF_PATTERN_WRITE_STRESS     = 2'd1                 ;
    localparam                   GF_ROW_REFRESH_EN           = 1'b1                 ;
    localparam    [   9: 0]      GF_CMD_START_CNT            = 10'd3                ;
    localparam    [   9: 0]      GF_ACT_CMD_GAP_DFT          = 10'd16               ;
    localparam    [   9: 0]      GF_RD_CMD_GAP_DFT           = 10'd12               ;
    localparam    [   9: 0]      GF_WR_CMD_GAP_DFT           = 10'd12               ;
    localparam    [   9: 0]      GF_PRE_CMD_GAP_DFT          = 10'd16               ;
    localparam    [   9: 0]      GF_CMD_GAP_MAX              = 10'd64               ;
    localparam    [   4: 0]      GF_PREAB_LAST_SLOT          = 5'd0                 ;
    localparam    [   9: 0]      GF_WTR_WAIT_CNT             = 10'd6                ;
// Current die setting is MR1=0x29 with MR3=0x16, which selects WL6.
// Keep this explicit because the WRITE command to DQ/WCK timing math depends
// on the real WL, not only the MR1 upper nibble.
    localparam    [   9: 0]      GF_WR_PAYLOAD_START_CNT     = 10'd10               ;
    localparam    [   9: 0]      GF_WR_OE_PRE_CNT            = 10'd2                ;
    localparam    [   9: 0]      GF_WR_OE_POST_CNT           = 10'd1                ;
    localparam    [   9: 0]      GF_WR_OE_START_CNT          = GF_WR_PAYLOAD_START_CNT -
                                                               GF_WR_OE_PRE_CNT      ;
    localparam    [   4: 0]      GF_READ_FIFO_DEPTH          = 5'd16                ;
// WCK open windows and transaction done counters come from bar06 CAPTURE_CFG
// registers so timing can be swept on hardware without a rebuild. Legacy done
// counts were READ 39 and WRITE 27, equal to old T_READ/T_WRITE minus one.

/***************reg*******************/
    reg                  [  20: 0]      state_c                    ;
    reg                  [  20: 0]      state_n                    ;
    reg                  [   1: 0]      gf_op_mode_r               ;
    reg                  [   1: 0]      gf_pattern_mode_r          ;
    reg                                 gf_read_data_sel_r         ;
    reg                                 gf_write_data_sel_r        ;
    reg                                 march_y_sequence_r         ;
    reg                                 last_access_r              ;
    reg                  [   5: 0]      cnt_col_ns                 ;
    reg                                 row_open_r                 ;
    reg                  [  17: 0]      open_row_r                 ;
    reg                  [   1: 0]      open_bg_r                  ;
    reg                  [   1: 0]      open_ba_r                  ;

    reg                  [   9: 0]      cnt_act                    ;
    reg                  [   9: 0]      cnt_read                   ;
    reg                  [   9: 0]      cnt_write                  ;
    reg                  [   9: 0]      cnt_wtr_wait               ;
    reg                  [   9: 0]      cnt_precharge              ;
    reg                                 act_cnt_flag               ;
    reg                                 read_cnt_flag              ;
    reg                                 write_cnt_flag             ;
    reg                                 precharge_cnt_flag         ;
    reg                                 gf_end_flag                ;
    reg                  [   4: 0]      write_data_slot_r          ;
    reg                  [   1: 0]      gf_err_bg_r                ;
    reg                  [   1: 0]      gf_err_ba_r                ;
    reg                  [   3: 0]      rd_fifo_wr_ptr             ;
    reg                  [   3: 0]      rd_fifo_rd_ptr             ;
    reg                  [   4: 0]      rd_fifo_level              ;
    reg                  [   1: 0]      rd_fifo_bg       [0:15]    ;
    reg                  [   1: 0]      rd_fifo_ba       [0:15]    ;
    reg                  [  17: 0]      rd_fifo_row      [0:15]    ;
    reg                  [   5: 0]      rd_fifo_col      [0:15]    ;
    reg                  [   1: 0]      rd_fifo_pattern_mode[0:15] ;
    reg                                 compare_valid_r            ;
    reg                                 compare_window_r           ;
    reg                                 compare_mismatch_odd_r     ;
    reg                                 compare_mismatch_even_r    ;
    reg                  [  27: 0]      compare_access_addr_r      ;
    reg                  [  27: 0]      compare_access_addr_dly_r  ;
    reg                  [  15: 0]      compare_expected_beat_r    ;
    reg                  [  15: 0]      compare_expected_dly_r     ;
    reg                  [   1: 0]      compare_pattern_mode_r     ;
    reg                  [ 255: 0]      compare_burst_r            ;
    reg                                 r_ck_phase                 ;

/***************wire******************/
    wire                                gf_pass_start_pulse        ;
    wire                                act_cnt_run                ;
    wire                                read_cnt_run               ;
    wire                                write_cnt_run              ;
    wire                                wtr_wait_cnt_run           ;
    wire                                precharge_cnt_run          ;
    wire                                refresh_cnt_run            ;
    wire                                act_done                   ;
    wire                                read_done                  ;
    wire                                write_done                 ;
    wire                                wtr_wait_done              ;
    wire                                precharge_done             ;
    wire                                refresh_done               ;
    wire                                access_last                ;
    wire                                w_write_access_done        ;
    wire                                w_read_access_done         ;
    wire                                w_read_step_done           ;
    wire                                w_write_burst_done         ;
    wire                                w_final_precharge_done     ;
    wire                                w_refresh_due              ;
    wire                                w_access_in_open_row       ;
    wire                                w_sched_start_read         ;
    wire                                w_sched_start_write        ;
    wire                                w_stream_timer_clear       ;
    wire                                refresh_cnt_flag           ;
    wire                                refresh_due_r              ;
    wire                                w_refresh_cmd              ;
    wire                 [  28: 0]      cnt_refresh                ;
    wire                 [  28: 0]      cnt_refi                   ;
    wire                 [   3: 0]      w_refresh_credit           ;
    wire                 [   3: 0]      w_refresh_batch_num        ;
    wire                 [   3: 0]      w_refresh_batch_left       ;
    wire                 [   9: 0]      w_act_cmd_gap_cnt          ;
    wire                 [   9: 0]      w_rd_cmd_gap_cnt           ;
    wire                 [   9: 0]      w_wr_cmd_gap_cnt           ;
    wire                 [   9: 0]      w_pre_cmd_gap_cnt          ;
    wire                 [   9: 0]      w_act_cmd_gap_latched      ;
    wire                 [   9: 0]      w_rd_cmd_gap_latched       ;
    wire                 [   9: 0]      w_wr_cmd_gap_latched       ;
    wire                 [   9: 0]      w_pre_cmd_gap_latched      ;
    wire                 [   3: 0]      w_bank_start_index         ;
    wire                 [   3: 0]      w_bank_end_index           ;
    wire                 [   4: 0]      w_bank_count               ;
    wire                 [   4: 0]      w_bank_last_slot           ;
    wire                 [   9: 0]      w_act_last_gap_cnt         ;
    wire                 [   9: 0]      w_rd_last_gap_cnt          ;
    wire                 [   9: 0]      w_wr_last_gap_cnt          ;
    wire                 [   9: 0]      w_pre_last_gap_cnt         ;
    wire                 [   9: 0]      w_act_last_cmd_start_cnt   ;
    wire                 [   9: 0]      w_rd_last_cmd_start_cnt    ;
    wire                 [   9: 0]      w_wr_last_cmd_start_cnt    ;
    wire                 [   9: 0]      w_pre_last_cmd_start_cnt   ;
    wire                 [   9: 0]      w_act_done_cnt             ;
    wire                 [   9: 0]      w_precharge_done_cnt       ;
    wire                 [   9: 0]      w_stream_read_done_cnt     ;
    wire                 [   9: 0]      w_stream_write_done_cnt    ;
    wire                                w_bank_range_valid         ;
    wire                 [   4: 0]      w_write_payload_fire_slot  ;
    wire                 [   9: 0]      w_act_next_cmd_cnt_dbg     ;
    wire                 [   9: 0]      w_read_next_cmd_cnt_dbg    ;
    wire                 [   9: 0]      w_read_next_capture_cnt_dbg;
    wire                 [   9: 0]      w_write_next_cmd_cnt_dbg   ;
    wire                 [   9: 0]      w_write_next_payload_cnt_dbg;
    wire                 [   9: 0]      w_pre_next_cmd_cnt_dbg     ;
    wire                 [   9: 0]      w_read_capture_last_cnt    ;
    wire                 [   9: 0]      w_write_payload_last_cnt   ;
    wire                 [   9: 0]      w_write_payload_rel        ;
    wire                 [   4: 0]      w_act_cmd_slot             ;
    wire                 [   4: 0]      w_read_cmd_slot            ;
    wire                 [   4: 0]      w_read_capture_slot        ;
    wire                 [   4: 0]      w_write_cmd_slot           ;
    wire                 [   4: 0]      w_write_data_slot          ;
    wire                 [   4: 0]      w_write_payload_slot       ;
    wire                                w_act_cmd_first            ;
    wire                                w_act_cmd_second           ;
    wire                                w_read_cmd_first           ;
    wire                                w_read_cmd_second          ;
    wire                                w_read_capture_fire        ;
    wire                                w_write_cmd_first          ;
    wire                                w_write_cmd_second         ;
    wire                                w_write_payload_fire       ;
    wire                                w_precharge_cmd_first      ;
    wire                                w_act_cmd_done             ;
    wire                                w_read_cmd_done            ;
    wire                                w_read_capture_done        ;
    wire                                w_write_cmd_done           ;
    wire                                w_write_payload_done       ;
    wire                                w_precharge_cmd_done       ;
    wire                                w_read_fifo_push           ;
    wire                                w_read_fifo_pop            ;
    wire                                w_read_fifo_empty          ;
    wire                                w_read_fifo_full           ;
    wire                                add_cnt_col                ;
    wire                                end_cnt_col                ;
    wire                                add_cnt_col_ns             ;
    wire                                end_cnt_col_ns             ;
    wire                 [  10: 0]      w_wr_dq_oe_last_sum        ;
    wire                 [   9: 0]      w_wr_dq_oe_last_cnt        ;
    wire                                w_wr_dq_oe_active          ;
    wire                                w_wck_wr_active            ;
    wire                                w_wck_rd_active            ;
    wire                 [   9: 0]      w_read_sample_start_cnt    ;
    wire                 [  17: 0]      w_access_row               ;
    wire                 [   1: 0]      w_access_bg                ;
    wire                 [   1: 0]      w_access_ba                ;
    wire                 [   5: 0]      w_access_col               ;
    wire                 [   3: 0]      w_act_bank_index           ;
    wire                 [   3: 0]      w_read_bank_index          ;
    wire                 [   3: 0]      w_write_bank_index         ;
    wire                 [   3: 0]      w_write_data_bank_index    ;
    wire                 [   1: 0]      w_act_bg                   ;
    wire                 [   1: 0]      w_act_ba                   ;
    wire                 [   1: 0]      w_read_bg                  ;
    wire                 [   1: 0]      w_read_ba                  ;
    wire                 [   1: 0]      w_write_bg                 ;
    wire                 [   1: 0]      w_write_ba                 ;
    wire                 [   1: 0]      w_write_data_bg            ;
    wire                 [   1: 0]      w_write_data_ba            ;
    wire                 [  15: 0]      w_read_expected_beat       ;
    wire                 [  15: 0]      w_fifo_expected_beat       ;
    wire                 [   1: 0]      w_fifo_pattern_mode        ;
    wire                 [  27: 0]      w_fifo_access_addr         ;
    wire                                w_compare_pipe_busy        ;
    wire                                w_compare_mismatch         ;
    wire                 [  63: 0]      w_write_march_word         ;
    wire                 [   1: 0]      w_pattern_mode_cfg         ;

/***************component*************/
lpddr5_gf_refresh_ctrl #(
    .P_TRFCAB                      (TRFCab                    ),
    .P_T_REFI_CYCLES               (T_REFI_CYCLES             ),
    .P_CMD_START_CNT               (29'd3                     )
) lpddr5_gf_refresh_ctrl_u0 (
    .i_clk                         (clk                        ),
    .i_rst_n                       (rst_n                      ),
    .i_enable                      (gf_test_en                 ),
    .i_refresh_active              (state_c == GF_REFRESH      ),
    .i_ck_active                   (r_ck_phase                 ),
    .i_batch_num                   (gf_refresh_batch_num        ),
    .o_refresh_cnt                 (cnt_refresh                ),
    .o_refi_cnt                    (cnt_refi                   ),
    .o_refresh_cnt_flag            (refresh_cnt_flag           ),
    .o_refresh_due                 (refresh_due_r              ),
    .o_refresh_cmd                 (w_refresh_cmd              ),
    .o_refresh_done                (refresh_done               ),
    .o_refresh_credit              (w_refresh_credit           ),
    .o_refresh_batch_num           (w_refresh_batch_num        ),
    .o_refresh_batch_left          (w_refresh_batch_left       )
);

lpddr5_gf_stream_timer #(
    .P_SECOND_PULSE_EN             (1'b1                      ),
    .P_RESET_GAP_CNT               (GF_ACT_CMD_GAP_DFT        )
) lpddr5_gf_act_stream_u0 (
    .i_clk                         (clk                        ),
    .i_rst_n                       (rst_n                      ),
    .i_clear                       (w_stream_timer_clear       ),
    .i_stream_active               (state_c == GF_ACTIVATING   ),
    .i_cnt_run                     (act_cnt_run                ),
    .i_cnt                         (cnt_act                    ),
    .i_start_cnt                   (GF_CMD_START_CNT           ),
    .i_gap_cnt                     (w_act_cmd_gap_cnt          ),
    .i_last_slot                   (w_bank_last_slot           ),
    .o_gap_cnt                     (w_act_cmd_gap_latched      ),
    .o_slot                        (w_act_cmd_slot             ),
    .o_next_start_cnt              (w_act_next_cmd_cnt_dbg     ),
    .o_last_start_cnt              (w_act_last_cmd_start_cnt   ),
    .o_first                       (w_act_cmd_first            ),
    .o_second                      (w_act_cmd_second           ),
    .o_done                        (w_act_cmd_done             )
);

lpddr5_gf_stream_timer #(
    .P_SECOND_PULSE_EN             (1'b1                      ),
    .P_RESET_GAP_CNT               (GF_RD_CMD_GAP_DFT         )
) lpddr5_gf_read_cmd_stream_u0 (
    .i_clk                         (clk                        ),
    .i_rst_n                       (rst_n                      ),
    .i_clear                       (w_stream_timer_clear       ),
    .i_stream_active               (state_c == GF_READ         ),
    .i_cnt_run                     (read_cnt_run               ),
    .i_cnt                         (cnt_read                   ),
    .i_start_cnt                   (GF_CMD_START_CNT           ),
    .i_gap_cnt                     (w_rd_cmd_gap_cnt           ),
    .i_last_slot                   (w_bank_last_slot           ),
    .o_gap_cnt                     (w_rd_cmd_gap_latched       ),
    .o_slot                        (w_read_cmd_slot            ),
    .o_next_start_cnt              (w_read_next_cmd_cnt_dbg    ),
    .o_last_start_cnt              (w_rd_last_cmd_start_cnt    ),
    .o_first                       (w_read_cmd_first           ),
    .o_second                      (w_read_cmd_second          ),
    .o_done                        (w_read_cmd_done            )
);

lpddr5_gf_stream_timer #(
    .P_SECOND_PULSE_EN             (1'b0                      ),
    .P_RESET_GAP_CNT               (GF_RD_CMD_GAP_DFT         )
) lpddr5_gf_read_capture_stream_u0 (
    .i_clk                         (clk                        ),
    .i_rst_n                       (rst_n                      ),
    .i_clear                       (w_stream_timer_clear       ),
    .i_stream_active               (state_c == GF_READ         ),
    .i_cnt_run                     (read_cnt_run               ),
    .i_cnt                         (cnt_read                   ),
    .i_start_cnt                   (w_read_sample_start_cnt    ),
    .i_gap_cnt                     (w_rd_cmd_gap_cnt           ),
    .i_last_slot                   (w_bank_last_slot           ),
    .o_gap_cnt                     (                           ),
    .o_slot                        (w_read_capture_slot        ),
    .o_next_start_cnt              (w_read_next_capture_cnt_dbg),
    .o_last_start_cnt              (w_read_capture_last_cnt    ),
    .o_first                       (w_read_capture_fire        ),
    .o_second                      (                           ),
    .o_done                        (w_read_capture_done        )
);

lpddr5_gf_stream_timer #(
    .P_SECOND_PULSE_EN             (1'b1                      ),
    .P_RESET_GAP_CNT               (GF_WR_CMD_GAP_DFT         )
) lpddr5_gf_write_cmd_stream_u0 (
    .i_clk                         (clk                        ),
    .i_rst_n                       (rst_n                      ),
    .i_clear                       (w_stream_timer_clear       ),
    .i_stream_active               ((state_c == GF_WRITE) ||
                                    (state_c == GF_WRITE_AFTER_READ)),
    .i_cnt_run                     (write_cnt_run              ),
    .i_cnt                         (cnt_write                  ),
    .i_start_cnt                   (GF_CMD_START_CNT           ),
    .i_gap_cnt                     (w_wr_cmd_gap_cnt           ),
    .i_last_slot                   (w_bank_last_slot           ),
    .o_gap_cnt                     (w_wr_cmd_gap_latched       ),
    .o_slot                        (w_write_cmd_slot           ),
    .o_next_start_cnt              (w_write_next_cmd_cnt_dbg   ),
    .o_last_start_cnt              (w_wr_last_cmd_start_cnt    ),
    .o_first                       (w_write_cmd_first          ),
    .o_second                      (w_write_cmd_second         ),
    .o_done                        (w_write_cmd_done           )
);

lpddr5_gf_stream_timer #(
    .P_SECOND_PULSE_EN             (1'b0                      ),
    .P_RESET_GAP_CNT               (GF_WR_CMD_GAP_DFT         )
) lpddr5_gf_write_payload_stream_u0 (
    .i_clk                         (clk                        ),
    .i_rst_n                       (rst_n                      ),
    .i_clear                       (w_stream_timer_clear       ),
    .i_stream_active               ((state_c == GF_WRITE) ||
                                    (state_c == GF_WRITE_AFTER_READ)),
    .i_cnt_run                     (write_cnt_run              ),
    .i_cnt                         (cnt_write                  ),
    .i_start_cnt                   (GF_WR_PAYLOAD_START_CNT    ),
    .i_gap_cnt                     (w_wr_cmd_gap_cnt           ),
    .i_last_slot                   (w_bank_last_slot           ),
    .o_gap_cnt                     (                           ),
    .o_slot                        (w_write_payload_fire_slot  ),
    .o_next_start_cnt              (w_write_next_payload_cnt_dbg),
    .o_last_start_cnt              (w_write_payload_last_cnt  ),
    .o_first                       (w_write_payload_fire       ),
    .o_second                      (                           ),
    .o_done                        (w_write_payload_done       )
);

lpddr5_gf_stream_timer #(
    .P_SECOND_PULSE_EN             (1'b0                      ),
    .P_RESET_GAP_CNT               (GF_PRE_CMD_GAP_DFT        )
) lpddr5_gf_precharge_stream_u0 (
    .i_clk                         (clk                        ),
    .i_rst_n                       (rst_n                      ),
    .i_clear                       (w_stream_timer_clear       ),
    .i_stream_active               ((state_c == GF_PRECHARGING) ||
                                    (state_c == GF_PRE_REFRESH)),
    .i_cnt_run                     (precharge_cnt_run          ),
    .i_cnt                         (cnt_precharge              ),
    .i_start_cnt                   (GF_CMD_START_CNT           ),
    .i_gap_cnt                     (w_pre_cmd_gap_cnt          ),
    .i_last_slot                   (GF_PREAB_LAST_SLOT         ),
    .o_gap_cnt                     (w_pre_cmd_gap_latched      ),
    .o_slot                        (                           ),
    .o_next_start_cnt              (w_pre_next_cmd_cnt_dbg     ),
    .o_last_start_cnt              (w_pre_last_cmd_start_cnt   ),
    .o_first                       (w_precharge_cmd_first      ),
    .o_second                      (                           ),
    .o_done                        (w_precharge_cmd_done       )
);

assign w_read_sample_start_cnt = {2'b00, read_capture_start_cnt};
assign w_access_row            = (march_y_sequence_r == 1'b1) ? gf_cnt_row_ns : gf_cnt_row;
assign w_access_bg             = (march_y_sequence_r == 1'b1) ? GF_end_bg     : GF_start_bg;
assign w_access_ba             = (march_y_sequence_r == 1'b1) ? GF_end_ba     : GF_start_ba;
assign w_access_col            = (march_y_sequence_r == 1'b1) ? cnt_col_ns    : gf_cnt_col;
// BAR06 gaps are sampled into stream-local registers before each stream starts.
// The live BAR values are clipped here only for safety; command slot generation
// below is driven by registered next-count/slot pointers, not by a combinational
// gap lookup path.
assign w_act_cmd_gap_cnt       = (gf_act_cmd_gap_cnt == 10'd0) ?
                                 GF_ACT_CMD_GAP_DFT :
                                 ((gf_act_cmd_gap_cnt > GF_CMD_GAP_MAX) ?
                                  GF_CMD_GAP_MAX : gf_act_cmd_gap_cnt);
assign w_rd_cmd_gap_cnt        = (gf_rd_cmd_gap_cnt == 10'd0) ?
                                 GF_RD_CMD_GAP_DFT :
                                 ((gf_rd_cmd_gap_cnt > GF_CMD_GAP_MAX) ?
                                  GF_CMD_GAP_MAX : gf_rd_cmd_gap_cnt);
assign w_wr_cmd_gap_cnt        = (gf_wr_cmd_gap_cnt == 10'd0) ?
                                 GF_WR_CMD_GAP_DFT :
                                 ((gf_wr_cmd_gap_cnt > GF_CMD_GAP_MAX) ?
                                  GF_CMD_GAP_MAX : gf_wr_cmd_gap_cnt);
assign w_pre_cmd_gap_cnt       = (gf_pre_cmd_gap_cnt == 10'd0) ?
                                 GF_PRE_CMD_GAP_DFT :
                                 ((gf_pre_cmd_gap_cnt > GF_CMD_GAP_MAX) ?
                                  GF_CMD_GAP_MAX : gf_pre_cmd_gap_cnt);

assign w_bank_start_index      = gf_bank_index(GF_start_bg, GF_start_ba);
assign w_bank_end_index        = gf_bank_index(GF_end_bg,   GF_end_ba);
assign w_bank_range_valid      = (w_bank_end_index >= w_bank_start_index);
assign w_bank_count            = (w_bank_range_valid == 1'b1) ?
                                 ({1'b0, w_bank_end_index} -
                                  {1'b0, w_bank_start_index} + 5'd1) :
                                 5'd1;
assign w_bank_last_slot        = w_bank_count - 5'd1;
assign w_act_last_gap_cnt      = (w_act_last_cmd_start_cnt > GF_CMD_START_CNT) ?
                                 (w_act_last_cmd_start_cnt - GF_CMD_START_CNT) :
                                 10'd0;
assign w_rd_last_gap_cnt       = (w_rd_last_cmd_start_cnt > GF_CMD_START_CNT) ?
                                 (w_rd_last_cmd_start_cnt - GF_CMD_START_CNT) :
                                 10'd0;
assign w_wr_last_gap_cnt       = (w_wr_last_cmd_start_cnt > GF_CMD_START_CNT) ?
                                 (w_wr_last_cmd_start_cnt - GF_CMD_START_CNT) :
                                 10'd0;
assign w_pre_last_gap_cnt      = (w_pre_last_cmd_start_cnt > GF_CMD_START_CNT) ?
                                 (w_pre_last_cmd_start_cnt - GF_CMD_START_CNT) :
                                 10'd0;
assign w_act_done_cnt          = w_act_last_cmd_start_cnt + T_RCD - 10'd1;
assign w_precharge_done_cnt    = w_pre_last_cmd_start_cnt + T_RPab - 10'd1;
assign w_stream_read_done_cnt  = w_rd_last_cmd_start_cnt + gf_read_done_cnt;
assign w_stream_write_done_cnt = w_wr_last_cmd_start_cnt + gf_write_done_cnt;
assign w_wr_dq_oe_last_sum     = {1'b0, w_wr_last_gap_cnt} +
                                 {1'b0, gf_wr_wck_last_cnt} +
                                 {1'b0, GF_WR_OE_POST_CNT};
assign w_wr_dq_oe_last_cnt     = (w_wr_dq_oe_last_sum > 11'd1023) ?
                                 10'h3ff :
                                 w_wr_dq_oe_last_sum[9:0];

assign w_stream_timer_clear    = (gf_test_en == 1'b0) ||
                                 (gf_pass_start == 1'b0);
assign w_write_payload_slot    = w_write_data_slot;
assign w_write_payload_rel     = (w_write_payload_fire == 1'b1) ?
                                 10'd0 :
                                 ((cnt_write >= w_write_payload_last_cnt) ?
                                  (cnt_write - w_write_payload_last_cnt) :
                                  10'h3ff);
assign w_write_data_slot       = (write_cnt_run &&
                                  (w_write_payload_done == 1'b0) &&
                                  (w_write_payload_fire == 1'b1)) ?
                                 w_write_payload_fire_slot :
                                 write_data_slot_r;

assign w_act_bank_index        = gf_stream_bank_index(march_y_sequence_r,
                                                       w_bank_start_index,
                                                       w_bank_end_index,
                                                       w_act_cmd_slot);
assign w_read_bank_index       = gf_stream_bank_index(march_y_sequence_r,
                                                       w_bank_start_index,
                                                       w_bank_end_index,
                                                       w_read_cmd_slot);
assign w_write_bank_index      = gf_stream_bank_index(march_y_sequence_r,
                                                       w_bank_start_index,
                                                       w_bank_end_index,
                                                       w_write_cmd_slot);
assign w_write_data_bank_index = gf_stream_bank_index(march_y_sequence_r,
                                                       w_bank_start_index,
                                                       w_bank_end_index,
                                                       w_write_data_slot);
assign w_act_bg                = gf_bank_bg(w_act_bank_index);
assign w_act_ba                = gf_bank_ba(w_act_bank_index);
assign w_read_bg               = gf_bank_bg(w_read_bank_index);
assign w_read_ba               = gf_bank_ba(w_read_bank_index);
assign w_write_bg              = gf_bank_bg(w_write_bank_index);
assign w_write_ba              = gf_bank_ba(w_write_bank_index);
assign w_write_data_bg         = gf_bank_bg(w_write_data_bank_index);
assign w_write_data_ba         = gf_bank_ba(w_write_data_bank_index);

assign w_pattern_mode_cfg      = (gf_pattern_mode_cfg == GF_PATTERN_WRITE_STRESS) ?
                                 GF_PATTERN_WRITE_STRESS : GF_PATTERN_ADDR_TOGGLE;
assign w_read_expected_beat    = gf_pattern_beat(gf_pattern_mode_r,
                                                  gf_read_data_sel_r,
                                                  w_access_row,
                                                  w_read_bg,
                                                  w_read_ba,
                                                  w_access_col,
                                                  16'd0);
assign w_read_fifo_empty       = (rd_fifo_level == 5'd0);
assign w_read_fifo_full        = (rd_fifo_level >= GF_READ_FIFO_DEPTH);
assign w_read_fifo_push        = w_read_cmd_first && (w_read_fifo_full == 1'b0);
assign w_read_fifo_pop         = (state_c == GF_READ) &&
                                 dq_a_burst_valid &&
                                 (w_read_fifo_empty == 1'b0);
assign w_compare_pipe_busy     = (compare_valid_r == 1'b1) ||
                                 (compare_window_r == 1'b1);
// Keep compare data derived from the FIFO address so addr/expected cannot
// diverge on the first read response after a stream boundary.
assign w_fifo_pattern_mode     = (w_read_fifo_empty == 1'b0) ?
                                 rd_fifo_pattern_mode[rd_fifo_rd_ptr] :
                                 gf_pattern_mode_r;
assign w_fifo_expected_beat    = (w_read_fifo_empty == 1'b0) ?
                                 gf_pattern_beat(w_fifo_pattern_mode,
                                                 gf_read_data_sel_r,
                                                 rd_fifo_row[rd_fifo_rd_ptr],
                                                 rd_fifo_bg[rd_fifo_rd_ptr],
                                                 rd_fifo_ba[rd_fifo_rd_ptr],
                                                 rd_fifo_col[rd_fifo_rd_ptr],
                                                 16'd0) :
                                 w_read_expected_beat;
assign w_fifo_access_addr      = (w_read_fifo_empty == 1'b0) ?
                                 {rd_fifo_ba[rd_fifo_rd_ptr],
                                  rd_fifo_bg[rd_fifo_rd_ptr],
                                  rd_fifo_row[rd_fifo_rd_ptr],
                                  rd_fifo_col[rd_fifo_rd_ptr]} :
                                 {w_access_ba, w_access_bg,
                                  w_access_row, w_access_col};
assign w_wr_dq_oe_active       = ((state_c == GF_WRITE) ||
                                 (state_c == GF_WRITE_AFTER_READ)) &&
                                 (cnt_write >= GF_WR_OE_START_CNT) &&
                                 (cnt_write <= w_wr_dq_oe_last_cnt);
assign w_wck_wr_active         = ((state_c == GF_WRITE) ||
                                   (state_c == GF_WRITE_AFTER_READ)) &&
                                 (cnt_write >= gf_wr_wck_start_cnt) &&
                                 ((w_write_cmd_done == 1'b0) ||
                                  (cnt_write <= (w_wr_last_gap_cnt + gf_wr_wck_last_cnt)));
assign w_wck_rd_active         = (state_c == GF_READ) &&
                                 (cnt_read >= gf_rd_wck_start_cnt) &&
                                 ((w_read_cmd_done == 1'b0) ||
                                  (cnt_read <= (w_rd_last_gap_cnt + gf_rd_wck_last_cnt)));
assign w_write_march_word      = gf_pattern_word(gf_pattern_mode_r,
                                                  gf_write_data_sel_r,
                                                  w_access_row,
                                                  w_write_data_bg,
                                                  w_write_data_ba,
                                                  w_access_col,
                                                  w_write_payload_rel);

//  assign w_write_march_word        = gf_write_window_word(cnt_write);

/***************assign****************/
assign gf_pass_start_pulse = gf_test_en &&
                             gf_pass_start &&
                             !gf_pass_start_d &&
                             !engine_inhibit;

assign act_cnt_run        = (state_c == GF_ACTIVATING) && act_cnt_flag;
assign act_done           = act_cnt_run &&
                            (w_act_cmd_done == 1'b1) &&
                            (cnt_act >= w_act_done_cnt);

assign read_cnt_run       = (state_c == GF_READ)        && read_cnt_flag;
assign read_done          = read_cnt_run &&
                            (w_read_cmd_done == 1'b1) &&
                            (w_read_capture_done == 1'b1) &&
                            (cnt_read >= w_stream_read_done_cnt) &&
                            (w_read_fifo_empty == 1'b1) &&
                            (w_compare_pipe_busy == 1'b0);

assign write_cnt_run      = ((state_c == GF_WRITE) ||
                             (state_c == GF_WRITE_AFTER_READ)) &&
                            write_cnt_flag;
assign write_done         = write_cnt_run &&
                            (w_write_cmd_done == 1'b1) &&
                            (w_write_payload_done == 1'b1) &&
                            (cnt_write >= w_stream_write_done_cnt);

assign wtr_wait_cnt_run   = (state_c == GF_WTR_WAIT);
assign wtr_wait_done      = wtr_wait_cnt_run && (cnt_wtr_wait >= (GF_WTR_WAIT_CNT - 10'd1));

assign precharge_cnt_run  = ((state_c == GF_PRECHARGING) ||
                             (state_c == GF_PRE_REFRESH)) &&
                            precharge_cnt_flag;
assign refresh_cnt_run    = (state_c == GF_REFRESH)     && refresh_cnt_flag;
assign precharge_done     = precharge_cnt_run &&
                            (w_precharge_cmd_done == 1'b1) &&
                            (cnt_precharge >= w_precharge_done_cnt);
assign w_write_burst_done = gf_en_write && write_done;
assign w_write_access_done = gf_en_write && write_done;
assign w_read_step_done   = gf_en_read && read_done;
assign w_read_access_done = w_read_step_done && (gf_op_mode_r == GF_OP_READ_ONLY);
assign w_final_precharge_done = (state_c == GF_PRECHARGING) &&
                                precharge_done &&
                                (last_access_r == 1'b1);
assign w_refresh_due      = (GF_ROW_REFRESH_EN == 1'b1) &&
                            (refresh_due_r == 1'b1);
assign w_access_in_open_row = (row_open_r == 1'b1) &&
                              (open_row_r == w_access_row);
assign w_sched_start_read  = (state_c == GF_SCHED) &&
                             (last_access_r == 1'b0) &&
                             (row_open_r == 1'b1) &&
                             (w_access_in_open_row == 1'b1) &&
                             (w_refresh_due == 1'b0) &&
                             ((gf_op_mode_r == GF_OP_READ_ONLY) ||
                              (gf_op_mode_r == GF_OP_READ_WRITE));
assign w_sched_start_write = (state_c == GF_SCHED) &&
                             (last_access_r == 1'b0) &&
                             (row_open_r == 1'b1) &&
                             (w_access_in_open_row == 1'b1) &&
                             (w_refresh_due == 1'b0) &&
                             (gf_op_mode_r == GF_OP_WRITE_ONLY);
assign add_cnt_col        = !march_y_sequence_r &&
                            (w_write_access_done || w_read_access_done);
assign end_cnt_col        = add_cnt_col && (gf_cnt_col >= GF_end_col);
assign add_cnt_col_ns     = march_y_sequence_r &&
                            (w_write_access_done || w_read_access_done);
assign end_cnt_col_ns     = add_cnt_col_ns && (cnt_col_ns <= GF_start_col);
assign access_last        = (!march_y_sequence_r &&
                             (gf_cnt_col >= GF_end_col) &&
                             (gf_cnt_row >= GF_end_row)) ||
                            ( march_y_sequence_r &&
                             (cnt_col_ns <= GF_start_col) &&
                             (gf_cnt_row_ns <= GF_start_row));
assign gf_state                 = state_c;
assign rx_dq_capture_en         = w_read_capture_fire;
assign gf_cnt_read_value        = cnt_read;
assign gf_cnt_write_value       = cnt_write;
assign gf_access_addr           = (compare_window_r == 1'b1) ?
                                  compare_access_addr_dly_r :
                                  w_fifo_access_addr;
assign gf_read_expected_beat    = (compare_window_r == 1'b1) ?
                                  compare_expected_dly_r :
                                  w_fifo_expected_beat;
assign gf_compare_window        = compare_window_r;
assign gf_compare_mismatch_odd  = compare_mismatch_odd_r;
assign gf_compare_mismatch_even = compare_mismatch_even_r;
assign w_compare_mismatch       = (compare_window_r == 1'b1) &&
                                  ((compare_mismatch_odd_r == 1'b1) ||
                                   (compare_mismatch_even_r == 1'b1));

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        gf_pass_start_d <= 1'b0;
    end
    else if (!gf_test_en) begin
        gf_pass_start_d <= 1'b0;
    end
    else begin
        gf_pass_start_d <= gf_pass_start;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        gf_op_mode_r <= GF_OP_WRITE_ONLY;
    else if (!gf_test_en)
        gf_op_mode_r <= GF_OP_WRITE_ONLY;
    else
        gf_op_mode_r <= gf_op_mode;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        gf_pattern_mode_r <= GF_PATTERN_ADDR_TOGGLE;
    else if (!gf_test_en)
        gf_pattern_mode_r <= GF_PATTERN_ADDR_TOGGLE;
    else if (gf_pass_start_pulse == 1'b1)
        gf_pattern_mode_r <= w_pattern_mode_cfg;
    else
        gf_pattern_mode_r <= gf_pattern_mode_r;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        gf_read_data_sel_r <= 1'b0;
    else if (!gf_test_en)
        gf_read_data_sel_r <= 1'b0;
    else
        gf_read_data_sel_r <= gf_read_data_sel;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        gf_write_data_sel_r <= 1'b0;
    else if (!gf_test_en)
        gf_write_data_sel_r <= 1'b0;
    else
        gf_write_data_sel_r <= gf_write_data_sel;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        march_y_sequence_r <= 1'b0;
    else if (!gf_test_en)
        march_y_sequence_r <= 1'b0;
    else
        march_y_sequence_r <= march_y_sequence;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        gf_pass_done <= 1'b0;
    end
    else if (!gf_test_en) begin
        gf_pass_done <= 1'b0;
    end
    else if (gf_end_flag) begin
        gf_pass_done <= 1'b1;
    end
    else begin
        gf_pass_done <= 1'b0;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        gf_end_flag <= 1'b0;
    end
    else if (!gf_test_en) begin
        gf_end_flag <= 1'b0;
    end
    else if (w_final_precharge_done) begin
        gf_end_flag <= 1'b1;
    end
    else begin
        gf_end_flag <= 1'b0;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state_c <= GF_IDLE;
    end
    else if (!gf_test_en) begin
        state_c <= GF_IDLE;
    end
    else if (gf_pass_start == 1'b0) begin
        state_c <= GF_IDLE;
    end
    else begin
        state_c <= state_n;
    end
end

always @(*) begin
    case (state_c)
        GF_IDLE: begin
            if ((gf_end_flag == 1'b1) || (gf_pass_done == 1'b1))
                state_n = GF_IDLE;
            else if ((gf_pass_start_d == 1'b1) && (engine_inhibit == 1'b0))
                state_n = GF_SCHED;
            else
                state_n = GF_IDLE;
        end

        GF_SCHED: begin
            if ((last_access_r == 1'b1) && (row_open_r == 1'b1))
                state_n = GF_PRECHARGING;
            else if (last_access_r == 1'b1)
                state_n = GF_IDLE;
            else if ((w_refresh_due == 1'b1) && (row_open_r == 1'b1))
                state_n = GF_PRE_REFRESH;
            else if (w_refresh_due == 1'b1)
                state_n = GF_REFRESH;
            else if (row_open_r == 1'b0)
                state_n = GF_ACTIVATING;
            else if (w_access_in_open_row == 1'b0)
                state_n = GF_PRECHARGING;
            else if (gf_op_mode_r == GF_OP_WRITE_ONLY)
                state_n = GF_WRITE;
            else if ((gf_op_mode_r == GF_OP_READ_ONLY) ||
                     (gf_op_mode_r == GF_OP_READ_WRITE))
                state_n = GF_READ;
            else
                state_n = GF_SCHED;
        end

        GF_ACTIVATING: begin
            if (act_done)
                state_n = GF_SCHED;
            else
                state_n = GF_ACTIVATING;
        end

        GF_READ: begin
            if (w_read_step_done && (gf_op_mode_r == GF_OP_READ_WRITE))
                state_n = GF_WTR_WAIT;
            else if (w_read_access_done)
                state_n = GF_SCHED;
            else
                state_n = GF_READ;
        end

        GF_WRITE: begin
            if (w_write_access_done)
                state_n = GF_SCHED;
            else
                state_n = GF_WRITE;
        end

        GF_WRITE_AFTER_READ: begin
            if (w_write_access_done)
                state_n = GF_SCHED;
            else
                state_n = GF_WRITE_AFTER_READ;
        end

        GF_WTR_WAIT: begin
            if (wtr_wait_done)
                state_n = GF_WRITE_AFTER_READ;
            else
                state_n = GF_WTR_WAIT;
        end

        GF_PRECHARGING: begin
            if (precharge_done && (last_access_r == 1'b1))
                state_n = GF_IDLE;
            else if (precharge_done)
                state_n = GF_SCHED;
            else
                state_n = GF_PRECHARGING;
        end

        GF_PRE_REFRESH: begin
            if (precharge_done)
                state_n = GF_REFRESH;
            else
                state_n = GF_PRE_REFRESH;
        end

        GF_REFRESH: begin
            if (refresh_done)
                state_n = GF_SCHED;
            else
                state_n = GF_REFRESH;
        end

        default: begin
            state_n = GF_IDLE;
        end
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0)
        write_data_slot_r <= 5'd0;
    else if (w_stream_timer_clear == 1'b1)
        write_data_slot_r <= 5'd0;
    else if ((state_c != GF_WRITE) &&
             (state_c != GF_WRITE_AFTER_READ))
        write_data_slot_r <= 5'd0;
    else if (w_write_payload_fire == 1'b1)
        write_data_slot_r <= w_write_payload_fire_slot;
    else
        write_data_slot_r <= write_data_slot_r;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        cnt_act <= 10'd0;
    else if (state_c != GF_ACTIVATING)
        cnt_act <= 10'd0;
    else if (act_cnt_run) begin
        if (act_done)
            cnt_act <= 10'd0;
        else
            cnt_act <= cnt_act + 10'd1;
    end
    else
        cnt_act <= cnt_act;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        act_cnt_flag <= 1'b0;
    else if (act_done)
        act_cnt_flag <= 1'b0;
    else if ((r_ck_phase == 1'b1) && (state_c == GF_ACTIVATING))
        act_cnt_flag <= 1'b1;
    else
        act_cnt_flag <= act_cnt_flag;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        cnt_read <= 10'd0;
    else if (state_c != GF_READ)
        cnt_read <= 10'd0;
    else if (read_cnt_run) begin
        if (read_done)
            cnt_read <= 10'd0;
        else
            cnt_read <= cnt_read + 10'd1;
    end
    else
        cnt_read <= cnt_read;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        read_cnt_flag <= 1'b0;
    else if (read_done)
        read_cnt_flag <= 1'b0;
    else if ((r_ck_phase == 1'b1) && (state_c == GF_READ))
        read_cnt_flag <= 1'b1;
    else
        read_cnt_flag <= read_cnt_flag;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        cnt_write <= 10'd0;
    else if ((state_c != GF_WRITE) && (state_c != GF_WRITE_AFTER_READ))
        cnt_write <= 10'd0;
    else if (write_cnt_run) begin
        if (write_done)
            cnt_write <= 10'd0;
        else
            cnt_write <= cnt_write + 10'd1;
    end
    else
        cnt_write <= cnt_write;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        write_cnt_flag <= 1'b0;
    else if (write_done)
        write_cnt_flag <= 1'b0;
    else if ((r_ck_phase == 1'b1) &&
             ((state_c == GF_WRITE) || (state_c == GF_WRITE_AFTER_READ)))
        write_cnt_flag <= 1'b1;
    else
        write_cnt_flag <= write_cnt_flag;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        cnt_wtr_wait <= 10'd0;
    else if (state_c != GF_WTR_WAIT)
        cnt_wtr_wait <= 10'd0;
    else if (wtr_wait_done)
        cnt_wtr_wait <= 10'd0;
    else
        cnt_wtr_wait <= cnt_wtr_wait + 10'd1;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        cnt_precharge <= 10'd0;
    else if ((state_c != GF_PRECHARGING) && (state_c != GF_PRE_REFRESH))
        cnt_precharge <= 10'd0;
    else if (precharge_cnt_run) begin
        if (precharge_done)
            cnt_precharge <= 10'd0;
        else
            cnt_precharge <= cnt_precharge + 10'd1;
    end
    else
        cnt_precharge <= cnt_precharge;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        precharge_cnt_flag <= 1'b0;
    else if (precharge_done)
        precharge_cnt_flag <= 1'b0;
    else if ((r_ck_phase == 1'b1) &&
             ((state_c == GF_PRECHARGING) || (state_c == GF_PRE_REFRESH)))
        precharge_cnt_flag <= 1'b1;
    else
        precharge_cnt_flag <= precharge_cnt_flag;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        row_open_r <= 1'b0;
    else if (!gf_test_en)
        row_open_r <= 1'b0;
    else if (gf_pass_start == 1'b0)
        row_open_r <= 1'b0;
    else if (gf_pass_start_pulse)
        row_open_r <= 1'b0;
    else if (precharge_done)
        row_open_r <= 1'b0;
    else if (act_done)
        row_open_r <= 1'b1;
    else
        row_open_r <= row_open_r;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        open_row_r <= 18'd0;
    else if (!gf_test_en)
        open_row_r <= 18'd0;
    else if (act_done)
        open_row_r <= w_access_row;
    else
        open_row_r <= open_row_r;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        open_bg_r <= 2'd0;
    else if (!gf_test_en)
        open_bg_r <= 2'd0;
    else if (act_done)
        open_bg_r <= w_access_bg;
    else
        open_bg_r <= open_bg_r;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        open_ba_r <= 2'd0;
    else if (!gf_test_en)
        open_ba_r <= 2'd0;
    else if (act_done)
        open_ba_r <= w_access_ba;
    else
        open_ba_r <= open_ba_r;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        gf_en_write <= 1'b0;
    else if (!gf_test_en || !gf_pass_start)
        gf_en_write <= 1'b0;
    else if (!gf_pass_start_d)
        gf_en_write <= 1'b0;
    else if (w_final_precharge_done)
        gf_en_write <= 1'b0;
    else if (w_write_burst_done)
        gf_en_write <= 1'b0;
    else if (w_sched_start_write == 1'b1)
        gf_en_write <= 1'b1;
    else if ((state_c == GF_WTR_WAIT) && (wtr_wait_done == 1'b1))
        gf_en_write <= 1'b1;
    else if ((state_c == GF_WRITE_AFTER_READ) && (r_ck_phase == 1'b0))
        gf_en_write <= 1'b1;
    else
        gf_en_write <= gf_en_write;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        gf_en_read <= 1'b0;
    else if (!gf_test_en || !gf_pass_start)
        gf_en_read <= 1'b0;
    else if (!gf_pass_start_d)
        gf_en_read <= 1'b0;
    else if (w_final_precharge_done)
        gf_en_read <= 1'b0;
    else if (read_done)
        gf_en_read <= 1'b0;
    else if (w_sched_start_read == 1'b1)
        gf_en_read <= 1'b1;
    else
        gf_en_read <= gf_en_read;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rd_fifo_wr_ptr <= 4'd0;
        rd_fifo_rd_ptr <= 4'd0;
        rd_fifo_level  <= 5'd0;
    end
    else if (!gf_test_en || !gf_pass_start) begin
        rd_fifo_wr_ptr <= 4'd0;
        rd_fifo_rd_ptr <= 4'd0;
        rd_fifo_level  <= 5'd0;
    end
    else if (gf_pass_start_pulse) begin
        rd_fifo_wr_ptr <= 4'd0;
        rd_fifo_rd_ptr <= 4'd0;
        rd_fifo_level  <= 5'd0;
    end
    else begin
        if (w_read_fifo_push == 1'b1) begin
            rd_fifo_bg[rd_fifo_wr_ptr]       <= w_read_bg;
            rd_fifo_ba[rd_fifo_wr_ptr]       <= w_read_ba;
            rd_fifo_row[rd_fifo_wr_ptr]      <= w_access_row;
            rd_fifo_col[rd_fifo_wr_ptr]      <= w_access_col;
            rd_fifo_pattern_mode[rd_fifo_wr_ptr] <= gf_pattern_mode_r;
            rd_fifo_wr_ptr                  <= rd_fifo_wr_ptr + 4'd1;
        end
        else begin
            rd_fifo_wr_ptr <= rd_fifo_wr_ptr;
        end

        if (w_read_fifo_pop == 1'b1)
            rd_fifo_rd_ptr <= rd_fifo_rd_ptr + 4'd1;
        else
            rd_fifo_rd_ptr <= rd_fifo_rd_ptr;

        if ((w_read_fifo_push == 1'b1) && (w_read_fifo_pop == 1'b0))
            rd_fifo_level <= rd_fifo_level + 5'd1;
        else if ((w_read_fifo_push == 1'b0) && (w_read_fifo_pop == 1'b1))
            rd_fifo_level <= rd_fifo_level - 5'd1;
        else
            rd_fifo_level <= rd_fifo_level;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) begin
        compare_valid_r  <= 1'b0;
        compare_window_r <= 1'b0;
    end
    else if ((gf_test_en == 1'b0) || (gf_pass_start == 1'b0)) begin
        compare_valid_r  <= 1'b0;
        compare_window_r <= 1'b0;
    end
    else if (gf_pass_start_pulse == 1'b1) begin
        compare_valid_r  <= 1'b0;
        compare_window_r <= 1'b0;
    end
    else begin
        compare_valid_r  <= w_read_fifo_pop;
        compare_window_r <= compare_valid_r;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) begin
        compare_access_addr_r   <= 28'd0;
        compare_expected_beat_r <= 16'd0;
        compare_pattern_mode_r  <= GF_PATTERN_ADDR_TOGGLE;
        compare_burst_r         <= 256'd0;
    end
    else if ((gf_test_en == 1'b0) || (gf_pass_start == 1'b0)) begin
        compare_access_addr_r   <= 28'd0;
        compare_expected_beat_r <= 16'd0;
        compare_pattern_mode_r  <= GF_PATTERN_ADDR_TOGGLE;
        compare_burst_r         <= 256'd0;
    end
    else if (gf_pass_start_pulse == 1'b1) begin
        compare_access_addr_r   <= 28'd0;
        compare_expected_beat_r <= 16'd0;
        compare_pattern_mode_r  <= GF_PATTERN_ADDR_TOGGLE;
        compare_burst_r         <= 256'd0;
    end
    else if (w_read_fifo_pop == 1'b1) begin
        compare_access_addr_r   <= w_fifo_access_addr;
        compare_expected_beat_r <= w_fifo_expected_beat;
        compare_pattern_mode_r  <= w_fifo_pattern_mode;
        compare_burst_r         <= dq_a_burst_flat;
    end
    else begin
        compare_access_addr_r   <= compare_access_addr_r;
        compare_expected_beat_r <= compare_expected_beat_r;
        compare_pattern_mode_r  <= compare_pattern_mode_r;
        compare_burst_r         <= compare_burst_r;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) begin
        compare_access_addr_dly_r <= 28'd0;
        compare_expected_dly_r    <= 16'd0;
    end
    else if ((gf_test_en == 1'b0) || (gf_pass_start == 1'b0)) begin
        compare_access_addr_dly_r <= 28'd0;
        compare_expected_dly_r    <= 16'd0;
    end
    else if (gf_pass_start_pulse == 1'b1) begin
        compare_access_addr_dly_r <= 28'd0;
        compare_expected_dly_r    <= 16'd0;
    end
    else if (compare_valid_r == 1'b1) begin
        compare_access_addr_dly_r <= compare_access_addr_r;
        compare_expected_dly_r    <= compare_expected_beat_r;
    end
    else begin
        compare_access_addr_dly_r <= compare_access_addr_dly_r;
        compare_expected_dly_r    <= compare_expected_dly_r;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) begin
        compare_mismatch_odd_r  <= 1'b0;
        compare_mismatch_even_r <= 1'b0;
    end
    else if ((gf_test_en == 1'b0) || (gf_pass_start == 1'b0)) begin
        compare_mismatch_odd_r  <= 1'b0;
        compare_mismatch_even_r <= 1'b0;
    end
    else if (gf_pass_start_pulse == 1'b1) begin
        compare_mismatch_odd_r  <= 1'b0;
        compare_mismatch_even_r <= 1'b0;
    end
    else if (compare_valid_r == 1'b1) begin
        compare_mismatch_odd_r  <= gf_pattern_mismatch(
            compare_burst_r,
            compare_pattern_mode_r,
            gf_read_data_sel_r,
            compare_access_addr_r[23:6],
            compare_access_addr_r[25:24],
            compare_access_addr_r[27:26],
            compare_access_addr_r[5:0],
            1'b1
        );
        compare_mismatch_even_r <= gf_pattern_mismatch(
            compare_burst_r,
            compare_pattern_mode_r,
            gf_read_data_sel_r,
            compare_access_addr_r[23:6],
            compare_access_addr_r[25:24],
            compare_access_addr_r[27:26],
            compare_access_addr_r[5:0],
            1'b0
        );
    end
    else begin
        compare_mismatch_odd_r  <= 1'b0;
        compare_mismatch_even_r <= 1'b0;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        gf_cnt_col    <= 6'd0;
        gf_cnt_row    <= 18'd0;
        gf_cnt_ba     <= 2'd0;
        gf_cnt_bg     <= 2'd0;
        cnt_col_ns    <= 6'd0;
        gf_cnt_row_ns <= 18'd0;
        last_access_r <= 1'b0;
    end
    else if (gf_pass_start_pulse) begin
        gf_cnt_col    <= GF_start_col;
        gf_cnt_row    <= GF_start_row;
        gf_cnt_ba     <= GF_start_ba;
        gf_cnt_bg     <= GF_start_bg;
        cnt_col_ns    <= GF_end_col;
        gf_cnt_row_ns <= GF_end_row;
        last_access_r <= 1'b0;
    end
    else if (w_final_precharge_done) begin
        last_access_r <= 1'b0;
    end
    else if (refresh_done && last_access_r) begin
        last_access_r <= 1'b0;
    end
    else if (w_write_access_done) begin
        last_access_r <= access_last;

        if (!march_y_sequence_r) begin
            if (gf_cnt_col >= GF_end_col) begin
                gf_cnt_col <= GF_start_col;
                if (gf_cnt_row >= GF_end_row) begin
                    gf_cnt_row <= GF_start_row;
                end
                else begin
                    gf_cnt_row <= gf_cnt_row + 18'd1;
                end
            end
            else begin
                gf_cnt_col <= gf_cnt_col + 6'd1;
            end
        end
        else begin
            if (cnt_col_ns <= GF_start_col) begin
                cnt_col_ns <= GF_end_col;
                if (gf_cnt_row_ns <= GF_start_row) begin
                    gf_cnt_row_ns <= GF_end_row;
                end
                else begin
                    gf_cnt_row_ns <= gf_cnt_row_ns - 18'd1;
                end
            end
            else begin
                cnt_col_ns <= cnt_col_ns - 6'd1;
            end
        end
    end
    else if (w_read_access_done) begin
        last_access_r <= access_last;

        if (!march_y_sequence_r) begin
            if (gf_cnt_col >= GF_end_col) begin
                gf_cnt_col <= GF_start_col;
                if (gf_cnt_row >= GF_end_row) begin
                    gf_cnt_row <= GF_start_row;
                end
                else begin
                    gf_cnt_row <= gf_cnt_row + 18'd1;
                end
            end
            else begin
                gf_cnt_col <= gf_cnt_col + 6'd1;
            end
        end
        else begin
            if (cnt_col_ns <= GF_start_col) begin
                cnt_col_ns <= GF_end_col;
                if (gf_cnt_row_ns <= GF_start_row) begin
                    gf_cnt_row_ns <= GF_end_row;
                end
                else begin
                    gf_cnt_row_ns <= gf_cnt_row_ns - 18'd1;
                end
            end
            else begin
                cnt_col_ns <= cnt_col_ns - 6'd1;
            end
        end
    end
end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            gf_err_flag <= 1'b0;
        else if (state_c == GF_IDLE)
            gf_err_flag <= 1'b0;
        else if (w_compare_mismatch)
            gf_err_flag <= 1'b1;
        else
            gf_err_flag <= 1'b0;
        end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gf_err_bg_r <= 2'd0;
            gf_err_ba_r <= 2'd0;
        end
        else if (gf_pass_start_pulse) begin
            gf_err_bg_r <= GF_start_bg;
            gf_err_ba_r <= GF_start_ba;
        end
        else if (w_compare_mismatch == 1'b1) begin
            gf_err_bg_r <= compare_access_addr_dly_r[25:24];
            gf_err_ba_r <= compare_access_addr_dly_r[27:26];
        end
        else begin
            gf_err_bg_r <= gf_err_bg_r;
            gf_err_ba_r <= gf_err_ba_r;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            err_cnt_GF <= 32'd0;
        else if (gf_pass_start_pulse)
            err_cnt_GF <= 32'd0;
        else if (gf_err_flag)
            err_cnt_GF <= err_cnt_GF + 32'd1;
        end

    // Keep CK stopped after IDD6 until the next GF pass starts explicitly.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            wave_ck_a_run_en <= 1'b1;
        else if (idd_ck_stop)
            wave_ck_a_run_en <= 1'b0;
        else if (gf_pass_start_pulse)
            wave_ck_a_run_en <= 1'b1;
        else
            wave_ck_a_run_en <= wave_ck_a_run_en;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            r_ck_phase <= 1'b0;
        else if (idd_ck_stop)
            r_ck_phase <= 1'b0;
        else if (gf_pass_start_pulse)
            r_ck_phase <= 1'b0;
        else if (wave_ck_a_run_en)
            r_ck_phase <= ~r_ck_phase;
        else
            r_ck_phase <= r_ck_phase;
    end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wave_cs_a_0_fall      <= 1'b0;
        wave_cs_a_0_rise      <= 1'b0;
        wave_ca_a_fall        <= 7'h00;
        wave_ca_a_rise        <= 7'h00;
        wave_wck_a_run_en   <= 2'b00;
        wave_wck_a_phase    <= 2'b00;
    end
    else begin
        wave_cs_a_0_fall      <= 1'b0;
        wave_cs_a_0_rise      <= 1'b0;
        wave_ca_a_fall        <= 7'h00;
        wave_ca_a_rise        <= 7'h00;
        wave_wck_a_run_en   <= 2'b00;
        wave_wck_a_phase    <= 2'b00;

        case (state_c)
            GF_ACTIVATING: begin
                if (w_act_cmd_first == 1'b1) begin
                    wave_cs_a_0_fall <= 1'b1;
                    wave_cs_a_0_rise <= 1'b1;
                    // ACT-1 R1. JEDEC prints the CA table CA0-first, so
                    // row "H H H R14..R17" = literal {R17..R14, 3'b111}.
                    // Byte-identical to the silicon-proven autu 400M GF.
                    wave_ca_a_rise <= {w_access_row[17:14], 3'b111};
                    wave_ca_a_fall <= {w_access_row[13:11], w_act_bg, w_act_ba};
                end
                else if (w_act_cmd_second == 1'b1) begin
                    wave_cs_a_0_fall <= 1'b1;
                    wave_cs_a_0_rise <= 1'b1;
                    // ACT-2 R1: JEDEC CA0-first row "H H L R7..R10"
                    // = literal {R10..R7, 3'b011} (autu-proven).
                    wave_ca_a_rise <= {w_access_row[10:7], 3'b011};
                    wave_ca_a_fall <= w_access_row[6:0];
                end
                else begin
                    wave_cs_a_0_fall <= 1'b0;
                    wave_cs_a_0_rise <= 1'b0;
                    wave_ca_a_fall   <= 7'h00;
                    wave_ca_a_rise   <= 7'h00;
                end
            end

            GF_READ: begin
                if (w_read_cmd_first == 1'b1) begin
                    wave_cs_a_0_fall <= 1'b1;
                    wave_cs_a_0_rise <= 1'b1;
                    wave_ca_a_rise <= 7'b0101100;
                    wave_ca_a_fall <= 7'b0000000;
                end
                else if (w_read_cmd_second == 1'b1) begin
                    wave_cs_a_0_fall <= 1'b1;
                    wave_cs_a_0_rise <= 1'b1;
                    // RD16 R1: JEDEC CA0-first row "H L L C0 C3 C4 C5"
                    // = literal {C5,C4,C3,C0, 3'b001} (autu-proven).
                    wave_ca_a_rise <= {w_access_col[5:3], w_access_col[0], 3'b001};
                    wave_ca_a_fall <= {1'b0, w_access_col[2:1], w_read_bg, w_read_ba};
                end
                else begin
                    wave_cs_a_0_fall <= 1'b0;
                    wave_cs_a_0_rise <= 1'b0;
                    wave_ca_a_fall   <= 7'h00;
                    wave_ca_a_rise   <= 7'h00;
                end
            end

            GF_WRITE,
            GF_WRITE_AFTER_READ: begin
                if (w_write_cmd_first == 1'b1) begin
                    wave_cs_a_0_fall <= 1'b1;
                    wave_cs_a_0_rise <= 1'b1;
                    wave_ca_a_rise <= 7'b0011100;
                    wave_ca_a_fall <= 7'b0000000;
                end
                else if (w_write_cmd_second == 1'b1) begin
                    wave_cs_a_0_fall <= 1'b1;
                    wave_cs_a_0_rise <= 1'b1;
                    // WR16 R1: JEDEC CA0-first row "L H H C0 C3 C4 C5"
                    // = literal {C5,C4,C3,C0, 3'b110} (autu-proven).
                    wave_ca_a_rise <= {w_access_col[5:3], w_access_col[0], 3'b110};
                    wave_ca_a_fall <= {1'b0, w_access_col[2:1], w_write_bg, w_write_ba};
                end
                else begin
                    wave_cs_a_0_fall <= 1'b0;
                    wave_cs_a_0_rise <= 1'b0;
                    wave_ca_a_fall   <= 7'h00;
                    wave_ca_a_rise   <= 7'h00;
                end
            end

            GF_PRECHARGING,
            GF_PRE_REFRESH: begin
                if (w_precharge_cmd_first == 1'b1) begin
                    wave_cs_a_0_fall <= 1'b1;
                    wave_cs_a_0_rise <= 1'b1;
                    wave_ca_a_rise   <= 7'b1111000;
                    wave_ca_a_fall   <= 7'b1110000;
                end
                else begin
                    wave_cs_a_0_fall <= 1'b0;
                    wave_cs_a_0_rise <= 1'b0;
                    wave_ca_a_fall   <= 7'h00;
                    wave_ca_a_rise   <= 7'h00;
                end
            end

            GF_REFRESH: begin
                if ((w_refresh_cmd == 1'b1) &&
                    (refresh_cnt_run == 1'b1)) begin
                    wave_cs_a_0_fall <= 1'b1;
                    wave_cs_a_0_rise <= 1'b1;
                    wave_ca_a_rise   <= 7'b0111000;
                    wave_ca_a_fall   <= 7'b1110000;
                end
                else begin
                    wave_cs_a_0_fall <= 1'b0;
                    wave_cs_a_0_rise <= 1'b0;
                    wave_ca_a_fall   <= 7'h00;
                    wave_ca_a_rise   <= 7'h00;
                end
            end

            default: begin
                wave_cs_a_0_fall <= 1'b0;
                wave_cs_a_0_rise <= 1'b0;
                wave_ca_a_fall   <= 7'h00;
                wave_ca_a_rise   <= 7'h00;
            end
        endcase

        if (w_wck_wr_active || w_wck_rd_active) begin
            wave_wck_a_run_en <= 2'b11;
            wave_wck_a_phase  <= GF_WCK_INVERT ? 2'b11 : 2'b00;
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wave_dq_a_tx_word <= 64'h0000_0000_0000_0000;
        wave_dq_oe        <= 1'b0;
    end
    else if (w_wr_dq_oe_active == 1'b1) begin
        wave_dq_a_tx_word <= w_write_march_word;
        wave_dq_oe        <= 1'b1;
    end
    else begin
        wave_dq_a_tx_word <= 64'h0000_0000_0000_0000;
        wave_dq_oe        <= 1'b0;
    end
end

always @(*) begin
    case (state_c)
        GF_IDLE:             ascii_state = "GF_IDLE       ";
        GF_SCHED:            ascii_state = "GF_SCHED      ";
        GF_ACTIVATING:       ascii_state = "GF_ACTIVATING ";
        GF_WRITE:            ascii_state = "GF_WRITE      ";
        GF_WRITE_AFTER_READ: ascii_state = "GF_RD_WR      ";
        GF_WTR_WAIT:         ascii_state = "GF_WTR_WAIT   ";
        GF_READ:             ascii_state = "GF_READ       ";
        GF_PRECHARGING:      ascii_state = "GF_PRECHARGE  ";
        GF_PRE_REFRESH:      ascii_state = "GF_PRE_REF    ";
        GF_REFRESH:          ascii_state = "GF_REFRESH    ";
        default:             ascii_state = "GF_DEFAULT    ";
    endcase
end

BLOCK64 u_gf_block64 (
    .clk                                (clk                       ),
    .rst_n                              (rst_n                     ),
    .gf_test_en                         (gf_test_en                ),
    .die_message                        (die_message               ),
    .cnt_bg                             (gf_err_bg_r               ),
    .cnt_ba                             (gf_err_ba_r               ),
    .cnt_row                            (gf_cnt_row                ),
    .cnt_row_ns                         (gf_cnt_row_ns              ),
    .march_y_sequence                   (march_y_sequence_r         ),
    .err_flag                           (gf_err_flag               ),
    .err_block_cnt                      (err_block_cnt             ),
    .err_block_message                  (err_block_message         )
);

endmodule
