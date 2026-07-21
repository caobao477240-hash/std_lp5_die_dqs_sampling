`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Module Name:     tb_gf_refresh_scheduler
// Description:
//   Focused regression for GF scheduler refresh insertion. The test forces a
//   short tREFI so refresh must be serviced between complete column accesses.
//////////////////////////////////////////////////////////////////////////////////

module tb_gf_refresh_scheduler #(
    parameter [9:0] TRFCAB_TEST       = 10,
    parameter [9:0] TRPAB_TEST        = 12,
    parameter [3:0] REFRESH_BATCH_TEST = 4'd1,
    parameter [9:0] T_REFI_TEST        = 120,
    parameter [5:0] END_COL_TEST       = 6'd5
);

reg          clk;
reg          rst_n;
reg          gf_test_en;
reg          gf_pass_start;

wire [20:0]  gf_state;
wire         gf_pass_done;
wire         gf_en_read;
wire         gf_en_write;
wire [9:0]   gf_cnt_read;
wire [9:0]   gf_cnt_write;
wire         gf_compare_mismatch_odd;
wire         gf_compare_mismatch_even;
wire [15:0]  gf_read_expected_beat;
wire [2:0]   refresh_batch_cfg;

integer      timeout_count;
integer      sched_seen;
integer      pre_refresh_seen;
integer      refresh_seen;
integer      refresh_service_count;
integer      refresh_command_count;
integer      precharge_service_count;
integer      precharge_command_count;
integer      refresh_command_in_service;
integer      refresh_command_cycle_last;
integer      cycle_count;
integer      compare_count;
integer      fail_count;
reg          rw_wait_write;
reg          refresh_state_d;
reg          precharge_state_d;
reg          precharge_cmd_d;
reg [255:0]  dq_burst_flat_r;
reg          dq_burst_valid_r;

localparam [7:0]  READ_CAPTURE_START       = 8'd10;
localparam [20:0] GF_SCHED_TB              = 21'b0_0000_0000_0000_1000_0001;
localparam [20:0] GF_READ_TB               = 21'b0_0000_0000_0100_0000_0000;
localparam [20:0] GF_WRITE_AFTER_READ_TB   = 21'b0_0000_0000_0100_0000_0001;
localparam [20:0] GF_PRECHARGING_TB        = 21'b0_0000_0000_1000_0000_0000;
localparam [20:0] GF_REFRESH_TB            = 21'b0_0000_0000_1000_0000_0001;
localparam [20:0] GF_PRE_REFRESH_TB        = 21'b0_0000_0000_1000_0000_0010;

function [255:0] tb_address_toggle_burst;
    input [15:0] addr_pattern;
    integer beat;
    begin
        tb_address_toggle_burst = 256'd0;
        for (beat = 0; beat < 16; beat = beat + 1) begin
            tb_address_toggle_burst[(16 * beat) +: 16] =
                (beat[0] == 1'b1) ? ~addr_pattern : addr_pattern;
        end
    end
endfunction

assign refresh_batch_cfg = (REFRESH_BATCH_TEST == 4'd8) ?
                           3'd0 : REFRESH_BATCH_TEST[2:0];

lpddr5_gf_engine #(
    .T_RCD                          (6                          ),
    .T_READ                         (40                         ),
    .T_WRITE                        (28                         ),
    .T_RPab                         (TRPAB_TEST                ),
    .TRFCab                         (TRFCAB_TEST                ),
    .T_REFI_CYCLES                  (T_REFI_TEST                )
) U_engine (
    .clk                            (clk                        ),
    .rst_n                          (rst_n                      ),
    .engine_inhibit                 (1'b0                       ),
    .idd_ck_stop                    (1'b0                       ),
    .GF_start_col                   (6'd0                       ),
    .GF_end_col                     (END_COL_TEST               ),
    .GF_start_row                   (18'd0                      ),
    .GF_end_row                     (18'd0                      ),
    .GF_start_bg                    (2'd0                       ),
    .GF_end_bg                      (2'd0                       ),
    .GF_start_ba                    (2'd0                       ),
    .GF_end_ba                      (2'd0                       ),
    .gf_test_en                     (gf_test_en                 ),
    .gf_pass_start                  (gf_pass_start              ),
    .gf_op_mode                     (2'd2                       ),
    .gf_read_data_sel               (1'b0                       ),
    .gf_write_data_sel              (1'b1                       ),
    .march_y_sequence               (1'b0                       ),
    .die_message                    (8'h18                      ),
    .read_capture_start_cnt         (READ_CAPTURE_START         ),
    .gf_rd_wck_start_cnt            (10'd5                      ),
    .gf_rd_wck_last_cnt             (10'd26                     ),
    .gf_wr_wck_start_cnt            (10'd5                      ),
    .gf_wr_wck_last_cnt             (10'd18                     ),
    .gf_read_done_cnt               (10'd39                     ),
    .gf_write_done_cnt              (10'd27                     ),
    .gf_act_cmd_gap_cnt             (10'd16                     ),
    .gf_rd_cmd_gap_cnt              (10'd12                     ),
    .gf_wr_cmd_gap_cnt              (10'd10                     ),
    .gf_pre_cmd_gap_cnt             (10'd16                     ),
    .gf_refresh_batch_num           (refresh_batch_cfg          ),
    .gf_pattern_mode_cfg            (2'd0                       ),
    .dq_a_burst_flat                (dq_burst_flat_r            ),
    .dq_a_burst_valid               (dq_burst_valid_r           ),
    .err_cnt_GF                     (                           ),
    .err_block_cnt                  (                           ),
    .err_block_message              (                           ),
    .gf_pass_done                   (gf_pass_done               ),
    .gf_state                       (gf_state                   ),
    .gf_pass_start_d                (                           ),
    .gf_en_read                     (gf_en_read                 ),
    .gf_en_write                    (gf_en_write                ),
    .rx_dq_capture_en               (                           ),
    .gf_err_flag                    (                           ),
    .gf_cnt_read_value              (gf_cnt_read                ),
    .gf_cnt_write_value             (gf_cnt_write               ),
    .gf_compare_window              (                           ),
    .gf_compare_mismatch_odd        (gf_compare_mismatch_odd    ),
    .gf_compare_mismatch_even       (gf_compare_mismatch_even   ),
    .gf_access_addr                 (                           ),
    .gf_read_expected_beat          (gf_read_expected_beat      ),
    .gf_cnt_ba                      (                           ),
    .gf_cnt_bg                      (                           ),
    .gf_cnt_row                     (                           ),
    .gf_cnt_col                     (                           ),
    .gf_cnt_row_ns                  (                           ),
    .ascii_state                    (                           ),
    .wave_ck_a_run_en               (                           ),
    .wave_cs_a_0_fall                 (                           ),
    .wave_cs_a_0_rise                 (                           ),
    .wave_ca_a_fall                   (                           ),
    .wave_ca_a_rise                   (                           ),
    .wave_wck_a_run_en                  (                           ),
    .wave_wck_a_phase                  (                           ),
    .wave_dq_a_tx_word              (                           ),
    .wave_dq_oe                     (                           )
);

always #2.5 clk = ~clk;

always @(negedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) begin
        dq_burst_flat_r  <= 256'd0;
        dq_burst_valid_r <= 1'b0;
    end
    else if ((gf_en_read == 1'b1) &&
             (gf_cnt_read == ({2'b00, READ_CAPTURE_START} + 10'd6))) begin
        dq_burst_flat_r  <= tb_address_toggle_burst(U_engine.w_fifo_expected_beat);
        dq_burst_valid_r <= 1'b1;
    end
    else begin
        dq_burst_flat_r  <= 256'd0;
        dq_burst_valid_r <= 1'b0;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        rw_wait_write <= 1'b0;
    else if (gf_state == GF_WRITE_AFTER_READ_TB)
        rw_wait_write <= 1'b0;
    else if ((gf_state == GF_READ_TB) &&
             (gf_en_read == 1'b1) &&
             (gf_cnt_read >= 10'd39))
        rw_wait_write <= 1'b1;
    else
        rw_wait_write <= rw_wait_write;
end

always @(posedge clk) begin
    if (rst_n == 1'b1) begin
        cycle_count = cycle_count + 1;

        if (gf_state == GF_SCHED_TB)
            sched_seen = sched_seen + 1;

        if (gf_state == GF_PRE_REFRESH_TB)
            pre_refresh_seen = pre_refresh_seen + 1;

        if (gf_state == GF_REFRESH_TB)
            refresh_seen = refresh_seen + 1;

        if ((gf_state == GF_REFRESH_TB) &&
            (refresh_state_d == 1'b0)) begin
            refresh_service_count = refresh_service_count + 1;
            refresh_command_in_service = 0;
            refresh_command_cycle_last = 0;
        end

        if (((gf_state == GF_PRECHARGING_TB) ||
             (gf_state == GF_PRE_REFRESH_TB)) &&
            (precharge_state_d == 1'b0))
            precharge_service_count = precharge_service_count + 1;

        if (U_engine.w_precharge_cmd_first == 1'b1)
            precharge_command_count = precharge_command_count + 1;

        if (precharge_cmd_d == 1'b1) begin
            if ((U_engine.wave_ca_a_rise != 7'b1111000) ||
                (U_engine.wave_ca_a_fall != 7'b1110000)) begin
                fail_count = fail_count + 1;
                $display("TB FAIL: PREab CA R1=%07b F1=%07b at %0t",
                         U_engine.wave_ca_a_rise,
                         U_engine.wave_ca_a_fall,
                         $time);
            end
        end

        if ((U_engine.precharge_done == 1'b1) &&
            (U_engine.cnt_precharge != (10'd3 + TRPAB_TEST - 1))) begin
            fail_count = fail_count + 1;
            $display("TB FAIL: precharge done count=%0d at %0t",
                     U_engine.cnt_precharge,
                     $time);
        end

        if (U_engine.w_refresh_cmd == 1'b1) begin
            refresh_command_count = refresh_command_count + 1;

            if ((refresh_command_in_service > 0) &&
                ((cycle_count - refresh_command_cycle_last) != TRFCAB_TEST)) begin
                fail_count = fail_count + 1;
                $display("TB FAIL: REF gap=%0d expected=%0d at %0t",
                         cycle_count - refresh_command_cycle_last,
                         TRFCAB_TEST,
                         $time);
            end

            refresh_command_in_service = refresh_command_in_service + 1;
            refresh_command_cycle_last = cycle_count;

            if (U_engine.cnt_refresh != 29'd3) begin
                fail_count = fail_count + 1;
                $display("TB FAIL: REF command count=%0d at %0t",
                         U_engine.cnt_refresh,
                         $time);
            end
        end

        if ((U_engine.refresh_done == 1'b1) &&
            (U_engine.cnt_refresh != (TRFCAB_TEST - 1))) begin
            fail_count = fail_count + 1;
            $display("TB FAIL: refresh done count=%0d at %0t",
                     U_engine.cnt_refresh,
                     $time);
        end

        if ((U_engine.refresh_done == 1'b1) &&
            (refresh_command_in_service != REFRESH_BATCH_TEST)) begin
            fail_count = fail_count + 1;
            $display("TB FAIL: batch commands=%0d expected=%0d at %0t",
                     refresh_command_in_service,
                     REFRESH_BATCH_TEST,
                     $time);
        end

        if (U_engine.w_refresh_credit > 4'd8) begin
            fail_count = fail_count + 1;
            $display("TB FAIL: refresh credit overflow=%0d at %0t",
                     U_engine.w_refresh_credit,
                     $time);
        end

        if ((U_engine.refresh_due_r == 1'b1) &&
            (U_engine.w_refresh_credit < REFRESH_BATCH_TEST)) begin
            fail_count = fail_count + 1;
            $display("TB FAIL: refresh due with credit=%0d batch=%0d at %0t",
                     U_engine.w_refresh_credit,
                     REFRESH_BATCH_TEST,
                     $time);
        end

        if (dq_burst_valid_r == 1'b1)
            compare_count = compare_count + 1;

        if ((gf_compare_mismatch_odd == 1'b1) ||
            (gf_compare_mismatch_even == 1'b1)) begin
            fail_count = fail_count + 1;
            $display("TB FAIL: unexpected compare mismatch at %0t", $time);
        end

        if ((rw_wait_write == 1'b1) &&
            ((gf_state == GF_PRECHARGING_TB) ||
             (gf_state == GF_PRE_REFRESH_TB) ||
             (gf_state == GF_REFRESH_TB))) begin
            fail_count = fail_count + 1;
            $display("TB FAIL: refresh/precharge inserted between READ and WRITE at %0t",
                     $time);
        end

        refresh_state_d = (gf_state == GF_REFRESH_TB);
        precharge_state_d = (gf_state == GF_PRECHARGING_TB) ||
                            (gf_state == GF_PRE_REFRESH_TB);
        precharge_cmd_d = U_engine.w_precharge_cmd_first;
    end
end

initial begin
    clk              = 1'b0;
    rst_n            = 1'b0;
    gf_test_en       = 1'b0;
    gf_pass_start    = 1'b0;
    timeout_count    = 0;
    sched_seen       = 0;
    pre_refresh_seen = 0;
    refresh_seen     = 0;
    refresh_service_count = 0;
    refresh_command_count = 0;
    precharge_service_count = 0;
    precharge_command_count = 0;
    refresh_command_in_service = 0;
    refresh_command_cycle_last = 0;
    cycle_count      = 0;
    compare_count    = 0;
    fail_count       = 0;
    rw_wait_write    = 1'b0;
    refresh_state_d  = 1'b0;
    precharge_state_d = 1'b0;
    precharge_cmd_d   = 1'b0;
    dq_burst_flat_r  = 256'd0;
    dq_burst_valid_r = 1'b0;

    repeat (8) @(posedge clk);
    rst_n = 1'b1;
    repeat (4) @(posedge clk);
    gf_test_en    = 1'b1;
    gf_pass_start = 1'b1;

    while ((gf_pass_done == 1'b0) && (timeout_count < 200000)) begin
        @(posedge clk);
        timeout_count = timeout_count + 1;
    end

    gf_pass_start = 1'b0;

    if (timeout_count >= 200000) begin
        $display("TB FAIL: timeout");
    end
    else if (fail_count != 0) begin
        $display("TB FAIL: fail_count=%0d", fail_count);
    end
    else if (sched_seen == 0) begin
        $display("TB FAIL: GF_SCHED was not visited");
    end
    else if (pre_refresh_seen == 0) begin
        $display("TB FAIL: GF_PRE_REFRESH was not visited");
    end
    else if (refresh_seen == 0) begin
        $display("TB FAIL: GF_REFRESH was not visited");
    end
    else if (refresh_command_count !=
             (refresh_service_count * REFRESH_BATCH_TEST)) begin
        $display("TB FAIL: refresh services=%0d batch=%0d commands=%0d",
                 refresh_service_count,
                 REFRESH_BATCH_TEST,
                 refresh_command_count);
    end
    else if (precharge_command_count != precharge_service_count) begin
        $display("TB FAIL: precharge services=%0d commands=%0d",
                 precharge_service_count,
                 precharge_command_count);
    end
    else if (compare_count == 0) begin
        $display("TB FAIL: no READ comparisons");
    end
    else begin
        $display("TB PASS: scheduler refresh clean, batch=%0d sched=%0d pre_ref=%0d ref=%0d services=%0d commands=%0d pre_services=%0d pre_commands=%0d cmp=%0d",
                 REFRESH_BATCH_TEST,
                 sched_seen,
                 pre_refresh_seen,
                 refresh_seen,
                 refresh_service_count,
                 refresh_command_count,
                 precharge_service_count,
                 precharge_command_count,
                 compare_count);
    end

    $finish;
end

endmodule
