`timescale 1ns / 1ps

// Current GF data-pattern check.
// WRITE mode checks the four 64-bit TX words driven during the payload window.
// READ mode feeds the matching 256-bit burst into the engine compare path.
module tb_gf_data_pattern #(
    parameter RW       = 0,        // 0 = write pass, 1 = read pass
    parameter MARCH    = 0,        // 0 = forward, 1 = reverse
    parameter PATTERN_MODE = 0,    // 0 = address toggle, 1 = write stress
    parameter END_ROW  = 3,
    parameter END_COL  = 9
);

reg         clk;
reg         rst_n;
reg         gf_total_en;
reg         gf_inner_en;

wire [20:0] gf_state;
wire        gf_inner_done;
wire        gf_en_read;
wire        gf_en_write;
wire [9:0]  gf_cnt_read;
wire [9:0]  gf_cnt_write;
wire        gf_compare_window;
wire        gf_compare_mismatch_odd;
wire        gf_compare_mismatch_even;
wire        rx_dq_capture_en;
wire [15:0] gf_read_expected_beat;
wire [63:0] wave_dq_a_tx_word;

integer checks;
integer errors;
integer timeout;
integer cycle_count;
integer rd_resp_wr_ptr;
integer rd_resp_rd_ptr;
integer rd_resp_level;
integer rd_resp_due_cycle [0:31];
reg [15:0] rd_resp_expected  [0:31];
reg         pattern_check_active;
integer     pattern_check_rel;
reg [15:0]  write_expected_beat;
integer     bank_order_checks;
integer     bank_order_errors;
integer     bank_check_slot;

localparam [7:0]  READ_CAPTURE_START = 8'h10;
reg         rd_burst_valid;
reg [255:0] gf_expect_burst;

function [15:0] gf_addr_pattern_expected;
    input        data_sel;
    input [17:0] addr_row;
    input [ 1:0] addr_bg;
    input [ 1:0] addr_ba;
    input [ 5:0] addr_col;
    reg   [15:0] addr_beat;
    begin
        addr_beat = {addr_row[5:0], addr_bg, addr_ba, addr_col};
        if (data_sel == addr_beat[0])
            gf_addr_pattern_expected = addr_beat;
        else
            gf_addr_pattern_expected = ~addr_beat;
    end
endfunction

function [15:0] gf_pattern_beat_expected;
    input [ 1:0] pattern_mode;
    input        data_sel;
    input [15:0] addr_pattern;
    input [15:0] beat_index;
    begin
        if (pattern_mode == 2'd1)
            gf_pattern_beat_expected = {16{data_sel ^ beat_index[0]}};
        else if (beat_index[0] == 1'b1)
            gf_pattern_beat_expected = ~addr_pattern;
        else
            gf_pattern_beat_expected = addr_pattern;
    end
endfunction

function [63:0] gf_pattern_word_expected;
    input [ 1:0] pattern_mode;
    input        data_sel;
    input [15:0] addr_pattern;
    input [ 9:0] payload_cnt;
    reg   [15:0] beat0;
    begin
        beat0 = {4'b0000, payload_cnt, 2'b00} - 16'd1;
        gf_pattern_word_expected = {
            gf_pattern_beat_expected(pattern_mode, data_sel, addr_pattern, beat0 + 16'd3),
            gf_pattern_beat_expected(pattern_mode, data_sel, addr_pattern, beat0 + 16'd2),
            gf_pattern_beat_expected(pattern_mode, data_sel, addr_pattern, beat0 + 16'd1),
            gf_pattern_beat_expected(pattern_mode, data_sel, addr_pattern, beat0)
        };
    end
endfunction

function [255:0] gf_pattern_burst_expected;
    input [ 1:0] pattern_mode;
    input        data_sel;
    input [15:0] addr_pattern;
    integer beat;
    begin
        gf_pattern_burst_expected = 256'd0;
        for (beat = 0; beat < 16; beat = beat + 1) begin
            gf_pattern_burst_expected[(16 * beat) +: 16] =
                gf_pattern_beat_expected(pattern_mode, data_sel,
                                         addr_pattern, beat[15:0]);
        end
    end
endfunction

function [3:0] gf_bank_order_expected;
    input         bank_reverse;
    input [4:0]   bank_slot;
    reg   [3:0]   linear_index;
    begin
        if (bank_reverse == 1'b1)
            linear_index = 4'd15 - bank_slot[3:0];
        else
            linear_index = bank_slot[3:0];

        gf_bank_order_expected = {linear_index[1:0],
                                  linear_index[3:2]};
    end
endfunction

lpddr5_gf_engine #(
    .T_RCD         (12 ),
    .T_READ        (40 ),
    .T_WRITE       (28 ),
    .T_RPab        (12 ),
    .TRFCab        (80 ),
    .T_REFI_CYCLES (781)
) dut (
    .clk                             (clk                     ),
    .rst_n                           (rst_n                   ),
    .engine_inhibit                  (1'b0                    ),
    .idd_ck_stop                     (1'b0                    ),
    .GF_start_col                    (6'd0                    ),
    .GF_end_col                      (END_COL[5:0]            ),
    .GF_start_row                    (18'd0                   ),
    .GF_end_row                      (END_ROW[17:0]           ),
    .GF_start_bg                     (2'd0                    ),
    .GF_end_bg                       (2'd3                    ),
    .GF_start_ba                     (2'd0                    ),
    .GF_end_ba                       (2'd3                    ),
    .gf_test_en                      (gf_total_en             ),
    .gf_pass_start                   (gf_inner_en             ),
    .gf_op_mode                      (RW[0] ? 2'd1 : 2'd0     ),
    .gf_read_data_sel                (RW[0]                   ),
    .gf_write_data_sel               (RW[0]                   ),
    .march_y_sequence                (MARCH[0]                ),
    .die_message                     (8'h18                   ),
    .read_capture_start_cnt          (READ_CAPTURE_START      ),
    .gf_rd_wck_start_cnt             (10'd5                   ),
    .gf_rd_wck_last_cnt              (10'd26                  ),
    .gf_wr_wck_start_cnt             (10'd5                   ),
    .gf_wr_wck_last_cnt              (10'd18                  ),
    .gf_read_done_cnt                (10'd39                  ),
    .gf_write_done_cnt               (10'd27                  ),
    .gf_act_cmd_gap_cnt              (10'd6                   ),
    .gf_rd_cmd_gap_cnt               (10'd4                   ),
    .gf_wr_cmd_gap_cnt               (10'd11                  ),
    .gf_pre_cmd_gap_cnt              (10'd7                   ),
    .gf_refresh_batch_num            (3'd1                    ),
    .gf_pattern_mode_cfg             (PATTERN_MODE[1:0]       ),
    .dq_a_burst_flat                 (gf_expect_burst         ),
    .dq_a_burst_valid                (rd_burst_valid          ),
    .err_cnt_GF                      (                        ),
    .err_block_cnt                   (                        ),
    .err_block_message               (                        ),
    .gf_pass_done                    (gf_inner_done           ),
    .gf_state                        (gf_state                ),
    .gf_pass_start_d                 (                        ),
    .gf_en_read                      (gf_en_read              ),
    .gf_en_write                     (gf_en_write             ),
    .rx_dq_capture_en                (rx_dq_capture_en        ),
    .gf_err_flag                     (                        ),
    .gf_cnt_read_value               (gf_cnt_read             ),
    .gf_cnt_write_value              (gf_cnt_write            ),
    .gf_compare_window               (gf_compare_window       ),
    .gf_compare_mismatch_odd         (gf_compare_mismatch_odd ),
    .gf_compare_mismatch_even        (gf_compare_mismatch_even),
    .gf_access_addr                  (                        ),
    .gf_read_expected_beat           (gf_read_expected_beat   ),
    .gf_cnt_ba                       (                        ),
    .gf_cnt_bg                       (                        ),
    .gf_cnt_row                      (                        ),
    .gf_cnt_col                      (                        ),
    .gf_cnt_row_ns                   (                        ),
    .ascii_state                     (                        ),
    .wave_ck_a_run_en                (                        ),
    .wave_cs_a_0_fall                  (                        ),
    .wave_cs_a_0_rise                  (                        ),
    .wave_ca_a_fall                    (                        ),
    .wave_ca_a_rise                    (                        ),
    .wave_wck_a_run_en                   (                        ),
    .wave_wck_a_phase                   (                        ),
    .wave_dq_a_tx_word               (wave_dq_a_tx_word       ),
    .wave_dq_oe                      (                        )
);

always #2.5 clk = ~clk;

always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0)
        cycle_count <= 0;
    else
        cycle_count <= cycle_count + 1;
end

always @(negedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) begin
        gf_expect_burst <= 256'h0;
        rd_burst_valid <= 1'b0;
    end
    else begin
        if ((RW[0] == 1'b1) &&
            (rd_resp_level > 0) &&
            (cycle_count >= rd_resp_due_cycle[rd_resp_rd_ptr])) begin
            gf_expect_burst <= gf_pattern_burst_expected(
                PATTERN_MODE[1:0],
                RW[0],
                dut.w_fifo_expected_beat
            );
            rd_burst_valid <= 1'b1;
            rd_resp_rd_ptr = (rd_resp_rd_ptr + 1) % 32;
            rd_resp_level  = rd_resp_level - 1;
        end
        else begin
            gf_expect_burst <= 256'h0;
            rd_burst_valid <= 1'b0;
        end

        if ((RW[0] == 1'b1) && (rx_dq_capture_en == 1'b1)) begin
            rd_resp_due_cycle[rd_resp_wr_ptr] = cycle_count + 6;
            rd_resp_expected[rd_resp_wr_ptr]  = dut.w_fifo_expected_beat;
            rd_resp_wr_ptr = (rd_resp_wr_ptr + 1) % 32;
            rd_resp_level  = rd_resp_level + 1;
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) begin
        pattern_check_active <= 1'b0;
        pattern_check_rel    <= 0;
        write_expected_beat  <= 16'd0;
    end
    else if ((RW[0] == 1'b0) &&
             (dut.w_write_payload_fire == 1'b1)) begin
        pattern_check_active <= 1'b1;
        pattern_check_rel    <= 0;
        write_expected_beat  <= gf_addr_pattern_expected(
            RW[0],
            dut.w_access_row,
            dut.w_write_data_bg,
            dut.w_write_data_ba,
            dut.w_access_col
        );
    end
    else if ((pattern_check_active == 1'b1) &&
             (pattern_check_rel < 4)) begin
        pattern_check_active <= 1'b1;
        pattern_check_rel    <= pattern_check_rel + 1;
        write_expected_beat  <= write_expected_beat;
    end
    else begin
        pattern_check_active <= 1'b0;
        pattern_check_rel    <= pattern_check_rel;
        write_expected_beat  <= write_expected_beat;
    end
end

always @(negedge clk) begin
    if ((rst_n == 1'b1) &&
        (RW[0] == 1'b0) &&
        (pattern_check_active == 1'b1)) begin
        checks = checks + 1;
        if (wave_dq_a_tx_word !==
            gf_pattern_word_expected(PATTERN_MODE[1:0],
                                     RW[0],
                                     write_expected_beat,
                                     pattern_check_rel[9:0])) begin
            errors = errors + 1;
            $display("PATTERN ERR t=%0t mode=%0d cnt_write=%0d tx=%h exp=%h",
                     $time,
                     PATTERN_MODE,
                     gf_cnt_write,
                     wave_dq_a_tx_word,
                     gf_pattern_word_expected(PATTERN_MODE[1:0],
                                              RW[0],
                                              write_expected_beat,
                                              pattern_check_rel[9:0]));
        end
    end
end

always @(posedge clk) begin
    if ((rst_n == 1'b1) && (RW[0] == 1'b1) &&
        (gf_compare_window == 1'b1)) begin
        checks = checks + 1;
        if ((gf_compare_mismatch_odd == 1'b1) ||
            (gf_compare_mismatch_even == 1'b1)) begin
            errors = errors + 1;
            if (errors <= 4) begin
                $display("COMPARE ERR t=%0t odd=%0b even=%0b addr=%h base=%h calc=%h beat0=%h beat1=%h mode=%0d",
                         $time,
                         gf_compare_mismatch_odd,
                         gf_compare_mismatch_even,
                         dut.compare_access_addr_dly_r,
                         dut.compare_expected_dly_r,
                         gf_addr_pattern_expected(
                             RW[0],
                             dut.compare_access_addr_dly_r[23:6],
                             dut.compare_access_addr_dly_r[25:24],
                             dut.compare_access_addr_dly_r[27:26],
                             dut.compare_access_addr_dly_r[5:0]
                         ),
                         dut.compare_burst_r[15:0],
                         dut.compare_burst_r[31:16],
                         dut.compare_pattern_mode_r);
            end
        end
    end
end

always @(negedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) begin
        bank_order_checks <= 0;
        bank_order_errors <= 0;
        bank_check_slot   <= 0;
    end
    else if (((RW[0] == 1'b1) && (dut.w_read_cmd_first == 1'b1)) ||
             ((RW[0] == 1'b0) && (dut.w_write_cmd_first == 1'b1))) begin
        bank_order_checks <= bank_order_checks + 1;

        if (((RW[0] == 1'b1) ? dut.w_read_bank_index :
                               dut.w_write_bank_index) !==
            gf_bank_order_expected(MARCH[0], bank_check_slot[4:0])) begin
            bank_order_errors <= bank_order_errors + 1;
            $display("BANK ORDER ERR t=%0t RW=%0d march=%0d slot=%0d got=%0d exp=%0d",
                     $time,
                     RW,
                     MARCH,
                     bank_check_slot,
                     (RW[0] == 1'b1) ? dut.w_read_bank_index :
                                      dut.w_write_bank_index,
                     gf_bank_order_expected(MARCH[0], bank_check_slot[4:0]));
        end

        if (bank_check_slot >= 15)
            bank_check_slot <= 0;
        else
            bank_check_slot <= bank_check_slot + 1;
    end
end

initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    gf_total_en = 1'b0;
    gf_inner_en = 1'b0;
    checks = 0;
    errors = 0;
    timeout = 0;
    cycle_count = 0;
    rd_resp_wr_ptr = 0;
    rd_resp_rd_ptr = 0;
    rd_resp_level = 0;
    pattern_check_active = 1'b0;
    pattern_check_rel = 0;
    write_expected_beat = 16'd0;
    bank_order_checks = 0;
    bank_order_errors = 0;
    bank_check_slot = 0;
    gf_expect_burst = 256'h0;
    rd_burst_valid = 1'b0;

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (3) @(posedge clk);
    gf_total_en = 1'b1;
    gf_inner_en = 1'b1;

    while ((gf_inner_done == 1'b0) && (timeout < 400000)) begin
        @(posedge clk);
        timeout = timeout + 1;
    end

    repeat (5) @(posedge clk);

    if (timeout >= 400000) begin
        $display("TB FAIL: timeout, state=%h checks=%0d", gf_state, checks);
    end
    else if ((checks == 0) || (bank_order_checks == 0)) begin
        $display("TB FAIL: missing checks pattern=%0d bank_order=%0d",
                 checks, bank_order_checks);
    end
    else if ((errors == 0) && (bank_order_errors == 0)) begin
        $display("TB PASS: RW=%0d MARCH=%0d mode=%0d pattern=%0d bank_order=%0d",
                 RW, MARCH, PATTERN_MODE, checks, bank_order_checks);
    end
    else begin
        $display("TB FAIL: RW=%0d MARCH=%0d mode=%0d pattern_err=%0d bank_err=%0d",
                 RW, MARCH, PATTERN_MODE, errors, bank_order_errors);
    end

    $finish;
end

endmodule
