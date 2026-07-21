`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Module Name:     tb_gf_cmd_truth
// Description:
//   Command-truth dump for lpddr5_gf_engine. It checks READ_THEN_WRITE emits
//   the WR16 CA command and the expected four DQ payload words.
//////////////////////////////////////////////////////////////////////////////////

module tb_gf_cmd_truth #(
    parameter [5:0] END_COL = 6'd3
);

reg          clk;
reg          rst_n;
reg          gf_total_en;
reg          gf_inner_en;
reg  [1:0]   gf_op_mode;
reg          gf_read_data_sel;
reg          gf_write_data_sel;
reg  [7:0]   capture_start;
reg  [255:0] dq_a_burst_flat;
reg          dq_a_burst_valid;
reg          idd_ck_stop;

wire [31:0]  err_cnt;
wire         inner_done;
wire         cs0_rise;
wire         cs0_fall;
wire [6:0]   ca_rise;
wire [6:0]   ca_fall;
wire [20:0]  gf_state;
wire         gf_en_write;
wire [9:0]   cnt_rd;
wire [9:0]   cnt_wr;
wire [1:0]   cnt_ba;
wire [1:0]   cnt_bg;
wire [17:0]  cnt_row;
wire [5:0]   cnt_col;
wire [63:0]  dq_word;
wire         ck_run_en;

integer      cmd_cnt;
integer      payload_cnt;
integer      payload_error_cnt;
integer      rw_write_cmd_cnt;
integer      cycle_count;
integer      resp_wr_ptr;
integer      resp_rd_ptr;
integer      resp_level;
integer      ck_ctrl_error_cnt;

reg [31:0]   resp_due_cycle [0:31];
reg [15:0]   resp_expected  [0:31];
reg          payload_check_active;
reg [ 9:0]   payload_check_rel;
reg          payload_data_sel;
reg [17:0]   payload_row;
reg [ 1:0]   payload_bg;
reg [ 1:0]   payload_ba;
reg [ 5:0]   payload_col;

localparam [20:0] GF_WRITE_AFTER_READ_TB = 21'b0_0000_0000_0100_0000_0001;
localparam [9:0]  RESP_DELAY_CYCLES      = 10'd22;

function [15:0] gf_addr_beat;
    input [17:0] addr_row;
    input [1:0]  addr_bg;
    input [1:0]  addr_ba;
    input [5:0]  addr_col;
    begin
        gf_addr_beat = {addr_row[5:0], addr_bg, addr_ba, addr_col};
    end
endfunction

function [15:0] gf_expected_beat;
    input        data_sel;
    input [17:0] addr_row;
    input [1:0]  addr_bg;
    input [1:0]  addr_ba;
    input [5:0]  addr_col;
    reg   [15:0] addr_beat;
    begin
        addr_beat = gf_addr_beat(addr_row, addr_bg, addr_ba, addr_col);

        if (data_sel == addr_beat[0])
            gf_expected_beat = addr_beat;
        else
            gf_expected_beat = ~addr_beat;
    end
endfunction

function [63:0] gf_expected_word;
    input        data_sel;
    input [17:0] addr_row;
    input [1:0]  addr_bg;
    input [1:0]  addr_ba;
    input [5:0]  addr_col;
    input [9:0]  payload_cnt;
    reg   [15:0] addr_pattern;
    reg   [15:0] beat0;
    begin
        addr_pattern = gf_expected_beat(data_sel, addr_row, addr_bg,
                                        addr_ba, addr_col);
        beat0 = {4'b0000, payload_cnt, 2'b00} - 16'd1;
        gf_expected_word = {
            ((beat0 + 16'd3) & 16'd1) ? ~addr_pattern : addr_pattern,
            ((beat0 + 16'd2) & 16'd1) ? ~addr_pattern : addr_pattern,
            ((beat0 + 16'd1) & 16'd1) ? ~addr_pattern : addr_pattern,
            ( beat0           & 16'd1) ? ~addr_pattern : addr_pattern
        };
    end
endfunction

function [255:0] gf_expected_burst;
    input [15:0] addr_pattern;
    integer beat;
    begin
        gf_expected_burst = 256'd0;
        for (beat = 0; beat < 16; beat = beat + 1) begin
            gf_expected_burst[(16 * beat) +: 16] =
                (beat[0] == 1'b1) ? ~addr_pattern : addr_pattern;
        end
    end
endfunction

lpddr5_gf_engine U_engine (
    .clk                             (clk            ),
    .rst_n                           (rst_n          ),
    .engine_inhibit                  (1'b0           ),
    .idd_ck_stop                     (idd_ck_stop    ),
    .GF_start_col                    (6'd0           ),
    .GF_end_col                      (END_COL        ),
    .GF_start_row                    (18'd0          ),
    .GF_end_row                      (18'd0          ),
    .GF_start_bg                     (2'd0           ),
    .GF_end_bg                       (2'd3           ),
    .GF_start_ba                     (2'd0           ),
    .GF_end_ba                       (2'd3           ),
    .gf_test_en                      (gf_total_en    ),
    .gf_pass_start                   (gf_inner_en    ),
    .gf_op_mode                      (gf_op_mode     ),
    .gf_read_data_sel                (gf_read_data_sel),
    .gf_write_data_sel               (gf_write_data_sel),
    .march_y_sequence                (1'b0           ),
    .die_message                     (8'h18          ),
    .read_capture_start_cnt          (capture_start  ),
    .gf_rd_wck_start_cnt             (10'd5          ),
    .gf_rd_wck_last_cnt              (10'd26         ),
    .gf_wr_wck_start_cnt             (10'd5          ),
    .gf_wr_wck_last_cnt              (10'd18         ),
    .gf_read_done_cnt                (10'd39         ),
    .gf_write_done_cnt               (10'd27         ),
    .gf_act_cmd_gap_cnt              (10'd16         ),
    .gf_rd_cmd_gap_cnt               (10'd12         ),
    .gf_wr_cmd_gap_cnt               (10'd10         ),
    .gf_pre_cmd_gap_cnt              (10'd16         ),
    .gf_refresh_batch_num            (3'd1           ),
    .gf_pattern_mode_cfg             (2'd0           ),
    .dq_a_burst_flat                 (dq_a_burst_flat),
    .dq_a_burst_valid                (dq_a_burst_valid),
    .err_cnt_GF                      (err_cnt        ),
    .err_block_cnt                   (               ),
    .err_block_message               (               ),
    .gf_pass_done                    (inner_done     ),
    .gf_state                        (gf_state       ),
    .gf_pass_start_d                 (               ),
    .gf_en_read                      (               ),
    .gf_en_write                     (gf_en_write    ),
    .rx_dq_capture_en                (               ),
    .gf_err_flag                     (               ),
    .gf_cnt_read_value               (cnt_rd         ),
    .gf_cnt_write_value              (cnt_wr         ),
    .gf_compare_window               (               ),
    .gf_compare_mismatch_odd         (               ),
    .gf_compare_mismatch_even        (               ),
    .gf_access_addr                  (               ),
    .gf_read_expected_beat           (               ),
    .gf_cnt_ba                       (cnt_ba         ),
    .gf_cnt_bg                       (cnt_bg         ),
    .gf_cnt_row                      (cnt_row        ),
    .gf_cnt_col                      (cnt_col        ),
    .gf_cnt_row_ns                   (               ),
    .ascii_state                     (               ),
    .wave_ck_a_run_en                (ck_run_en      ),
    .wave_cs_a_0_rise                  (cs0_rise       ),
    .wave_cs_a_0_fall                  (cs0_fall       ),
    .wave_ca_a_rise                    (ca_rise        ),
    .wave_ca_a_fall                    (ca_fall        ),
    .wave_wck_a_run_en                   (               ),
    .wave_wck_a_phase                   (               ),
    .wave_dq_a_tx_word               (dq_word        ),
    .wave_dq_oe                      (               )
);

always #2.5 clk = ~clk;

always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0)
        cycle_count <= 0;
    else
        cycle_count <= cycle_count + 1;
end

always @(posedge clk) begin
    if ((rst_n == 1'b1) && (U_engine.w_read_cmd_first == 1'b1)) begin
        resp_due_cycle[resp_wr_ptr] = cycle_count + RESP_DELAY_CYCLES;
        resp_expected[resp_wr_ptr]  = U_engine.w_read_expected_beat;
        resp_wr_ptr = resp_wr_ptr + 1;
        resp_level  = resp_level + 1;
    end
end

always @(negedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) begin
        dq_a_burst_flat  <= 256'h0;
        dq_a_burst_valid <= 1'b0;
    end
    else if ((resp_level > 0) && (cycle_count >= resp_due_cycle[resp_rd_ptr])) begin
        dq_a_burst_flat  <= gf_expected_burst(resp_expected[resp_rd_ptr]);
        dq_a_burst_valid <= 1'b1;
        resp_rd_ptr      = resp_rd_ptr + 1;
        resp_level       = resp_level - 1;
    end
    else begin
        dq_a_burst_flat  <= 256'h0;
        dq_a_burst_valid <= 1'b0;
    end
end

always @(posedge clk) begin
    if ((cs0_rise || cs0_fall) && (cmd_cnt < 80)) begin
        $display("CMD %0d: state=%05x wr_cnt=%0d rd_cnt=%0d rise=%07b fall=%07b",
                 cmd_cnt, gf_state, cnt_wr, cnt_rd, ca_rise, ca_fall);
        cmd_cnt = cmd_cnt + 1;
    end

    if ((gf_state == GF_WRITE_AFTER_READ_TB) &&
        ((cnt_wr == 10'd4) || (cnt_wr == 10'd5)) &&
        (cs0_rise || cs0_fall)) begin
        rw_write_cmd_cnt = rw_write_cmd_cnt + 1;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) begin
        payload_check_active <= 1'b0;
        payload_check_rel    <= 10'd0;
        payload_data_sel     <= 1'b0;
        payload_row          <= 18'd0;
        payload_bg           <= 2'd0;
        payload_ba           <= 2'd0;
        payload_col          <= 6'd0;
    end
    else if ((gf_state == GF_WRITE_AFTER_READ_TB) &&
             (U_engine.w_write_payload_fire == 1'b1) &&
             (U_engine.w_write_payload_slot == 5'd0)) begin
        payload_check_active <= 1'b1;
        payload_check_rel    <= 10'd0;
        payload_data_sel     <= gf_write_data_sel;
        payload_row          <= U_engine.w_access_row;
        payload_bg           <= U_engine.w_write_data_bg;
        payload_ba           <= U_engine.w_write_data_ba;
        payload_col          <= U_engine.w_access_col;
    end
    else if ((payload_check_active == 1'b1) &&
             (payload_check_rel < 10'd3)) begin
        payload_check_active <= 1'b1;
        payload_check_rel    <= payload_check_rel + 10'd1;
    end
    else begin
        payload_check_active <= 1'b0;
        payload_check_rel    <= payload_check_rel;
    end
end

always @(negedge clk) begin
    if ((rst_n == 1'b1) &&
        (payload_check_active == 1'b1) &&
        (payload_cnt < 4)) begin
        $display("GF_PAYLOAD data_sel=%0d word=%0d cnt_wr=%0d dq=%h exp=%h",
                 payload_data_sel,
                 payload_cnt,
                 cnt_wr,
                 dq_word,
                 gf_expected_word(payload_data_sel,
                                  payload_row,
                                  payload_bg,
                                  payload_ba,
                                  payload_col,
                                  payload_check_rel));

        if (dq_word !== gf_expected_word(payload_data_sel,
                                         payload_row,
                                         payload_bg,
                                         payload_ba,
                                         payload_col,
                                         payload_check_rel)) begin
            payload_error_cnt = payload_error_cnt + 1;
            $display("GF_PAYLOAD_ERR dq got=%h exp=%h",
                     dq_word,
                     gf_expected_word(payload_data_sel,
                                      payload_row,
                                      payload_bg,
                                      payload_ba,
                                      payload_col,
                                      payload_check_rel));
        end

        payload_cnt = payload_cnt + 1;

        if (payload_cnt == 4) begin
            if ((payload_error_cnt == 0) &&
                (rw_write_cmd_cnt >= 2) &&
                (ck_ctrl_error_cnt == 0)) begin
                $display("SIM PASS: GF CK stop/restart, WR16 command and March payload");
            end
            else begin
                $display("SIM FAIL: GF payload errors=%0d rw_write_cmd_cnt=%0d ck_ctrl_errors=%0d",
                         payload_error_cnt,
                         rw_write_cmd_cnt,
                         ck_ctrl_error_cnt);
            end
            $finish;
        end
    end
end

initial begin
    clk              = 1'b0;
    rst_n            = 1'b0;
    gf_total_en      = 1'b0;
    gf_inner_en      = 1'b0;
    gf_op_mode       = 2'd0;
    gf_read_data_sel = 1'b0;
    gf_write_data_sel = 1'b0;
    capture_start    = 8'd18;
    dq_a_burst_flat  = 256'h0;
    dq_a_burst_valid = 1'b0;
    idd_ck_stop      = 1'b0;
    cmd_cnt          = 0;
    payload_cnt      = 0;
    payload_error_cnt = 0;
    rw_write_cmd_cnt = 0;
    cycle_count      = 0;
    resp_wr_ptr      = 0;
    resp_rd_ptr      = 0;
    resp_level       = 0;
    ck_ctrl_error_cnt = 0;
    payload_check_active = 1'b0;
    payload_check_rel = 10'd0;
    payload_data_sel = 1'b0;
    payload_row = 18'd0;
    payload_bg = 2'd0;
    payload_ba = 2'd0;
    payload_col = 6'd0;

    repeat (10) @(posedge clk);
    rst_n = 1'b1;
    repeat (10) @(posedge clk);

    // A one-cycle IDD6 stop request must hold CK off until GF starts.
    idd_ck_stop <= 1'b1;
    @(posedge clk);
    idd_ck_stop <= 1'b0;
    repeat (6) @(posedge clk);

    if ((ck_run_en !== 1'b0) || (U_engine.r_ck_phase !== 1'b0)) begin
        $display("SIM FAIL: GF CK did not remain stopped after IDD6");
        ck_ctrl_error_cnt = ck_ctrl_error_cnt + 1;
    end

    gf_total_en    <= 1'b1;
    gf_op_mode <= 2'd2;
    gf_read_data_sel <= 1'b0;
    gf_write_data_sel <= 1'b1;
    @(posedge clk);
    gf_inner_en <= 1'b1;
    repeat (4) @(posedge clk);

    if (ck_run_en !== 1'b1) begin
        $display("SIM FAIL: GF CK did not restart on pass start");
        ck_ctrl_error_cnt = ck_ctrl_error_cnt + 1;
    end

    wait (inner_done == 1'b1);
    gf_inner_en <= 1'b0;
    repeat (20) @(posedge clk);

    $display("SIM FAIL: GF payload checker did not collect four words");
    $finish;

    gf_op_mode <= 2'd1;
    gf_read_data_sel <= 1'b0;
    gf_write_data_sel <= 1'b0;
    @(posedge clk);
    gf_inner_en <= 1'b1;
    wait (inner_done == 1'b1);
    gf_inner_en <= 1'b0;
    repeat (20) @(posedge clk);

    $display("SIM DONE: %0d commands captured", cmd_cnt);
    $finish;
end

initial begin
    #10_000_000;
    $display("SIM FAIL: timeout");
    $finish;
end

endmodule
