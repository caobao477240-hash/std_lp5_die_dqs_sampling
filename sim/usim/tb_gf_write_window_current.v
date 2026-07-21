`timescale 1ns / 1ps

// Focused current-RTL check for the GF WRITE data window.
// It prints the exact 64-bit word driven into the DQ SERDES for each
// cnt_write cycle under the fixed RTL GF window values used on hardware.
module tb_gf_write_window_current #(
    parameter READ_CAPTURE_START  = 8'h10
);

reg         clk;
reg         rst_n;
reg         total_en;
reg         inner_en;

wire        inner_done;
wire [20:0] gf_state;
wire        gf_en_write;
wire [9:0]  gf_cnt_write;
wire [1:0]  wave_wck_a_run_en;
wire [1:0]  wave_wck_a_phase;
wire [63:0] wave_dq_a_tx_word;
wire        wave_dq_oe;

integer timeout_count;
reg     first_write_dump_done;

lpddr5_gf_engine #(
    .T_RCD         (6),
    .T_READ        (40),
    .T_WRITE       (28),
    .T_RPab        (8),
    .TRFCab        (10),
    .T_REFI_CYCLES (781)
) dut (
    .clk                             (clk),
    .rst_n                           (rst_n),
    .engine_inhibit                  (1'b0),
    .idd_ck_stop                     (1'b0),
    .GF_start_col                    (6'd0),
    .GF_end_col                      (6'd0),
    .GF_start_row                    (18'd0),
    .GF_end_row                      (18'd0),
    .GF_start_bg                     (2'd0),
    .GF_end_bg                       (2'd3),
    .GF_start_ba                     (2'd0),
    .GF_end_ba                       (2'd3),
    .gf_test_en                      (total_en),
    .gf_pass_start                   (inner_en),
    .gf_op_mode                      (2'd0),
    .gf_read_data_sel                (1'b0),
    .gf_write_data_sel               (1'b0),
    .march_y_sequence                (1'b0),
    .die_message                     (8'h18),
    .read_capture_start_cnt          (READ_CAPTURE_START),
    .gf_rd_wck_start_cnt             (10'd5),
    .gf_rd_wck_last_cnt              (10'd26),
    .gf_wr_wck_start_cnt             (10'd5),
    .gf_wr_wck_last_cnt              (10'd18),
    .gf_read_done_cnt                (10'd39),
    .gf_write_done_cnt               (10'd27),
    .gf_act_cmd_gap_cnt              (10'd16),
    .gf_rd_cmd_gap_cnt               (10'd12),
    .gf_wr_cmd_gap_cnt               (10'd10),
    .gf_pre_cmd_gap_cnt              (10'd16),
    .gf_refresh_batch_num            (3'd1),
    .gf_pattern_mode_cfg             (2'd0),
    .dq_a_burst_flat                 (256'h0),
    .dq_a_burst_valid                (1'b0),
    .err_cnt_GF                      (),
    .err_block_cnt                   (),
    .err_block_message               (),
    .gf_pass_done                    (inner_done),
    .gf_state                        (gf_state),
    .gf_pass_start_d                 (),
    .gf_en_read                      (),
    .gf_en_write                     (gf_en_write),
    .rx_dq_capture_en                (),
    .gf_err_flag                     (),
    .gf_cnt_read_value               (),
    .gf_cnt_write_value              (gf_cnt_write),
    .gf_compare_window               (),
    .gf_compare_mismatch_odd         (),
    .gf_compare_mismatch_even        (),
    .gf_access_addr                  (),
    .gf_read_expected_beat           (),
    .gf_cnt_ba                       (),
    .gf_cnt_bg                       (),
    .gf_cnt_row                      (),
    .gf_cnt_col                      (),
    .gf_cnt_row_ns                   (),
    .ascii_state                     (),
    .wave_ck_a_run_en                (),
    .wave_cs_a_0_fall                  (),
    .wave_cs_a_0_rise                  (),
    .wave_ca_a_fall                    (),
    .wave_ca_a_rise                    (),
    .wave_wck_a_run_en                   (wave_wck_a_run_en),
    .wave_wck_a_phase                   (wave_wck_a_phase),
    .wave_dq_a_tx_word               (wave_dq_a_tx_word),
    .wave_dq_oe                      (wave_dq_oe)
);

always #2.5 clk = ~clk;

always @(posedge clk) begin
    if ((rst_n == 1'b1) && (gf_en_write == 1'b1)) begin
        $display("WR_WINDOW t=%0t cnt_write=%02h wr_rel=%02h oe=%0b wck=%02b/%02b tx=%04h %04h %04h %04h",
                 $time,
                 gf_cnt_write[7:0],
                 gf_cnt_write[7:0] - 8'd10,
                 wave_dq_oe,
                 wave_wck_a_phase,
                 wave_wck_a_run_en,
                 wave_dq_a_tx_word[15:0],
                 wave_dq_a_tx_word[31:16],
                 wave_dq_a_tx_word[47:32],
                 wave_dq_a_tx_word[63:48]);

        if ((gf_cnt_write[7:0] == 8'h14) &&
            (first_write_dump_done == 1'b0)) begin
            first_write_dump_done <= 1'b1;
            $display("TB DONE: first write-window dump complete");
            $finish;
        end
    end
end

initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    total_en = 1'b0;
    inner_en = 1'b0;
    timeout_count = 0;
    first_write_dump_done = 1'b0;

    $display("TB_CFG fixed RTL GF window: data=05..13 payload=0a..0d wck=05..12 read_capture=%02h",
             READ_CAPTURE_START);

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (3) @(posedge clk);
    total_en = 1'b1;
    inner_en = 1'b1;

    while ((inner_done == 1'b0) && (timeout_count < 10000)) begin
        @(posedge clk);
        timeout_count = timeout_count + 1;
    end

    if (timeout_count >= 10000) begin
        $display("TB FAIL: timeout state=%h", gf_state);
    end
    else begin
        $display("TB DONE: write-window dump complete");
    end
    $finish;
end

endmodule
