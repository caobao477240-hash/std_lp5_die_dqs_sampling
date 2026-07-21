`include "dram_driver_head.vh"

/**
 * bar06
 * DUT calibration parameter register block.
 *
 * This block only keeps BAR-visible registers and readback muxes.
 * RDC scanning is implemented by lpddr5_init/rdc_train.
 */
module bar06 (
    // Clock and BAR06 serial register bus
    input  wire                 clk                         ,
    input  wire                 rst_n                       ,
    input  wire [  7:0]         sir_addr                    ,
    input  wire                 sir_read                    ,
    input  wire [ 95:0]         sir_wdat                    ,
    input  wire                 sir_sel                     ,
    output wire                 sir_dack                    ,
    output wire [ 95:0]         sir_rdat                    ,

    // DQ delay readback; delay storage is owned by rdc_train.
    input  wire [143:0]         dq_delay_flat               ,

    // BAR06_MRW: runtime debug MRW command, not used by default init/GF flow
    output reg  [ 23:0]         mrw_r                       ,

    // BAR06_CAPTURE_CFG: read capture, burst slice, WCK, and GF done timing.
    output reg  [  7:0]         read_capture_start_cnt      ,
    output reg  [  7:0]         gf_capture_start_cnt        ,
    output reg  [  3:0]         init_beat_offset            ,
    output reg  [  3:0]         gf_beat_offset              ,
    output reg  [  9:0]         gf_rd_wck_start_cnt         ,
    output reg  [  9:0]         gf_rd_wck_last_cnt          ,
    output reg  [  9:0]         gf_wr_wck_start_cnt         ,
    output reg  [  9:0]         gf_wr_wck_last_cnt          ,
    output reg  [  9:0]         gf_read_done_cnt            ,
    output reg  [  9:0]         gf_write_done_cnt           ,
    output reg  [  9:0]         gf_act_cmd_gap_cnt          ,
    output reg  [  9:0]         gf_rd_cmd_gap_cnt           ,
    output reg  [  9:0]         gf_wr_cmd_gap_cnt           ,
    output reg  [  9:0]         gf_pre_cmd_gap_cnt          ,
    output reg  [  2:0]         gf_refresh_batch_num        ,
    output reg  [  1:0]         gf_pattern_mode_cfg         ,

    // BAR06_RDC_STATUS: latest single RDC check result.
    input  wire [ 15:0]         rdc_err_bitmap              ,
    input  wire                 rdc_check_valid             ,
    input  wire                 rdc_check_pass              ,

    // BAR06_RDC_TRAIN_CTRL: init-time RDC training configuration.
    output reg                  rdc_train_init_en           ,
    output reg                  rdc_train_apply_best_cfg    ,
    output reg                  rdc_train_dual_pattern_cfg  ,
    output reg  [  3:0]         rdc_train_dq_start_cfg      ,
    output reg  [  3:0]         rdc_train_dq_end_cfg        ,
    output reg  [  8:0]         rdc_train_tap_start_cfg     ,
    output reg  [  8:0]         rdc_train_tap_stop_cfg      ,
    output reg  [  8:0]         rdc_train_tap_step_cfg      ,
    output wire                 rdc_train_dq_delay_l_we     ,
    output wire                 rdc_train_dq_delay_h_we     ,
    output wire [ 95:0]         rdc_train_dq_delay_wdat     ,
    output reg  [  8:0]         rdc_train_scan_tap_sel      ,

    // BAR06_RDC_TRAIN_STATUS and window readback.
    input  wire [  3:0]         rdc_train_state             ,
    input  wire                 rdc_train_busy              ,
    input  wire                 rdc_train_done              ,
    input  wire                 rdc_train_apply_best        ,
    input  wire [  3:0]         rdc_train_dq_start          ,
    input  wire [  8:0]         rdc_train_tap               ,
    input  wire [  9:0]         rdc_train_status_best_len   ,
    input  wire [ 15:0]         rdc_train_pass_mask         ,
    input  wire [ 15:0]         rdc_train_fail_mask         ,
    input  wire [ 15:0]         rdc_train_last_err_bitmap   ,
    input  wire                 rdc_train_init_ready        ,
    input  wire                 rdc_train_pass_all          ,
    input  wire [143:0]         rdc_train_best_flat         ,
    input  wire [143:0]         rdc_train_left_flat         ,
    input  wire [143:0]         rdc_train_right_flat        ,
    input  wire [ 15:0]         rdc_train_scan_pass_bitmap
);

/***************parameter*************/
    localparam     [   7: 0]      CAPTURE_START_DFT           = 8'h11  ;
    localparam     [   3: 0]      BURST_BEAT_OFFSET_DFT       = 4'd0   ;
    localparam     [   9: 0]      GF_RD_WCK_START_DFT         = 10'd5  ;
    localparam     [   9: 0]      GF_RD_WCK_LAST_DFT          = 10'd26 ;
    localparam     [   9: 0]      GF_WR_WCK_START_DFT         = 10'd5  ;
    localparam     [   9: 0]      GF_WR_WCK_LAST_DFT          = 10'd18 ;
    localparam     [   9: 0]      GF_READ_DONE_DFT            = 10'd39 ;
    localparam     [   9: 0]      GF_WRITE_DONE_DFT           = 10'd27 ;
    localparam     [   9: 0]      GF_ACT_CMD_GAP_DFT          = 10'd16 ;
    localparam     [   9: 0]      GF_RD_CMD_GAP_DFT           = 10'd12 ;
    localparam     [   9: 0]      GF_WR_CMD_GAP_DFT           = 10'd12 ;
    localparam     [   9: 0]      GF_PRE_CMD_GAP_DFT          = 10'd16 ;
    localparam     [   9: 0]      GF_CMD_GAP_MAX              = 10'd64 ;
    localparam     [   2: 0]      GF_REFRESH_BATCH_DFT        = 3'd1   ;
    localparam     [   1: 0]      GF_PATTERN_ADDR_TOGGLE      = 2'd0   ;
    localparam     [   1: 0]      GF_PATTERN_WRITE_STRESS     = 2'd1   ;
    localparam     [   1: 0]      GF_PATTERN_MODE_DFT         = GF_PATTERN_ADDR_TOGGLE;
    localparam     [   8: 0]      RDC_TAP_START_DFT           = 9'd0   ;
    localparam     [   8: 0]      RDC_TAP_STOP_DFT            = 9'd300 ;
    localparam     [   8: 0]      RDC_TAP_STEP_DFT            = 9'd2   ;
    localparam                    RDC_DUAL_PATTERN_DFT       = 1'b1   ;

/***************reg*******************/
    reg                  [  95: 0]      sir_rdat_next              ;
/***************wire******************/
// MRW and BAR write decode
    wire                                w_bar_write_en             ;
    wire                                w_bar_write_idle_en        ;
    wire                                w_write_mrw                ;

// CAPTURE_CFG
    wire                                w_write_capture_cfg        ;
    wire                                w_write_gf_stream_cfg      ;
    wire                                w_write_gf_pattern_cfg     ;

// RDC_TRAIN and DQ delay
    wire                                w_write_dq_delay_l         ;
    wire                                w_write_dq_delay_h         ;
    wire                                w_write_rdc_train_cfg      ;
    wire                                w_write_rdc_train_scan     ;
    wire                                w_read_rdc_train_scan      ;
    reg  [  8:0]                        rdc_train_scan_tap_step     ;
    wire [  9:0]                        w_rdc_train_scan_tap_next   ;

/***************assign****************/
// MRW and BAR write decode
assign w_bar_write_en            = (sir_sel == 1'b1) && (sir_read == 1'b0);
assign w_bar_write_idle_en       = (w_bar_write_en == 1'b1) && (rdc_train_busy == 1'b0);
assign w_write_mrw               = w_bar_write_idle_en && (sir_addr == `bar06_MRW);

// CAPTURE_CFG
assign w_write_capture_cfg       = w_bar_write_idle_en && (sir_addr == `bar06_CAPTURE_CFG);
assign w_write_gf_stream_cfg     = w_bar_write_idle_en && (sir_addr == `bar06_GF_STREAM_CFG);
assign w_write_gf_pattern_cfg    = w_bar_write_idle_en && (sir_addr == `bar06_GF_PATTERN_CFG);

// RDC_TRAIN and DQ delay
assign w_write_dq_delay_l        = w_bar_write_idle_en && (sir_addr == `bar06_DQ_DELAY_L);
assign w_write_dq_delay_h        = w_bar_write_idle_en && (sir_addr == `bar06_DQ_DELAY_H);
assign w_write_rdc_train_cfg     = w_bar_write_idle_en && (sir_addr == `bar06_RDC_TRAIN_CTRL);
assign w_write_rdc_train_scan    = w_bar_write_idle_en && (sir_addr == `bar06_RDC_TRAIN_SCAN);
assign w_read_rdc_train_scan     = sir_sel && sir_read &&
                                   (sir_addr == `bar06_RDC_TRAIN_SCAN);
assign w_rdc_train_scan_tap_next = {1'b0, rdc_train_scan_tap_sel} +
                                   {1'b0, rdc_train_scan_tap_step};

assign rdc_train_dq_delay_l_we    = w_write_dq_delay_l;
assign rdc_train_dq_delay_h_we    = w_write_dq_delay_h;
assign rdc_train_dq_delay_wdat    = sir_wdat;

/***************always****************/
always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) begin
        mrw_r <= 24'd0;
    end
    else if (w_write_mrw == 1'b1) begin
        mrw_r <= sir_wdat[23:0];
    end
    else begin
        mrw_r <= mrw_r;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) begin
        gf_pattern_mode_cfg <= GF_PATTERN_MODE_DFT;
    end
    else if (w_write_gf_pattern_cfg == 1'b1) begin
        if (sir_wdat[1:0] == GF_PATTERN_WRITE_STRESS)
            gf_pattern_mode_cfg <= GF_PATTERN_WRITE_STRESS;
        else
            gf_pattern_mode_cfg <= GF_PATTERN_ADDR_TOGGLE;
    end
    else begin
        gf_pattern_mode_cfg <= gf_pattern_mode_cfg;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) begin
        rdc_train_scan_tap_sel  <= 9'd0;
        rdc_train_scan_tap_step <= 9'd1;
    end
    else if (w_write_rdc_train_scan == 1'b1) begin
        rdc_train_scan_tap_sel  <= sir_wdat[8:0];
        rdc_train_scan_tap_step <= (sir_wdat[17:9] == 9'd0) ?
                                   9'd1 : sir_wdat[17:9];
    end
    else if (w_read_rdc_train_scan == 1'b1) begin
        rdc_train_scan_tap_sel <= (w_rdc_train_scan_tap_next > 10'd511) ?
                                  9'd511 : w_rdc_train_scan_tap_next[8:0];
        rdc_train_scan_tap_step <= rdc_train_scan_tap_step;
    end
    else begin
        rdc_train_scan_tap_sel  <= rdc_train_scan_tap_sel;
        rdc_train_scan_tap_step <= rdc_train_scan_tap_step;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) begin
        read_capture_start_cnt <= CAPTURE_START_DFT;
        gf_capture_start_cnt   <= CAPTURE_START_DFT;
        init_beat_offset       <= BURST_BEAT_OFFSET_DFT;
        gf_beat_offset         <= BURST_BEAT_OFFSET_DFT;
        gf_rd_wck_start_cnt    <= GF_RD_WCK_START_DFT;
        gf_rd_wck_last_cnt     <= GF_RD_WCK_LAST_DFT;
        gf_wr_wck_start_cnt    <= GF_WR_WCK_START_DFT;
        gf_wr_wck_last_cnt     <= GF_WR_WCK_LAST_DFT;
        gf_read_done_cnt       <= GF_READ_DONE_DFT;
        gf_write_done_cnt      <= GF_WRITE_DONE_DFT;
    end
    else if (w_write_capture_cfg == 1'b1) begin
        read_capture_start_cnt <= sir_wdat[7:0];
        gf_capture_start_cnt   <= (sir_wdat[15:8] == 8'd0) ?
                                  CAPTURE_START_DFT : sir_wdat[15:8];
        init_beat_offset       <= sir_wdat[19:16];
        gf_beat_offset         <= sir_wdat[23:20];
        gf_rd_wck_start_cnt    <= sir_wdat[33:24];
        gf_rd_wck_last_cnt     <= (sir_wdat[43:34] == 10'd0) ?
                                  GF_RD_WCK_LAST_DFT : sir_wdat[43:34];
        gf_wr_wck_start_cnt    <= sir_wdat[53:44];
        gf_wr_wck_last_cnt     <= (sir_wdat[63:54] == 10'd0) ?
                                  GF_WR_WCK_LAST_DFT : sir_wdat[63:54];
        gf_read_done_cnt       <= (sir_wdat[73:64] == 10'd0) ?
                                  GF_READ_DONE_DFT : sir_wdat[73:64];
        gf_write_done_cnt      <= (sir_wdat[83:74] == 10'd0) ?
                                  GF_WRITE_DONE_DFT : sir_wdat[83:74];
    end
    else begin
        read_capture_start_cnt <= read_capture_start_cnt;
        gf_capture_start_cnt   <= gf_capture_start_cnt;
        init_beat_offset       <= init_beat_offset;
        gf_beat_offset         <= gf_beat_offset;
        gf_rd_wck_start_cnt    <= gf_rd_wck_start_cnt;
        gf_rd_wck_last_cnt     <= gf_rd_wck_last_cnt;
        gf_wr_wck_start_cnt    <= gf_wr_wck_start_cnt;
        gf_wr_wck_last_cnt     <= gf_wr_wck_last_cnt;
        gf_read_done_cnt       <= gf_read_done_cnt;
        gf_write_done_cnt      <= gf_write_done_cnt;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) begin
        gf_act_cmd_gap_cnt    <= GF_ACT_CMD_GAP_DFT;
        gf_rd_cmd_gap_cnt     <= GF_RD_CMD_GAP_DFT;
        gf_wr_cmd_gap_cnt     <= GF_WR_CMD_GAP_DFT;
        gf_pre_cmd_gap_cnt    <= GF_PRE_CMD_GAP_DFT;
        gf_refresh_batch_num <= GF_REFRESH_BATCH_DFT;
    end
    else if (w_write_gf_stream_cfg == 1'b1) begin
        gf_act_cmd_gap_cnt    <= (sir_wdat[9:0] == 10'd0) ?
                                 GF_ACT_CMD_GAP_DFT :
                                 ((sir_wdat[9:0] > GF_CMD_GAP_MAX) ?
                                  GF_CMD_GAP_MAX : sir_wdat[9:0]);
        gf_rd_cmd_gap_cnt     <= (sir_wdat[19:10] == 10'd0) ?
                                 GF_RD_CMD_GAP_DFT :
                                 ((sir_wdat[19:10] > GF_CMD_GAP_MAX) ?
                                  GF_CMD_GAP_MAX : sir_wdat[19:10]);
        gf_wr_cmd_gap_cnt     <= (sir_wdat[29:20] == 10'd0) ?
                                 GF_WR_CMD_GAP_DFT :
                                 ((sir_wdat[29:20] > GF_CMD_GAP_MAX) ?
                                  GF_CMD_GAP_MAX : sir_wdat[29:20]);
        gf_pre_cmd_gap_cnt    <= (sir_wdat[39:30] == 10'd0) ?
                                 GF_PRE_CMD_GAP_DFT :
                                 ((sir_wdat[39:30] > GF_CMD_GAP_MAX) ?
                                  GF_CMD_GAP_MAX : sir_wdat[39:30]);
        // Three-bit code 0 represents the JEDEC maximum batch of eight.
        gf_refresh_batch_num <= (sir_wdat[42:40] == 3'd0) ?
                                3'd0 :
                                ((sir_wdat[42:40] == 3'd4) ?
                                 3'd4 : 3'd1);
    end
    else begin
        gf_act_cmd_gap_cnt    <= gf_act_cmd_gap_cnt;
        gf_rd_cmd_gap_cnt     <= gf_rd_cmd_gap_cnt;
        gf_wr_cmd_gap_cnt     <= gf_wr_cmd_gap_cnt;
        gf_pre_cmd_gap_cnt    <= gf_pre_cmd_gap_cnt;
        gf_refresh_batch_num <= gf_refresh_batch_num;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) begin
        rdc_train_init_en        <= 1'b0;
        rdc_train_apply_best_cfg <= 1'b1;
        rdc_train_dual_pattern_cfg <= RDC_DUAL_PATTERN_DFT;
        rdc_train_dq_start_cfg   <= 4'd0;
        rdc_train_dq_end_cfg     <= 4'd15;
        rdc_train_tap_start_cfg  <= RDC_TAP_START_DFT;
        rdc_train_tap_stop_cfg   <= RDC_TAP_STOP_DFT;
        rdc_train_tap_step_cfg   <= RDC_TAP_STEP_DFT;
    end
    else if (w_write_rdc_train_cfg == 1'b1) begin
        rdc_train_init_en        <= sir_wdat[2];
        rdc_train_apply_best_cfg <= sir_wdat[1];
        rdc_train_dual_pattern_cfg <= sir_wdat[39];
        rdc_train_dq_start_cfg   <= sir_wdat[7:4];
        rdc_train_dq_end_cfg     <= (sir_wdat[11:8] < sir_wdat[7:4]) ?
                                    sir_wdat[7:4] : sir_wdat[11:8];
        rdc_train_tap_start_cfg  <= sir_wdat[20:12];
        rdc_train_tap_stop_cfg   <= (sir_wdat[29:21] < sir_wdat[20:12]) ?
                                    sir_wdat[20:12] : sir_wdat[29:21];
        rdc_train_tap_step_cfg   <= (sir_wdat[38:30] == 9'd0) ?
                                    9'd1 : sir_wdat[38:30];
    end
    else begin
        rdc_train_init_en        <= rdc_train_init_en;
        rdc_train_apply_best_cfg <= rdc_train_apply_best_cfg;
        rdc_train_dual_pattern_cfg <= rdc_train_dual_pattern_cfg;
        rdc_train_dq_start_cfg   <= rdc_train_dq_start_cfg;
        rdc_train_dq_end_cfg     <= rdc_train_dq_end_cfg;
        rdc_train_tap_start_cfg  <= rdc_train_tap_start_cfg;
        rdc_train_tap_stop_cfg   <= rdc_train_tap_stop_cfg;
        rdc_train_tap_step_cfg   <= rdc_train_tap_step_cfg;
    end
end

always @(*) begin
    case (sir_addr)
        `bar06_CAPTURE_CFG: begin
            sir_rdat_next = {
                12'h000,
                gf_write_done_cnt,
                gf_read_done_cnt,
                gf_wr_wck_last_cnt,
                gf_wr_wck_start_cnt,
                gf_rd_wck_last_cnt,
                gf_rd_wck_start_cnt,
                gf_beat_offset,
                init_beat_offset,
                gf_capture_start_cnt,
                read_capture_start_cnt
            };
        end

        `bar06_GF_STREAM_CFG: begin
            sir_rdat_next = {
                53'd0,
                gf_refresh_batch_num,
                gf_pre_cmd_gap_cnt,
                gf_wr_cmd_gap_cnt,
                gf_rd_cmd_gap_cnt,
                gf_act_cmd_gap_cnt
            };
        end

        `bar06_GF_PATTERN_CFG: begin
            sir_rdat_next = {94'd0, gf_pattern_mode_cfg};
        end

        `bar06_RDC_TRAIN_SCAN: begin
            sir_rdat_next = {
                62'd0,
                rdc_train_scan_pass_bitmap,
                rdc_train_scan_tap_step,
                rdc_train_scan_tap_sel
            };
        end

        `bar06_DQ_DELAY_L: begin
            sir_rdat_next = {24'h000000, dq_delay_flat[ 71: 0]};
        end

        `bar06_DQ_DELAY_H: begin
            sir_rdat_next = {24'h000000, dq_delay_flat[143:72]};
        end

        `bar06_RDC_STATUS: begin
            sir_rdat_next = {
                72'h0000_0000_0000_0000_00,
                6'h00,
                rdc_check_pass,
                rdc_check_valid,
                rdc_err_bitmap
            };
        end

        `bar06_RDC_TRAIN_CTRL: begin
            sir_rdat_next = {
                56'h0000_0000_0000_00,
                rdc_train_dual_pattern_cfg,
                rdc_train_tap_step_cfg,
                rdc_train_tap_stop_cfg,
                rdc_train_tap_start_cfg,
                rdc_train_dq_end_cfg,
                rdc_train_dq_start_cfg,
                1'b0,
                rdc_train_init_en,
                rdc_train_apply_best_cfg,
                1'b0
            };
        end

        `bar06_RDC_TRAIN_STATUS: begin
            sir_rdat_next = {
                8'h00,
                rdc_train_fail_mask,
                rdc_train_pass_mask,
                rdc_train_last_err_bitmap,
                rdc_train_status_best_len,
                rdc_train_tap,
                rdc_train_dq_start,
                rdc_train_state,
                9'h000,
                rdc_train_init_ready,
                rdc_train_pass_all,
                rdc_train_done,
                rdc_train_busy
            };
        end

        `bar06_RDC_TRAIN_BEST_L: begin
            sir_rdat_next = {24'h000000, rdc_train_best_flat[ 71: 0]};
        end

        `bar06_RDC_TRAIN_BEST_H: begin
            sir_rdat_next = {24'h000000, rdc_train_best_flat[143:72]};
        end

        `bar06_RDC_TRAIN_LEFT_L: begin
            sir_rdat_next = {24'h000000, rdc_train_left_flat[ 71: 0]};
        end

        `bar06_RDC_TRAIN_LEFT_H: begin
            sir_rdat_next = {24'h000000, rdc_train_left_flat[143:72]};
        end

        `bar06_RDC_TRAIN_RIGHT_L: begin
            sir_rdat_next = {24'h000000, rdc_train_right_flat[ 71: 0]};
        end

        `bar06_RDC_TRAIN_RIGHT_H: begin
            sir_rdat_next = {24'h000000, rdc_train_right_flat[143:72]};
        end

        default: begin
            sir_rdat_next = 96'h0000_0000_0000_0000_0000_0000;
        end
    endcase
end

bar_response u_bar_response (
    .clk           (clk           ),
    .rst_n         (rst_n         ),
    .sir_sel       (sir_sel       ),
    .sir_read      (sir_read      ),
    .sir_rdat_next (sir_rdat_next ),
    .sir_dack      (sir_dack      ),
    .sir_rdat      (sir_rdat      )
);

endmodule
