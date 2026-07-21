`timescale 1ns / 1ps

`include "dram_driver_head.vh"

module tb_bar06_gf_stream_cfg;

/***************reg******************/
    reg                     clk                         ;
    reg                     rst_n                       ;
    reg      [  7:0]        sir_addr                    ;
    reg                     sir_read                    ;
    reg      [ 95:0]        sir_wdat                    ;
    reg                     sir_sel                     ;

/***************wire*****************/
    wire                    sir_dack                    ;
    wire     [ 95:0]        sir_rdat                    ;
    wire     [  9:0]        gf_act_cmd_gap_cnt          ;
    wire     [  9:0]        gf_rd_cmd_gap_cnt           ;
    wire     [  9:0]        gf_wr_cmd_gap_cnt           ;
    wire     [  9:0]        gf_pre_cmd_gap_cnt          ;
    wire     [  2:0]        gf_refresh_batch_num        ;
    wire     [  1:0]        gf_pattern_mode_cfg         ;
    wire     [  8:0]        rdc_train_scan_tap_sel      ;

/***************task*****************/
task write_stream_cfg;
    input    [  9:0]        act_gap                     ;
    input    [  9:0]        rd_gap                      ;
    input    [  9:0]        wr_gap                      ;
    input    [  9:0]        pre_gap                     ;
    input    [  2:0]        refresh_batch               ;
begin
    @(negedge clk);
    sir_addr = `bar06_GF_STREAM_CFG;
    sir_read = 1'b0;
    sir_wdat = {53'd0, refresh_batch, pre_gap, wr_gap, rd_gap, act_gap};
    sir_sel  = 1'b1;
    @(negedge clk);
    sir_sel  = 1'b0;
    sir_wdat = 96'd0;
end
endtask

task check_rdc_scan_readback;
    input    [  8:0]        tap_sel                     ;
    input    [  8:0]        tap_step                    ;
begin
    @(negedge clk);
    sir_addr = `bar06_RDC_TRAIN_SCAN;
    sir_read = 1'b0;
    sir_wdat = {78'd0, tap_step, tap_sel};
    sir_sel  = 1'b1;
    @(negedge clk);
    sir_sel  = 1'b0;
    sir_wdat = 96'd0;

    @(negedge clk);
    sir_addr = `bar06_RDC_TRAIN_SCAN;
    sir_read = 1'b1;
    sir_sel  = 1'b1;
    @(posedge clk);
    #1;

    if ((sir_rdat[8:0] !== tap_sel) ||
        (sir_rdat[17:9] !== tap_step) ||
        (sir_rdat[33:18] !== 16'hA55A)) begin
        $display("BAR06 RDC scan mismatch value=0x%024h", sir_rdat);
        $fatal(1);
    end

    @(negedge clk);
    sir_sel = 1'b0;
    @(posedge clk);
    #1;
    if (rdc_train_scan_tap_sel !== (tap_sel + tap_step)) begin
        $display("BAR06 RDC scan increment=%0d expected=%0d",
                 rdc_train_scan_tap_sel, tap_sel + tap_step);
        $fatal(1);
    end
end
endtask

task write_pattern_cfg;
    input    [  1:0]        pattern_mode                ;
begin
    @(negedge clk);
    sir_addr = `bar06_GF_PATTERN_CFG;
    sir_read = 1'b0;
    sir_wdat = {94'd0, pattern_mode};
    sir_sel  = 1'b1;
    @(negedge clk);
    sir_sel  = 1'b0;
    sir_wdat = 96'd0;
end
endtask

task check_pattern_cfg;
    input    [  1:0]        pattern_mode                ;
begin
    @(negedge clk);
    sir_addr = `bar06_GF_PATTERN_CFG;
    sir_read = 1'b1;
    sir_sel  = 1'b1;
    @(posedge clk);
    #1;

    if ((gf_pattern_mode_cfg !== pattern_mode) ||
        (sir_rdat[1:0] !== pattern_mode)) begin
        $display("BAR06 pattern mismatch output=%0d readback=%0d expected=%0d",
                 gf_pattern_mode_cfg, sir_rdat[1:0], pattern_mode);
        $fatal(1);
    end

    @(negedge clk);
    sir_sel = 1'b0;
end
endtask

task check_stream_cfg;
    input    [  9:0]        act_gap                     ;
    input    [  9:0]        rd_gap                      ;
    input    [  9:0]        wr_gap                      ;
    input    [  9:0]        pre_gap                     ;
    input    [  2:0]        refresh_batch               ;
begin
    @(negedge clk);
    sir_addr = `bar06_GF_STREAM_CFG;
    sir_read = 1'b1;
    sir_sel  = 1'b1;
    @(posedge clk);
    #1;

    if ((gf_act_cmd_gap_cnt   !== act_gap) ||
        (gf_rd_cmd_gap_cnt    !== rd_gap)  ||
        (gf_wr_cmd_gap_cnt    !== wr_gap)  ||
        (gf_pre_cmd_gap_cnt   !== pre_gap) ||
        (gf_refresh_batch_num !== refresh_batch)) begin
        $display("BAR06 register mismatch act=%0d rd=%0d wr=%0d pre=%0d batch=%0d",
                 gf_act_cmd_gap_cnt, gf_rd_cmd_gap_cnt,
                 gf_wr_cmd_gap_cnt, gf_pre_cmd_gap_cnt,
                 gf_refresh_batch_num);
        $fatal(1);
    end

    if (sir_rdat[42:0] !==
        {refresh_batch, pre_gap, wr_gap, rd_gap, act_gap}) begin
        $display("BAR06 readback mismatch value=0x%024h", sir_rdat);
        $fatal(1);
    end

    @(negedge clk);
    sir_sel = 1'b0;
end
endtask

/***************component************/
bar06 u_bar06 (
    .clk                            (clk                         ),
    .rst_n                          (rst_n                       ),
    .sir_addr                       (sir_addr                    ),
    .sir_read                       (sir_read                    ),
    .sir_wdat                       (sir_wdat                    ),
    .sir_sel                        (sir_sel                     ),
    .sir_dack                       (sir_dack                    ),
    .sir_rdat                       (sir_rdat                    ),
    .dq_delay_flat                  (144'd0                      ),
    .mrw_r                          (                            ),
    .read_capture_start_cnt         (                            ),
    .gf_capture_start_cnt           (                            ),
    .init_beat_offset               (                            ),
    .gf_beat_offset                 (                            ),
    .gf_rd_wck_start_cnt            (                            ),
    .gf_rd_wck_last_cnt             (                            ),
    .gf_wr_wck_start_cnt            (                            ),
    .gf_wr_wck_last_cnt             (                            ),
    .gf_read_done_cnt               (                            ),
    .gf_write_done_cnt              (                            ),
    .gf_act_cmd_gap_cnt             (gf_act_cmd_gap_cnt          ),
    .gf_rd_cmd_gap_cnt              (gf_rd_cmd_gap_cnt           ),
    .gf_wr_cmd_gap_cnt              (gf_wr_cmd_gap_cnt           ),
    .gf_pre_cmd_gap_cnt             (gf_pre_cmd_gap_cnt          ),
    .gf_refresh_batch_num           (gf_refresh_batch_num        ),
    .gf_pattern_mode_cfg            (gf_pattern_mode_cfg         ),
    .rdc_err_bitmap                 (16'd0                       ),
    .rdc_check_valid                (1'b0                        ),
    .rdc_check_pass                 (1'b0                        ),
    .rdc_train_init_en              (                            ),
    .rdc_train_apply_best_cfg       (                            ),
    .rdc_train_dual_pattern_cfg     (                            ),
    .rdc_train_dq_start_cfg         (                            ),
    .rdc_train_dq_end_cfg           (                            ),
    .rdc_train_tap_start_cfg        (                            ),
    .rdc_train_tap_stop_cfg         (                            ),
    .rdc_train_tap_step_cfg         (                            ),
    .rdc_train_dq_delay_l_we        (                            ),
    .rdc_train_dq_delay_h_we        (                            ),
    .rdc_train_dq_delay_wdat        (                            ),
    .rdc_train_scan_tap_sel         (rdc_train_scan_tap_sel      ),
    .rdc_train_state                (4'd0                        ),
    .rdc_train_busy                 (1'b0                        ),
    .rdc_train_done                 (1'b0                        ),
    .rdc_train_apply_best           (1'b0                        ),
    .rdc_train_dq_start             (4'd0                        ),
    .rdc_train_tap                  (9'd0                        ),
    .rdc_train_status_best_len      (10'd0                       ),
    .rdc_train_pass_mask            (16'd0                       ),
    .rdc_train_fail_mask            (16'd0                       ),
    .rdc_train_last_err_bitmap      (16'd0                       ),
    .rdc_train_init_ready           (1'b0                        ),
    .rdc_train_pass_all             (1'b0                        ),
    .rdc_train_best_flat            (144'd0                      ),
    .rdc_train_left_flat            (144'd0                      ),
    .rdc_train_right_flat           (144'd0                      ),
    .rdc_train_scan_pass_bitmap     (16'hA55A                    )
);

/***************always***************/
always #2.5 clk = ~clk;

/***************initial**************/
initial begin
    clk      = 1'b0;
    rst_n    = 1'b0;
    sir_addr = 8'd0;
    sir_read = 1'b0;
    sir_wdat = 96'd0;
    sir_sel  = 1'b0;

    repeat (4) @(posedge clk);
    rst_n = 1'b1;

    check_stream_cfg(10'd16, 10'd12, 10'd12, 10'd16, 3'd1);
    write_stream_cfg(10'd6, 10'd7, 10'd11, 10'd7, 3'd4);
    check_stream_cfg(10'd6, 10'd7, 10'd11, 10'd7, 3'd4);
    // BAR06 uses code 0 for the internal eight-refresh batch.
    write_stream_cfg(10'd6, 10'd10, 10'd11, 10'd7, 3'd0);
    check_stream_cfg(10'd6, 10'd10, 10'd11, 10'd7, 3'd0);
    write_stream_cfg(10'd6, 10'd7, 10'd11, 10'd7, 3'd3);
    check_stream_cfg(10'd6, 10'd7, 10'd11, 10'd7, 3'd1);
    check_pattern_cfg(2'd0);
    write_pattern_cfg(2'd0);
    check_pattern_cfg(2'd0);
    write_pattern_cfg(2'd1);
    check_pattern_cfg(2'd1);
    write_pattern_cfg(2'd2);
    check_pattern_cfg(2'd0);
    check_rdc_scan_readback(9'd230, 9'd2);

    $display("SIM PASS: BAR06 GF stream/pattern/scan config");
    $finish;
end

endmodule
