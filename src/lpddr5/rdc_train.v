/**
 * rdc_train
 * RDC per-DQ input delay training engine.
 */
module rdc_train #(
    // Number of consecutive sampled tap points required for a valid window.
    parameter [9:0] P_MIN_WINDOW_POINTS = 10'd4,
    // Number of fresh MRR/capture results used to verify the selected center.
    parameter [1:0] P_VERIFY_REPEAT      = 2'd3
) (
    input  wire                 clk                         ,
    input  wire                 rst_n                       ,

    input  wire                 train_start                 ,
    input  wire                 train_clear                 ,
    input  wire                 train_apply_best_cfg        ,
    input  wire                 train_dual_pattern_cfg      ,
    input  wire [  3:0]         train_dq_start_cfg          ,
    input  wire [  3:0]         train_dq_end_cfg            ,
    input  wire [  8:0]         train_tap_start_cfg         ,
    input  wire [  8:0]         train_tap_stop_cfg          ,
    input  wire [  8:0]         train_tap_step_cfg          ,

    input  wire                 dq_delay_l_we               ,
    input  wire                 dq_delay_h_we               ,
    input  wire [ 95:0]         dq_delay_wdat               ,

    input  wire                 train_init_ready_in         ,
    input  wire                 runtime_mr_busy             ,
    input  wire [ 15:0]         rdc_err_bitmap              ,
    input  wire                 rdc_check_valid             ,
    input  wire [  8:0]         train_scan_tap_sel          ,

    output reg  [143:0]         dq_delay_flat               ,
    output reg  [ 23:0]         mrw_r                       ,
    output reg  [ 31:0]         mrr_r                       ,
    output wire [  3:0]         train_state                 ,
    output wire                 train_busy                  ,
    output wire                 train_done                  ,
    output wire                 train_apply_best            ,
    output wire [  3:0]         train_dq_start              ,
    output wire [  8:0]         train_tap                   ,
    output wire                 train_pattern_sel           ,
    output wire [  9:0]         train_status_best_len       ,
    output wire [ 15:0]         train_pass_mask             ,
    output wire [ 15:0]         train_fail_mask             ,
    output wire [ 15:0]         train_last_err_bitmap       ,
    output wire                 train_init_ready            ,
    output wire                 train_pass_all              ,
    output wire [143:0]         train_best_flat             ,
    output wire [143:0]         train_left_flat             ,
    output wire [143:0]         train_right_flat            ,
    output wire [ 15:0]         train_scan_pass_bitmap
);

/***************function**************/
function [15:0] rdc_train_mask_range;
    input [3:0] first_dq;
    input [3:0] last_dq;
    integer idx;
    begin
        rdc_train_mask_range = 16'h0000;
        for (idx = 0; idx < 16; idx = idx + 1) begin
            if ((idx >= first_dq) && (idx <= last_dq)) begin
                rdc_train_mask_range[idx] = 1'b1;
            end
        end
    end
endfunction

function [15:0] rdc_train_window_fail_mask;
    input [159:0] best_len_flat;
    input [15:0]  target_mask;
    integer idx;
    begin
        rdc_train_window_fail_mask = 16'h0000;
        for (idx = 0; idx < 16; idx = idx + 1) begin
            if ((target_mask[idx] == 1'b1) &&
                (best_len_flat[(idx * 10) +: 10] < P_MIN_WINDOW_POINTS)) begin
                rdc_train_window_fail_mask[idx] = 1'b1;
            end
        end
    end
endfunction

function [ 7:0] rdc_train_pattern_value;
    input [  6:0] mr_addr;
    input         pattern_sel;
    begin
        // MR33/MR34 are the two 8-beat halves of one BL16 pattern.
        // Keep the two halves complementary so the MR boundary also toggles.
        if (mr_addr == 7'h21) begin
            rdc_train_pattern_value =
                (pattern_sel == 1'b1) ? 8'h3c : 8'h5a;
        end
        else begin
            rdc_train_pattern_value =
                (pattern_sel == 1'b1) ? 8'hc3 : 8'ha5;
        end
    end
endfunction

function [23:0] rdc_train_mrw_pattern_cmd;
    input [6:0] mr_addr;
    input       pattern_sel;
    reg   [7:0] pattern_value;
    begin
        pattern_value = rdc_train_pattern_value(mr_addr, pattern_sel);
        // Runtime MRW command keeps bit[7] unused. Keep it zero so
        // OP[7:0] and MA[6:0] line up with lpddr5_init.
        rdc_train_mrw_pattern_cmd = {
            7'd0,
            1'b1,
            pattern_value[7],
            pattern_value[6:0],
            1'b0,
            mr_addr
        };
    end
endfunction

/***************parameter*************/
    localparam   [   3: 0]      RDC_TRAIN_IDLE              = 4'd0          ;
    localparam   [   3: 0]      RDC_TRAIN_WAIT_INIT         = 4'd1          ;
    localparam   [   3: 0]      RDC_TRAIN_LOAD_TAP          = 4'd2          ;
    localparam   [   3: 0]      RDC_TRAIN_WAIT_LOAD         = 4'd3          ;
    localparam   [   3: 0]      RDC_TRAIN_SET_MR33          = 4'd4          ;
    localparam   [   3: 0]      RDC_TRAIN_WAIT_MR33         = 4'd5          ;
    localparam   [   3: 0]      RDC_TRAIN_SET_MR34          = 4'd6          ;
    localparam   [   3: 0]      RDC_TRAIN_WAIT_MR34         = 4'd7          ;
    localparam   [   3: 0]      RDC_TRAIN_MRR_LOW           = 4'd8          ;
    localparam   [   3: 0]      RDC_TRAIN_MRR_HIGH          = 4'd9          ;
    localparam   [   3: 0]      RDC_TRAIN_WAIT_CLEAR        = 4'd10         ;
    localparam   [   3: 0]      RDC_TRAIN_WAIT_VALID        = 4'd11         ;
    localparam   [   3: 0]      RDC_TRAIN_SCORE             = 4'd12         ;
    localparam   [   3: 0]      RDC_TRAIN_NEXT_TAP          = 4'd13         ;
    localparam   [   3: 0]      RDC_TRAIN_FINISH_DQ         = 4'd14         ;
    localparam   [   3: 0]      RDC_TRAIN_DONE              = 4'd15         ;
    localparam   [   7: 0]      RDC_TRAIN_LOAD_WAIT_CYCLES  = 8'd96         ;
    localparam   [   7: 0]      RDC_TRAIN_MRW_WAIT_CYCLES   = 8'd96         ;
    localparam   [   2: 0]      RDC_TRAIN_MRR_HOLD_CYCLES   = 3'd5          ;
    localparam   [  11: 0]      RDC_TRAIN_RESULT_TIMEOUT    = 12'd2047      ;
    localparam   [   6: 0]      RDC_TRAIN_MR33_ADDR         = 7'h21         ;
    localparam   [   6: 0]      RDC_TRAIN_MR34_ADDR         = 7'h22         ;
    localparam   [  31: 0]      RDC_TRAIN_MRR8_LOW          = 32'h0000_0008 ;
    localparam   [  31: 0]      RDC_TRAIN_MRR8_HIGH         = 32'h0100_0008 ;
    localparam   [   8: 0]      RDC_TRAIN_TAP_START_DFT     = 9'd0          ;
    localparam   [   8: 0]      RDC_TRAIN_TAP_STOP_DFT      = 9'd300        ;
    localparam   [   8: 0]      RDC_TRAIN_TAP_STEP_DFT      = 9'd2          ;
    localparam                  RDC_TRAIN_DUAL_PATTERN_DFT  = 1'b1          ;

/***************reg*******************/
    reg   [   3: 0]      rdc_train_state               ;
    reg                  rdc_train_busy                ;
    reg                  rdc_train_done                ;
    reg                  rdc_train_apply_best          ;
    reg   [   3: 0]      rdc_train_dq_start            ;
    reg   [   3: 0]      rdc_train_dq_end              ;
    reg   [   8: 0]      rdc_train_tap_start           ;
    reg   [   8: 0]      rdc_train_tap_stop            ;
    reg   [   8: 0]      rdc_train_tap_step            ;
    reg   [   8: 0]      rdc_train_tap                 ;
    reg   [   7: 0]      rdc_train_wait_cnt            ;
    reg   [  11: 0]      rdc_train_timeout_cnt         ;
    reg   [   2: 0]      rdc_train_fire_cnt            ;
    reg   [  15: 0]      rdc_train_win_active          ;
    reg   [ 143: 0]      rdc_train_win_left_flat       ;
    reg   [ 159: 0]      rdc_train_win_len_flat        ;
    reg   [ 159: 0]      rdc_train_best_len_flat       ;
    reg   [ 143: 0]      rdc_train_saved_delay_flat    ;
    reg   [ 143: 0]      rdc_train_best_flat           ;
    reg   [ 143: 0]      rdc_train_left_flat           ;
    reg   [ 143: 0]      rdc_train_right_flat          ;
    reg   [  15: 0]      rdc_train_pass_mask           ;
    reg   [  15: 0]      rdc_train_fail_mask           ;
    reg   [  15: 0]      rdc_train_target_mask         ;
    reg   [  15: 0]      rdc_train_last_err_bitmap     ;
    reg   [  15: 0]      rdc_train_tap_err_bitmap      ;
    reg   [  15: 0]      rdc_train_pattern_active      ;
    reg   [  15: 0]      rdc_train_retry_err0          ;
    reg   [  15: 0]      rdc_train_retry_err1          ;
    reg   [   1: 0]      rdc_train_retry_cnt           ;
    reg   [  15: 0]      rdc_train_scan_pass_bitmap    ;
    reg   [   8: 0]      r_rdc_train_scan_clear_addr   ;
    reg                  r_rdc_train_scan_clear_active ;
    reg                  r_rdc_train_scan_map_valid    ;
    reg                  r_rdc_train_start_pending     ;
    reg                  rdc_train_pattern_idx         ;
    reg                  rdc_train_pattern_mr_loaded   ;
    reg                  rdc_train_dual_pattern        ;
    reg                  rdc_train_init_ready_seen     ;
    reg                  rdc_train_verify_mode         ;
    reg   [   1: 0]      rdc_train_verify_round        ;
    reg   [  15: 0]      rdc_train_verify_err_bitmap   ;
    reg   [  15: 0]      rdc_train_win_active_next     ;
    reg   [ 143: 0]      rdc_train_win_left_flat_next  ;
    reg   [ 159: 0]      rdc_train_win_len_flat_next   ;
    reg   [ 159: 0]      rdc_train_best_len_flat_next  ;
    reg   [ 143: 0]      rdc_train_best_flat_next      ;
    reg   [ 143: 0]      rdc_train_left_flat_next      ;
    reg   [ 143: 0]      rdc_train_right_flat_next     ;
    integer              rdc_train_idx                 ;
    integer              rdc_train_comb_idx            ;
    reg   [   8: 0]      rdc_train_score_left_tmp      ;
    reg   [   9: 0]      rdc_train_score_len_tmp       ;
    reg   [   9: 0]      rdc_train_score_mid_sum       ;

    // Pattern-0 pass bitmap is written during the first sweep and read during
    // the second sweep to score the same tap with pattern intersection.
    (* ram_style = "distributed" *)
    reg   [  15: 0]      rdc_train_pat0_pass_mem [0:511];

/***************wire******************/
    wire  [   9: 0]      w_rdc_train_tap_delta        ;
    wire  [   9: 0]      w_rdc_train_tap_step_ext     ;
    wire  [   9: 0]      w_rdc_train_tap_sum          ;
    wire  [   8: 0]      w_rdc_train_tap_next         ;
    wire                 w_rdc_train_last_tap         ;
    wire  [  15: 0]      w_rdc_train_target_mask_cfg  ;
    wire  [  15: 0]      w_rdc_train_pat0_pass_bitmap ;
    wire  [  15: 0]      w_rdc_train_pat1_pass_bitmap ;
    wire  [  15: 0]      w_rdc_train_dual_err_bitmap  ;
    wire  [  15: 0]      w_rdc_train_vote_err_bitmap  ;
    wire  [  15: 0]      w_rdc_train_result_err_bitmap;
    wire  [  15: 0]      w_rdc_train_window_fail_mask  ;
    wire  [  15: 0]      w_rdc_train_verify_err_bitmap ;
    wire                 w_rdc_train_retry_needed     ;
    wire                 w_rdc_train_scan_clear_last  ;
    wire                 w_rdc_train_start_accept     ;
    wire                 w_rdc_train_scan_output_valid;
    wire                 w_rdc_train_pass_mem_clear_we;
    wire                 w_rdc_train_pass_mem_result_we;
    wire                 w_rdc_train_pass_mem_timeout_we;
    wire                 w_rdc_train_pass_mem_we      ;
    wire  [   8: 0]      w_rdc_train_pass_mem_waddr   ;
    wire  [  15: 0]      w_rdc_train_pass_mem_wdata   ;

/***************assign****************/
    assign   train_state                 = rdc_train_state      ;
    assign   train_busy                  = rdc_train_busy       ;
    assign   train_done                  = rdc_train_done       ;
    assign   train_apply_best            = rdc_train_apply_best ;
    assign   train_dq_start              = rdc_train_dq_start   ;
    assign   train_tap                   = rdc_train_tap        ;
    assign   train_pattern_sel           = rdc_train_pattern_idx;
    assign   train_status_best_len       = rdc_train_best_len_flat[(rdc_train_dq_start * 10) +: 10];
    assign   train_pass_mask             = rdc_train_pass_mask  ;
    assign   train_fail_mask             = rdc_train_fail_mask  ;
    assign   train_last_err_bitmap       = rdc_train_last_err_bitmap            ;
    assign   train_init_ready            = train_init_ready_in || rdc_train_init_ready_seen;
    assign   train_pass_all              = rdc_train_done && ((rdc_train_fail_mask & rdc_train_target_mask) == 16'h0000);
    assign   train_best_flat             = rdc_train_best_flat  ;
    assign   train_left_flat             = rdc_train_left_flat  ;
    assign   train_right_flat            = rdc_train_right_flat ;
    assign   train_scan_pass_bitmap      = rdc_train_scan_pass_bitmap;

assign w_rdc_train_tap_delta     = {1'b0, rdc_train_tap_stop} - {1'b0, rdc_train_tap};
assign w_rdc_train_tap_step_ext  = {1'b0, rdc_train_tap_step};
assign w_rdc_train_tap_sum       = {1'b0, rdc_train_tap} + w_rdc_train_tap_step_ext;
assign w_rdc_train_tap_next      = w_rdc_train_tap_sum[8:0];
assign w_rdc_train_last_tap      =
    (rdc_train_tap >= rdc_train_tap_stop) ||
    (w_rdc_train_tap_delta < w_rdc_train_tap_step_ext);
assign w_rdc_train_target_mask_cfg =
    rdc_train_mask_range(train_dq_start_cfg, train_dq_end_cfg);
assign w_rdc_train_pat0_pass_bitmap = rdc_train_pat0_pass_mem[rdc_train_tap];
assign w_rdc_train_vote_err_bitmap  =
       (rdc_train_retry_err0 & rdc_train_retry_err1)
     | (rdc_train_retry_err0 & rdc_err_bitmap)
     | (rdc_train_retry_err1 & rdc_err_bitmap);
assign w_rdc_train_result_err_bitmap =
    (rdc_train_retry_cnt == 2'd2) ? w_rdc_train_vote_err_bitmap :
                                    rdc_err_bitmap;
assign w_rdc_train_pat1_pass_bitmap = ~w_rdc_train_result_err_bitmap;
assign w_rdc_train_dual_err_bitmap  =
    ~(w_rdc_train_pat0_pass_bitmap & w_rdc_train_pat1_pass_bitmap);
assign w_rdc_train_window_fail_mask =
    rdc_train_window_fail_mask(rdc_train_best_len_flat,
                               rdc_train_target_mask);
assign w_rdc_train_verify_err_bitmap =
    rdc_train_verify_err_bitmap | rdc_err_bitmap;
assign w_rdc_train_retry_needed =
    (rdc_train_retry_cnt == 2'd0) &&
    (|(((~rdc_err_bitmap & ~rdc_train_pattern_active) |
        ( rdc_err_bitmap &  rdc_train_pattern_active)) &
       rdc_train_target_mask));
assign w_rdc_train_scan_clear_last =
    (r_rdc_train_scan_clear_active == 1'b1) &&
    (r_rdc_train_scan_clear_addr == 9'd511);
assign w_rdc_train_start_accept =
    ((train_start == 1'b1) || (r_rdc_train_start_pending == 1'b1)) &&
    (r_rdc_train_scan_clear_active == 1'b0) &&
    (train_clear == 1'b0) &&
    (rdc_train_busy == 1'b0);
assign w_rdc_train_scan_output_valid =
    (r_rdc_train_scan_map_valid == 1'b1) &&
    (r_rdc_train_scan_clear_active == 1'b0) &&
    (train_clear == 1'b0) &&
    (w_rdc_train_start_accept == 1'b0);
assign w_rdc_train_pass_mem_clear_we =
    r_rdc_train_scan_clear_active;
assign w_rdc_train_pass_mem_result_we =
    (rdc_train_busy == 1'b1) &&
    (rdc_train_state == RDC_TRAIN_WAIT_VALID) &&
    (rdc_train_verify_mode == 1'b0) &&
    (rdc_check_valid == 1'b1) &&
    (w_rdc_train_retry_needed == 1'b0) &&
    (rdc_train_retry_cnt != 2'd1);
assign w_rdc_train_pass_mem_timeout_we =
    (rdc_train_busy == 1'b1) &&
    ((((rdc_train_state == RDC_TRAIN_WAIT_CLEAR) &&
       (rdc_check_valid == 1'b1)) ||
      ((rdc_train_state == RDC_TRAIN_WAIT_VALID) &&
       (rdc_train_verify_mode == 1'b0) &&
       (rdc_check_valid == 1'b0))) &&
     (rdc_train_timeout_cnt >= RDC_TRAIN_RESULT_TIMEOUT));
assign w_rdc_train_pass_mem_we =
    w_rdc_train_pass_mem_clear_we ||
    w_rdc_train_pass_mem_result_we ||
    w_rdc_train_pass_mem_timeout_we;
assign w_rdc_train_pass_mem_waddr =
    (w_rdc_train_pass_mem_clear_we == 1'b1) ?
    r_rdc_train_scan_clear_addr : rdc_train_tap;
assign w_rdc_train_pass_mem_wdata =
    ((w_rdc_train_pass_mem_clear_we == 1'b1) ||
     (w_rdc_train_pass_mem_timeout_we == 1'b1)) ? 16'h0000 :
    ((rdc_train_dual_pattern == 1'b1) &&
     (rdc_train_pattern_idx == 1'b1)) ?
    (w_rdc_train_pat0_pass_bitmap & w_rdc_train_pat1_pass_bitmap) :
    ~w_rdc_train_result_err_bitmap;

// Pattern-1 overwrites pattern-0 with the final intersection. The same memory
// then provides the complete post-training pass map without another 512x16 RAM.
// Runtime clear uses the RAM's single write port, one 16-bit tap per cycle.
always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) begin
        r_rdc_train_scan_clear_addr   <= 9'd0;
        r_rdc_train_scan_clear_active <= 1'b0;
    end
    else if (train_clear == 1'b1) begin
        r_rdc_train_scan_clear_addr   <= 9'd0;
        r_rdc_train_scan_clear_active <= 1'b1;
    end
    else if (w_rdc_train_scan_clear_last == 1'b1) begin
        r_rdc_train_scan_clear_addr   <= 9'd0;
        r_rdc_train_scan_clear_active <= 1'b0;
    end
    else if (r_rdc_train_scan_clear_active == 1'b1) begin
        r_rdc_train_scan_clear_addr <=
            r_rdc_train_scan_clear_addr + 9'd1;
        r_rdc_train_scan_clear_active <=
            r_rdc_train_scan_clear_active;
    end
    else begin
        r_rdc_train_scan_clear_addr   <= r_rdc_train_scan_clear_addr;
        r_rdc_train_scan_clear_active <= r_rdc_train_scan_clear_active;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) begin
        r_rdc_train_start_pending <= 1'b0;
    end
    else if (train_clear == 1'b1) begin
        r_rdc_train_start_pending <= train_start;
    end
    else if ((train_start == 1'b1) &&
             (r_rdc_train_scan_clear_active == 1'b1)) begin
        r_rdc_train_start_pending <= 1'b1;
    end
    else if (w_rdc_train_start_accept == 1'b1) begin
        r_rdc_train_start_pending <= 1'b0;
    end
    else begin
        r_rdc_train_start_pending <= r_rdc_train_start_pending;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) begin
        r_rdc_train_scan_map_valid <= 1'b0;
    end
    else if (train_clear == 1'b1) begin
        r_rdc_train_scan_map_valid <= 1'b0;
    end
    else if (w_rdc_train_start_accept == 1'b1) begin
        r_rdc_train_scan_map_valid <= 1'b0;
    end
    else if (rdc_train_done == 1'b1) begin
        r_rdc_train_scan_map_valid <= 1'b1;
    end
    else begin
        r_rdc_train_scan_map_valid <= r_rdc_train_scan_map_valid;
    end
end

always @(posedge clk) begin
    if (w_rdc_train_pass_mem_we == 1'b1) begin
        rdc_train_pat0_pass_mem[w_rdc_train_pass_mem_waddr] <=
            w_rdc_train_pass_mem_wdata;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) begin
        rdc_train_scan_pass_bitmap <= 16'h0000;
    end
    else if (w_rdc_train_scan_output_valid == 1'b0) begin
        rdc_train_scan_pass_bitmap <= 16'h0000;
    end
    else begin
        rdc_train_scan_pass_bitmap <=
            rdc_train_pat0_pass_mem[train_scan_tap_sel];
    end
end

/***************always****************/
always @(*) begin
    rdc_train_win_active_next    = rdc_train_win_active;
    rdc_train_win_left_flat_next = rdc_train_win_left_flat;
    rdc_train_win_len_flat_next  = rdc_train_win_len_flat;
    rdc_train_best_len_flat_next = rdc_train_best_len_flat;
    rdc_train_best_flat_next     = rdc_train_best_flat;
    rdc_train_left_flat_next     = rdc_train_left_flat;
    rdc_train_right_flat_next    = rdc_train_right_flat;
    rdc_train_score_left_tmp     = 9'd0;
    rdc_train_score_len_tmp      = 10'd0;
    rdc_train_score_mid_sum      = 10'd0;

    for (rdc_train_comb_idx = 0;
         rdc_train_comb_idx < 16;
         rdc_train_comb_idx = rdc_train_comb_idx + 1) begin
        if ((rdc_train_comb_idx >= rdc_train_dq_start) &&
            (rdc_train_comb_idx <= rdc_train_dq_end)) begin
            if (rdc_train_last_err_bitmap[rdc_train_comb_idx] == 1'b0) begin
                if (rdc_train_win_active[rdc_train_comb_idx] == 1'b1) begin
                    rdc_train_score_left_tmp =
                        rdc_train_win_left_flat[(rdc_train_comb_idx * 9) +: 9];
                    rdc_train_score_len_tmp =
                        rdc_train_win_len_flat[(rdc_train_comb_idx * 10) +: 10] + 10'd1;
                end
                else begin
                    rdc_train_score_left_tmp = rdc_train_tap;
                    rdc_train_score_len_tmp  = 10'd1;
                end

                rdc_train_win_active_next[rdc_train_comb_idx] = 1'b1;
                rdc_train_win_left_flat_next[(rdc_train_comb_idx * 9) +: 9] =
                    rdc_train_score_left_tmp;
                rdc_train_win_len_flat_next[(rdc_train_comb_idx * 10) +: 10] =
                    rdc_train_score_len_tmp;

                if (rdc_train_score_len_tmp >
                    rdc_train_best_len_flat[(rdc_train_comb_idx * 10) +: 10]) begin
                    rdc_train_score_mid_sum =
                        {1'b0, rdc_train_score_left_tmp} + {1'b0, rdc_train_tap};
                    rdc_train_best_len_flat_next[(rdc_train_comb_idx * 10) +: 10] =
                        rdc_train_score_len_tmp;
                    rdc_train_best_flat_next[(rdc_train_comb_idx * 9) +: 9] =
                        rdc_train_score_mid_sum[9:1];
                    rdc_train_left_flat_next[(rdc_train_comb_idx * 9) +: 9] =
                        rdc_train_score_left_tmp;
                    rdc_train_right_flat_next[(rdc_train_comb_idx * 9) +: 9] =
                        rdc_train_tap;
                end
            end
            else begin
                rdc_train_win_active_next[rdc_train_comb_idx] = 1'b0;
                rdc_train_win_len_flat_next[(rdc_train_comb_idx * 10) +: 10] = 10'd0;
            end
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) begin
        dq_delay_flat[  8:  0]    <= 9'd0;
        dq_delay_flat[ 17:  9]    <= 9'd0;
        dq_delay_flat[ 26: 18]    <= 9'd0;
        dq_delay_flat[ 35: 27]    <= 9'd0;
        dq_delay_flat[ 44: 36]    <= 9'd0;
        dq_delay_flat[ 53: 45]    <= 9'd0;
        dq_delay_flat[ 62: 54]    <= 9'd0;
        dq_delay_flat[ 71: 63]    <= 9'd0;
        dq_delay_flat[ 80: 72]    <= 9'd0;
        dq_delay_flat[ 89: 81]    <= 9'd0;
        dq_delay_flat[ 98: 90]    <= 9'd0;
        dq_delay_flat[107: 99]    <= 9'd0;
        dq_delay_flat[116:108]    <= 9'd0;
        dq_delay_flat[125:117]    <= 9'd0;
        dq_delay_flat[134:126]    <= 9'd0;
        dq_delay_flat[143:135]    <= 9'd0;
        mrw_r                     <= 24'd0;
        mrr_r                     <= 32'd0;
        rdc_train_state           <= RDC_TRAIN_IDLE;
        rdc_train_busy            <= 1'b0;
        rdc_train_done            <= 1'b0;
        rdc_train_apply_best      <= 1'b1;
        rdc_train_dq_start        <= 4'd0;
        rdc_train_dq_end          <= 4'd15;
        rdc_train_tap_start       <= RDC_TRAIN_TAP_START_DFT;
        rdc_train_tap_stop        <= RDC_TRAIN_TAP_STOP_DFT;
        rdc_train_tap_step        <= RDC_TRAIN_TAP_STEP_DFT;
        rdc_train_tap             <= RDC_TRAIN_TAP_START_DFT;
        rdc_train_wait_cnt        <= 8'd0;
        rdc_train_timeout_cnt     <= 12'd0;
        rdc_train_fire_cnt        <= 3'd0;
        rdc_train_win_active      <= 16'h0000;
        rdc_train_win_left_flat   <= 144'd0;
        rdc_train_win_len_flat    <= 160'd0;
        rdc_train_best_len_flat   <= 160'd0;
        rdc_train_saved_delay_flat <= 144'd0;
        rdc_train_best_flat       <= 144'd0;
        rdc_train_left_flat       <= 144'd0;
        rdc_train_right_flat      <= 144'd0;
        rdc_train_pass_mask       <= 16'h0000;
        rdc_train_fail_mask       <= 16'h0000;
        rdc_train_target_mask     <= 16'hffff;
        rdc_train_last_err_bitmap <= 16'h0000;
        rdc_train_tap_err_bitmap  <= 16'h0000;
        rdc_train_pattern_active  <= 16'h0000;
        rdc_train_retry_err0      <= 16'h0000;
        rdc_train_retry_err1      <= 16'h0000;
        rdc_train_retry_cnt       <= 2'd0;
        rdc_train_pattern_idx     <= 1'b0;
        rdc_train_pattern_mr_loaded <= 1'b0;
        rdc_train_dual_pattern    <= RDC_TRAIN_DUAL_PATTERN_DFT;
        rdc_train_init_ready_seen <= 1'b0;
        rdc_train_verify_mode     <= 1'b0;
        rdc_train_verify_round    <= 2'd0;
        rdc_train_verify_err_bitmap <= 16'h0000;
    end
    else begin
        if (train_init_ready_in == 1'b1) begin
            rdc_train_init_ready_seen <= 1'b1;
        end
        else begin
            rdc_train_init_ready_seen <= rdc_train_init_ready_seen;
        end

        if (train_clear == 1'b1) begin
            dq_delay_flat          <= 144'd0;
            mrw_r                  <= 24'd0;
            mrr_r                  <= 32'd0;
            rdc_train_state        <= RDC_TRAIN_IDLE;
            rdc_train_busy         <= 1'b0;
            rdc_train_done         <= 1'b0;
            rdc_train_apply_best   <= 1'b1;
            rdc_train_tap          <= rdc_train_tap_start;
            rdc_train_wait_cnt     <= 8'd0;
            rdc_train_timeout_cnt  <= 12'd0;
            rdc_train_fire_cnt     <= 3'd0;
            rdc_train_win_active   <= 16'h0000;
            rdc_train_win_len_flat <= 160'd0;
            rdc_train_saved_delay_flat <= 144'd0;
            rdc_train_best_len_flat <= 160'd0;
            rdc_train_best_flat    <= 144'd0;
            rdc_train_left_flat    <= 144'd0;
            rdc_train_right_flat   <= 144'd0;
            rdc_train_pass_mask    <= 16'h0000;
            rdc_train_fail_mask    <= 16'h0000;
            rdc_train_target_mask  <= 16'hffff;
            rdc_train_last_err_bitmap <= 16'h0000;
            rdc_train_tap_err_bitmap <= 16'h0000;
            rdc_train_pattern_active <= 16'h0000;
            rdc_train_retry_err0     <= 16'h0000;
            rdc_train_retry_err1     <= 16'h0000;
            rdc_train_retry_cnt      <= 2'd0;
            rdc_train_pattern_idx  <= 1'b0;
            rdc_train_pattern_mr_loaded <= 1'b0;
            rdc_train_dual_pattern <= RDC_TRAIN_DUAL_PATTERN_DFT;
            rdc_train_init_ready_seen <= 1'b0;
            rdc_train_verify_mode   <= 1'b0;
            rdc_train_verify_round  <= 2'd0;
            rdc_train_verify_err_bitmap <= 16'h0000;
        end
        else if (w_rdc_train_start_accept == 1'b1) begin
            rdc_train_state        <= RDC_TRAIN_WAIT_INIT;
            rdc_train_busy         <= 1'b1;
            rdc_train_done         <= 1'b0;
            rdc_train_apply_best   <= train_apply_best_cfg;
            rdc_train_dq_start     <= train_dq_start_cfg;
            rdc_train_dq_end       <= train_dq_end_cfg;
            rdc_train_tap_start    <= train_tap_start_cfg;
            rdc_train_tap_stop     <= train_tap_stop_cfg;
            rdc_train_tap_step     <= train_tap_step_cfg;
            rdc_train_tap          <= train_tap_start_cfg;
            rdc_train_wait_cnt     <= 8'd0;
            rdc_train_timeout_cnt  <= 12'd0;
            rdc_train_fire_cnt     <= 3'd0;
            rdc_train_win_active   <= 16'h0000;
            rdc_train_win_left_flat <= 144'd0;
            rdc_train_win_len_flat <= 160'd0;
            rdc_train_best_len_flat <= 160'd0;
            rdc_train_saved_delay_flat <= dq_delay_flat;
            rdc_train_best_flat    <= 144'd0;
            rdc_train_left_flat    <= 144'd0;
            rdc_train_right_flat   <= 144'd0;
            rdc_train_pass_mask    <= 16'h0000;
            rdc_train_fail_mask    <= 16'h0000;
            rdc_train_target_mask  <= w_rdc_train_target_mask_cfg;
            rdc_train_last_err_bitmap <= 16'h0000;
            rdc_train_tap_err_bitmap <= 16'h0000;
            rdc_train_pattern_active <= 16'h0000;
            rdc_train_retry_err0     <= 16'h0000;
            rdc_train_retry_err1     <= 16'h0000;
            rdc_train_retry_cnt      <= 2'd0;
            rdc_train_pattern_idx  <= 1'b0;
            rdc_train_pattern_mr_loaded <= 1'b0;
            rdc_train_dual_pattern <= train_dual_pattern_cfg;
            rdc_train_verify_mode   <= 1'b0;
            rdc_train_verify_round  <= 2'd0;
            rdc_train_verify_err_bitmap <= 16'h0000;
            mrw_r                  <= 24'd0;
            mrr_r                  <= 32'd0;
        end
        else if (rdc_train_busy == 1'b1) begin
            case (rdc_train_state)
                RDC_TRAIN_WAIT_INIT: begin
                    if (train_init_ready == 1'b1) begin
                        rdc_train_state <= RDC_TRAIN_LOAD_TAP;
                    end
                    else begin
                        rdc_train_state <= rdc_train_state;
                    end
                end

                RDC_TRAIN_LOAD_TAP: begin
                    for (rdc_train_idx = 0;rdc_train_idx < 16;rdc_train_idx = rdc_train_idx + 1) begin
                        if ((rdc_train_idx >= rdc_train_dq_start) && (rdc_train_idx <= rdc_train_dq_end)) begin
                            dq_delay_flat[(rdc_train_idx * 9) +: 9] <= rdc_train_tap;
                        end
                        else begin
                            dq_delay_flat[(rdc_train_idx * 9) +: 9] <= rdc_train_saved_delay_flat[(rdc_train_idx * 9) +: 9];
                        end
                    end
                    rdc_train_wait_cnt       <= 8'd0;
                    rdc_train_tap_err_bitmap <= 16'h0000;
                    rdc_train_retry_err0     <= 16'h0000;
                    rdc_train_retry_err1     <= 16'h0000;
                    rdc_train_retry_cnt      <= 2'd0;
                    mrw_r                    <= 24'd0;
                    mrr_r                    <= 32'd0;
                    rdc_train_state          <= RDC_TRAIN_WAIT_LOAD;
                end

                RDC_TRAIN_WAIT_LOAD: begin
                    if (rdc_train_wait_cnt >= RDC_TRAIN_LOAD_WAIT_CYCLES) begin
                        rdc_train_wait_cnt <= 8'd0;
                        if (rdc_train_pattern_mr_loaded == 1'b0) begin
                            rdc_train_state <= RDC_TRAIN_SET_MR33;
                        end
                        else begin
                            rdc_train_state <= RDC_TRAIN_MRR_LOW;
                        end
                    end
                    else begin
                        rdc_train_wait_cnt <= rdc_train_wait_cnt + 8'd1;
                    end
                end

                RDC_TRAIN_SET_MR33: begin
                    if ((runtime_mr_busy == 1'b1) && (rdc_train_fire_cnt == 3'd0)) begin
                        mrw_r              <= 24'd0;
                        mrr_r              <= 32'd0;
                        rdc_train_fire_cnt <= 3'd0;
                        rdc_train_wait_cnt <= 8'd0;
                        rdc_train_state    <= RDC_TRAIN_SET_MR33;
                    end
                    else begin
                        mrr_r <= 32'd0;
                        mrw_r <= rdc_train_mrw_pattern_cmd(
                            RDC_TRAIN_MR33_ADDR,
                            rdc_train_pattern_idx
                        );
                        if (rdc_train_fire_cnt >= RDC_TRAIN_MRR_HOLD_CYCLES) begin
                            rdc_train_fire_cnt <= 3'd0;
                            rdc_train_wait_cnt <= 8'd0;
                            rdc_train_state    <= RDC_TRAIN_WAIT_MR33;
                        end
                        else begin
                            rdc_train_fire_cnt <= rdc_train_fire_cnt + 3'd1;
                        end
                    end
                end

                RDC_TRAIN_WAIT_MR33: begin
                    mrw_r <= 24'd0;
                    mrr_r <= 32'd0;
                    if (rdc_train_wait_cnt >= RDC_TRAIN_MRW_WAIT_CYCLES) begin
                        rdc_train_wait_cnt <= 8'd0;
                        rdc_train_state    <= RDC_TRAIN_SET_MR34;
                    end
                    else begin
                        rdc_train_wait_cnt <= rdc_train_wait_cnt + 8'd1;
                    end
                end

                RDC_TRAIN_SET_MR34: begin
                    if ((runtime_mr_busy == 1'b1) &&
                        (rdc_train_fire_cnt == 3'd0)) begin
                        mrw_r              <= 24'd0;
                        mrr_r              <= 32'd0;
                        rdc_train_fire_cnt <= 3'd0;
                        rdc_train_wait_cnt <= 8'd0;
                        rdc_train_state    <= RDC_TRAIN_SET_MR34;
                    end
                    else begin
                        mrr_r <= 32'd0;
                        mrw_r <= rdc_train_mrw_pattern_cmd(
                            RDC_TRAIN_MR34_ADDR,
                            rdc_train_pattern_idx
                        );
                        if (rdc_train_fire_cnt >= RDC_TRAIN_MRR_HOLD_CYCLES) begin
                            rdc_train_fire_cnt <= 3'd0;
                            rdc_train_wait_cnt <= 8'd0;
                            rdc_train_state    <= RDC_TRAIN_WAIT_MR34;
                        end
                        else begin
                            rdc_train_fire_cnt <= rdc_train_fire_cnt + 3'd1;
                        end
                    end
                end

                RDC_TRAIN_WAIT_MR34: begin
                    mrw_r <= 24'd0;
                    mrr_r <= 32'd0;
                    if (rdc_train_wait_cnt >= RDC_TRAIN_MRW_WAIT_CYCLES) begin
                        rdc_train_wait_cnt <= 8'd0;
                        rdc_train_pattern_mr_loaded <= 1'b1;
                        rdc_train_state    <= RDC_TRAIN_MRR_LOW;
                    end
                    else begin
                        rdc_train_wait_cnt <= rdc_train_wait_cnt + 8'd1;
                    end
                end

                RDC_TRAIN_MRR_LOW: begin
                    if (runtime_mr_busy == 1'b1) begin
                        mrw_r                 <= 24'd0;
                        mrr_r                 <= RDC_TRAIN_MRR8_LOW;
                        rdc_train_fire_cnt    <= 3'd0;
                        rdc_train_timeout_cnt <= 12'd0;
                        rdc_train_state       <= RDC_TRAIN_MRR_LOW;
                    end
                    else begin
                        mrw_r                 <= 24'd0;
                        mrr_r                 <= RDC_TRAIN_MRR8_LOW;
                        rdc_train_fire_cnt    <= 3'd0;
                        rdc_train_timeout_cnt <= 12'd0;
                        rdc_train_state       <= RDC_TRAIN_MRR_HIGH;
                    end
                end

                RDC_TRAIN_MRR_HIGH: begin
                    mrw_r <= 24'd0;
                    mrr_r <= RDC_TRAIN_MRR8_HIGH;
                    if (rdc_train_fire_cnt >= RDC_TRAIN_MRR_HOLD_CYCLES) begin
                        rdc_train_fire_cnt    <= 3'd0;
                        rdc_train_timeout_cnt <= 12'd0;
                        rdc_train_state       <= RDC_TRAIN_WAIT_CLEAR;
                    end
                    else begin
                        rdc_train_fire_cnt <= rdc_train_fire_cnt + 3'd1;
                    end
                end

                RDC_TRAIN_WAIT_CLEAR: begin
                    mrw_r <= 24'd0;
                    mrr_r <= RDC_TRAIN_MRR8_LOW;
                    if (rdc_check_valid == 1'b0) begin
                        rdc_train_timeout_cnt <= 12'd0;
                        rdc_train_state       <= RDC_TRAIN_WAIT_VALID;
                    end
                    else if (rdc_train_timeout_cnt >= RDC_TRAIN_RESULT_TIMEOUT) begin
                        rdc_train_last_err_bitmap <= 16'hffff;
                        rdc_train_tap_err_bitmap  <= 16'hffff;
                        rdc_train_pattern_active  <=
                            rdc_train_pattern_active & ~rdc_train_target_mask;
                        rdc_train_retry_err0      <= 16'h0000;
                        rdc_train_retry_err1      <= 16'h0000;
                        rdc_train_retry_cnt       <= 2'd0;
                        rdc_train_timeout_cnt     <= 12'd0;
                        if ((rdc_train_dual_pattern == 1'b1) &&
                            (rdc_train_pattern_idx == 1'b0)) begin
                            rdc_train_state <= RDC_TRAIN_NEXT_TAP;
                        end
                        else begin
                            rdc_train_state <= RDC_TRAIN_SCORE;
                        end
                    end
                    else begin
                        rdc_train_timeout_cnt <= rdc_train_timeout_cnt + 12'd1;
                    end
                end

                RDC_TRAIN_WAIT_VALID: begin
                    if (rdc_train_verify_mode == 1'b1) begin
                        if (rdc_check_valid == 1'b1) begin
                            rdc_train_timeout_cnt <= 12'd0;
                            if ((P_VERIFY_REPEAT > 2'd1) &&
                                (rdc_train_verify_round < (P_VERIFY_REPEAT - 2'd1))) begin
                                rdc_train_verify_err_bitmap <=
                                    w_rdc_train_verify_err_bitmap;
                                rdc_train_verify_round <=
                                    rdc_train_verify_round + 2'd1;
                                rdc_train_state <= RDC_TRAIN_MRR_LOW;
                            end
                            else if ((w_rdc_train_verify_err_bitmap &
                                      rdc_train_target_mask) != 16'h0000) begin
                                rdc_train_last_err_bitmap <=
                                    w_rdc_train_verify_err_bitmap;
                                rdc_train_tap_err_bitmap <=
                                    w_rdc_train_verify_err_bitmap;
                                rdc_train_fail_mask <=
                                    w_rdc_train_verify_err_bitmap & rdc_train_target_mask;
                                rdc_train_pass_mask <=
                                    rdc_train_target_mask &
                                    ~w_rdc_train_verify_err_bitmap;
                                for (rdc_train_idx = 0;
                                     rdc_train_idx < 16;
                                     rdc_train_idx = rdc_train_idx + 1) begin
                                    dq_delay_flat[(rdc_train_idx * 9) +: 9] <=
                                        rdc_train_saved_delay_flat[(rdc_train_idx * 9) +: 9];
                                end
                                rdc_train_verify_round <= 2'd0;
                                rdc_train_state <= RDC_TRAIN_SCORE;
                            end
                            else if ((rdc_train_dual_pattern == 1'b1) &&
                                     (rdc_train_pattern_idx == 1'b0)) begin
                                rdc_train_verify_err_bitmap <= 16'h0000;
                                rdc_train_verify_round      <= 2'd0;
                                rdc_train_pattern_idx       <= 1'b1;
                                rdc_train_pattern_mr_loaded <= 1'b0;
                                rdc_train_state             <= RDC_TRAIN_SET_MR33;
                            end
                            else begin
                                rdc_train_last_err_bitmap <= 16'h0000;
                                rdc_train_tap_err_bitmap  <= 16'h0000;
                                rdc_train_fail_mask       <= 16'h0000;
                                rdc_train_pass_mask       <= rdc_train_target_mask;
                                if (rdc_train_apply_best == 1'b0) begin
                                    for (rdc_train_idx = 0;
                                         rdc_train_idx < 16;
                                         rdc_train_idx = rdc_train_idx + 1) begin
                                        dq_delay_flat[(rdc_train_idx * 9) +: 9] <=
                                            rdc_train_saved_delay_flat[(rdc_train_idx * 9) +: 9];
                                    end
                                end
                                rdc_train_state <= RDC_TRAIN_SCORE;
                            end
                        end
                        else if (rdc_train_timeout_cnt >= RDC_TRAIN_RESULT_TIMEOUT) begin
                            rdc_train_last_err_bitmap <= 16'hffff;
                            rdc_train_tap_err_bitmap  <= 16'hffff;
                            rdc_train_fail_mask       <= rdc_train_target_mask;
                            rdc_train_pass_mask       <= 16'h0000;
                            for (rdc_train_idx = 0;
                                 rdc_train_idx < 16;
                                 rdc_train_idx = rdc_train_idx + 1) begin
                                dq_delay_flat[(rdc_train_idx * 9) +: 9] <=
                                    rdc_train_saved_delay_flat[(rdc_train_idx * 9) +: 9];
                            end
                            rdc_train_verify_round    <= 2'd0;
                            rdc_train_timeout_cnt     <= 12'd0;
                            rdc_train_state           <= RDC_TRAIN_SCORE;
                        end
                        else begin
                            rdc_train_timeout_cnt <= rdc_train_timeout_cnt + 12'd1;
                        end
                    end
                    else if (rdc_check_valid == 1'b1) begin
                        rdc_train_timeout_cnt     <= 12'd0;
                        if (w_rdc_train_retry_needed == 1'b1) begin
                            rdc_train_retry_err0 <= rdc_err_bitmap;
                            rdc_train_retry_cnt  <= 2'd1;
                            rdc_train_state      <= RDC_TRAIN_MRR_LOW;
                        end
                        else if (rdc_train_retry_cnt == 2'd1) begin
                            rdc_train_retry_err1 <= rdc_err_bitmap;
                            rdc_train_retry_cnt  <= 2'd2;
                            rdc_train_state      <= RDC_TRAIN_MRR_LOW;
                        end
                        else begin
                            rdc_train_pattern_active <=
                                  (rdc_train_pattern_active & ~rdc_train_target_mask)
                                | (~w_rdc_train_result_err_bitmap & rdc_train_target_mask);
                            rdc_train_retry_err0 <= 16'h0000;
                            rdc_train_retry_err1 <= 16'h0000;
                            rdc_train_retry_cnt  <= 2'd0;

                            if ((rdc_train_dual_pattern == 1'b1) &&
                                (rdc_train_pattern_idx == 1'b0)) begin
                                rdc_train_last_err_bitmap <=
                                    w_rdc_train_result_err_bitmap;
                                rdc_train_tap_err_bitmap <=
                                    w_rdc_train_result_err_bitmap;
                                rdc_train_state <= RDC_TRAIN_NEXT_TAP;
                            end
                            else if (rdc_train_dual_pattern == 1'b1) begin
                                rdc_train_last_err_bitmap <= w_rdc_train_dual_err_bitmap;
                                rdc_train_tap_err_bitmap  <= w_rdc_train_dual_err_bitmap;
                                rdc_train_state           <= RDC_TRAIN_SCORE;
                            end
                            else begin
                                rdc_train_last_err_bitmap <=
                                    w_rdc_train_result_err_bitmap;
                                rdc_train_tap_err_bitmap <=
                                    w_rdc_train_result_err_bitmap;
                                rdc_train_state <= RDC_TRAIN_SCORE;
                            end
                        end
                    end
                    else if (rdc_train_timeout_cnt >= RDC_TRAIN_RESULT_TIMEOUT) begin
                        rdc_train_last_err_bitmap <= 16'hffff;
                        rdc_train_tap_err_bitmap  <= 16'hffff;
                        rdc_train_pattern_active  <=
                            rdc_train_pattern_active & ~rdc_train_target_mask;
                        rdc_train_retry_err0      <= 16'h0000;
                        rdc_train_retry_err1      <= 16'h0000;
                        rdc_train_retry_cnt       <= 2'd0;
                        rdc_train_timeout_cnt     <= 12'd0;
                        if ((rdc_train_dual_pattern == 1'b1) &&
                            (rdc_train_pattern_idx == 1'b0)) begin
                            rdc_train_state <= RDC_TRAIN_NEXT_TAP;
                        end
                        else begin
                            rdc_train_state <= RDC_TRAIN_SCORE;
                        end
                    end
                    else begin
                        rdc_train_timeout_cnt <= rdc_train_timeout_cnt + 12'd1;
                    end
                end

                RDC_TRAIN_SCORE: begin
                    if (rdc_train_verify_mode == 1'b1) begin
                        // Close the final verification read before reporting done.
                        mrw_r                <= 24'd0;
                        mrr_r                <= 32'd0;
                        rdc_train_verify_mode <= 1'b0;
                        rdc_train_state       <= RDC_TRAIN_DONE;
                    end
                    else begin
                        mrw_r                    <= 24'd0;
                        mrr_r                    <= 32'd0;
                        rdc_train_win_active    <= rdc_train_win_active_next;
                        rdc_train_win_left_flat <= rdc_train_win_left_flat_next;
                        rdc_train_win_len_flat  <= rdc_train_win_len_flat_next;
                        rdc_train_best_len_flat <= rdc_train_best_len_flat_next;
                        rdc_train_best_flat     <= rdc_train_best_flat_next;
                        rdc_train_left_flat     <= rdc_train_left_flat_next;
                        rdc_train_right_flat    <= rdc_train_right_flat_next;
                        rdc_train_state         <= RDC_TRAIN_NEXT_TAP;
                    end
                end

                RDC_TRAIN_NEXT_TAP: begin
                    if (w_rdc_train_last_tap == 1'b1) begin
                        if ((rdc_train_dual_pattern == 1'b1) &&
                            (rdc_train_pattern_idx == 1'b0)) begin
                            rdc_train_tap               <= rdc_train_tap_start;
                            rdc_train_pattern_idx       <= 1'b1;
                            rdc_train_pattern_mr_loaded <= 1'b0;
                            rdc_train_pattern_active    <= 16'h0000;
                            rdc_train_retry_err0        <= 16'h0000;
                            rdc_train_retry_err1        <= 16'h0000;
                            rdc_train_retry_cnt         <= 2'd0;
                            rdc_train_state             <= RDC_TRAIN_LOAD_TAP;
                        end
                        else begin
                            rdc_train_state <= RDC_TRAIN_FINISH_DQ;
                        end
                    end
                    else begin
                        rdc_train_tap   <= w_rdc_train_tap_next;
                        rdc_train_state <= RDC_TRAIN_LOAD_TAP;
                    end
                end

                RDC_TRAIN_FINISH_DQ: begin
                    rdc_train_pass_mask          <=
                        rdc_train_target_mask & ~w_rdc_train_window_fail_mask;
                    rdc_train_fail_mask          <= w_rdc_train_window_fail_mask;
                    rdc_train_verify_round      <= 2'd0;
                    rdc_train_verify_err_bitmap <= 16'h0000;
                    rdc_train_pattern_idx       <= 1'b0;
                    rdc_train_pattern_mr_loaded <= 1'b0;
                    mrw_r                       <= 24'd0;
                    mrr_r                       <= 32'd0;
                    for (rdc_train_idx = 0;
                         rdc_train_idx < 16;
                         rdc_train_idx = rdc_train_idx + 1) begin
                        if (w_rdc_train_window_fail_mask != 16'h0000) begin
                            dq_delay_flat[(rdc_train_idx * 9) +: 9] <=
                                rdc_train_saved_delay_flat[(rdc_train_idx * 9) +: 9];
                        end
                        else if ((rdc_train_idx >= rdc_train_dq_start) &&
                                 (rdc_train_idx <= rdc_train_dq_end)) begin
                            // Temporarily apply every candidate for the real center check.
                            dq_delay_flat[(rdc_train_idx * 9) +: 9] <=
                                rdc_train_best_flat[(rdc_train_idx * 9) +: 9];
                        end
                        else begin
                            dq_delay_flat[(rdc_train_idx * 9) +: 9] <=
                                rdc_train_saved_delay_flat[(rdc_train_idx * 9) +: 9];
                        end
                    end
                    rdc_train_win_active <= 16'h0000;
                    rdc_train_win_len_flat <= 160'd0;
                    rdc_train_pattern_active <= 16'h0000;
                    rdc_train_retry_err0 <= 16'h0000;
                    rdc_train_retry_err1 <= 16'h0000;
                    rdc_train_retry_cnt  <= 2'd0;
                    if (w_rdc_train_window_fail_mask != 16'h0000) begin
                        rdc_train_verify_mode <= 1'b0;
                        rdc_train_state       <= RDC_TRAIN_DONE;
                    end
                    else begin
                        rdc_train_verify_mode <= 1'b1;
                        rdc_train_state       <= RDC_TRAIN_WAIT_LOAD;
                    end
                end

                RDC_TRAIN_DONE: begin
                    rdc_train_busy  <= 1'b0;
                    rdc_train_done  <= 1'b1;
                    rdc_train_state <= RDC_TRAIN_IDLE;
                    mrw_r           <= 24'd0;
                    mrr_r           <= 32'd0;
                end

                default: begin
                    rdc_train_state <= RDC_TRAIN_IDLE;
                    rdc_train_busy  <= 1'b0;
                    mrw_r           <= 24'd0;
                    mrr_r           <= 32'd0;
                end
            endcase
        end
        else if (dq_delay_l_we == 1'b1) begin
            dq_delay_flat[  8:  0] <= dq_delay_wdat[ 8: 0];
            dq_delay_flat[ 17:  9] <= dq_delay_wdat[17: 9];
            dq_delay_flat[ 26: 18] <= dq_delay_wdat[26:18];
            dq_delay_flat[ 35: 27] <= dq_delay_wdat[35:27];
            dq_delay_flat[ 44: 36] <= dq_delay_wdat[44:36];
            dq_delay_flat[ 53: 45] <= dq_delay_wdat[53:45];
            dq_delay_flat[ 62: 54] <= dq_delay_wdat[62:54];
            dq_delay_flat[ 71: 63] <= dq_delay_wdat[71:63];
        end
        else if (dq_delay_h_we == 1'b1) begin
            dq_delay_flat[ 80: 72] <= dq_delay_wdat[ 8: 0];
            dq_delay_flat[ 89: 81] <= dq_delay_wdat[17: 9];
            dq_delay_flat[ 98: 90] <= dq_delay_wdat[26:18];
            dq_delay_flat[107: 99] <= dq_delay_wdat[35:27];
            dq_delay_flat[116:108] <= dq_delay_wdat[44:36];
            dq_delay_flat[125:117] <= dq_delay_wdat[53:45];
            dq_delay_flat[134:126] <= dq_delay_wdat[62:54];
            dq_delay_flat[143:135] <= dq_delay_wdat[71:63];
        end
        else begin
            dq_delay_flat         <= dq_delay_flat;
            mrr_r                 <= mrr_r;
            rdc_train_state       <= rdc_train_state;
            rdc_train_busy        <= rdc_train_busy;
            rdc_train_done        <= rdc_train_done;
            rdc_train_apply_best  <= rdc_train_apply_best;
            rdc_train_dq_start    <= rdc_train_dq_start;
            rdc_train_dq_end      <= rdc_train_dq_end;
            rdc_train_tap_start   <= rdc_train_tap_start;
            rdc_train_tap_stop    <= rdc_train_tap_stop;
            rdc_train_tap_step    <= rdc_train_tap_step;
            rdc_train_tap         <= rdc_train_tap;
        end
    end
end

endmodule
