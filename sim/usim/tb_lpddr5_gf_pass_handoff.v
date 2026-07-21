`timescale 1ns / 1ps

// Focused regression for the GF controller-to-engine pass handoff.
// It keeps the address range small and checks that READ passes consume the
// address-dependent 256-bit burst pattern used by the current GF engine.
module tb_lpddr5_gf_pass_handoff #(
    parameter END_COL_TEST = 1,
    parameter END_ROW_TEST = 1,
    parameter PASS_COUNT   = 6,
    parameter T_REFI_TEST  = 60000
);

reg         clk;
reg         rst_n;
reg         gf_total_en;

wire [1:0]  gf_op_mode;
wire        gf_read_data_sel;
wire        gf_write_data_sel;
wire        march_y_sequence;
wire        gf_total_done;
wire [95:0] gf_result_data;
wire        gf_inner_en;
wire        gf_inner_done;
wire [5:0]  gf_start_col;
wire [5:0]  gf_end_col;
wire [17:0] gf_start_row;
wire [17:0] gf_end_row;
wire [1:0]  gf_start_bg;
wire [1:0]  gf_end_bg;
wire [1:0]  gf_start_ba;
wire [1:0]  gf_end_ba;
wire [31:0] gf_error_count;
wire [1:0]  gf_cnt_ba;
wire [1:0]  gf_cnt_bg;
wire [17:0] gf_cnt_row;
wire [5:0]  gf_cnt_col;
wire        gf_en_write;
wire        gf_en_read;
wire        gf_compare_window;
wire        gf_compare_mismatch_odd;
wire        gf_compare_mismatch_even;
wire [9:0]  gf_cnt_read;
wire [63:0] wave_dq_a_tx_word;
reg  [255:0] dq_a_burst_flat_r;
reg          dq_a_burst_valid_r;

integer timeout_count;
integer compare_count;
integer mismatch_count;
integer pass_start_count;
integer cycle_count;
integer resp_wr_ptr;
integer resp_rd_ptr;
integer resp_level;

localparam [7:0] READ_CAPTURE_START = 8'h10;
localparam [9:0] RESP_DELAY_CYCLES  = 10'd18;

reg [31:0] resp_due_cycle [0:255];
reg [15:0] resp_expected  [0:255];

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

lpddr5_gf ctrl (
    .cha_core_clk       (clk             ),
    .cha_phy_rst_n      (rst_n           ),
    .clk_200m           (clk             ),
    .rst_n              (rst_n           ),
    .die_message        (8'h18           ),
    .gf_op_mode         (gf_op_mode      ),
    .gf_read_data_sel   (gf_read_data_sel),
    .gf_write_data_sel  (gf_write_data_sel),
    .march_y_sequence   (march_y_sequence),
    .GF_total_en        (gf_total_en     ),
    .GF_total_done      (gf_total_done   ),
    .GF_result_data     (gf_result_data  ),
    .cha_GF_inner_en    (gf_inner_en     ),
    .cha_GF_inner_done  (gf_inner_done   ),
    .cha_err_cnt_GF     (gf_error_count  ),
    .cha_GF_start_col   (gf_start_col    ),
    .cha_GF_end_col     (gf_end_col      ),
    .cha_GF_start_row   (gf_start_row    ),
    .cha_GF_end_row     (gf_end_row      ),
    .cha_GF_start_bg    (gf_start_bg     ),
    .cha_GF_end_bg      (gf_end_bg       ),
    .cha_GF_start_ba    (gf_start_ba     ),
    .cha_GF_end_ba      (gf_end_ba       )
);

lpddr5_gf_engine #(
    .T_RCD         (6          ),
    .T_READ        (40         ),
    .T_WRITE       (28         ),
    .T_RPab        (8          ),
    .TRFCab        (10         ),
    .T_REFI_CYCLES (T_REFI_TEST)
) engine (
    .clk                             (clk                         ),
    .rst_n                           (rst_n                       ),
    .engine_inhibit                  (1'b0                        ),
    .idd_ck_stop                     (1'b0                        ),
    .GF_start_col                    (gf_start_col                ),
    .GF_end_col                      (gf_end_col                  ),
    .GF_start_row                    (gf_start_row                ),
    .GF_end_row                      (gf_end_row                  ),
    .GF_start_bg                     (gf_start_bg                 ),
    .GF_end_bg                       (gf_end_bg                   ),
    .GF_start_ba                     (gf_start_ba                 ),
    .GF_end_ba                       (gf_end_ba                   ),
    .gf_test_en                      (gf_total_en                 ),
    .gf_pass_start                   (gf_inner_en                 ),
    .gf_op_mode                      (gf_op_mode                  ),
    .gf_read_data_sel                (gf_read_data_sel            ),
    .gf_write_data_sel               (gf_write_data_sel           ),
    .march_y_sequence                (march_y_sequence            ),
    .die_message                     (8'h18                       ),
    .read_capture_start_cnt          (READ_CAPTURE_START          ),
    .gf_rd_wck_start_cnt             (10'd5                       ),
    .gf_rd_wck_last_cnt              (10'd26                      ),
    .gf_wr_wck_start_cnt             (10'd5                       ),
    .gf_wr_wck_last_cnt              (10'd18                      ),
    .gf_read_done_cnt                (10'd39                      ),
    .gf_write_done_cnt               (10'd27                      ),
    .gf_act_cmd_gap_cnt              (10'd16                      ),
    .gf_rd_cmd_gap_cnt               (10'd12                      ),
    .gf_wr_cmd_gap_cnt               (10'd10                      ),
    .gf_pre_cmd_gap_cnt              (10'd16                      ),
    .gf_refresh_batch_num            (3'd1                        ),
    .gf_pattern_mode_cfg             (2'd0                        ),
    .dq_a_burst_flat                 (dq_a_burst_flat_r           ),
    .dq_a_burst_valid                (dq_a_burst_valid_r          ),
    .err_cnt_GF                      (gf_error_count              ),
    .err_block_cnt                   (                            ),
    .err_block_message               (                            ),
    .gf_pass_done                    (gf_inner_done               ),
    .gf_state                        (                            ),
    .gf_pass_start_d                 (                            ),
    .gf_en_read                      (gf_en_read                  ),
    .gf_en_write                     (gf_en_write                 ),
    .rx_dq_capture_en                (                            ),
    .gf_err_flag                     (                            ),
    .gf_cnt_read_value               (gf_cnt_read                 ),
    .gf_cnt_write_value              (                            ),
    .gf_compare_window               (gf_compare_window           ),
    .gf_compare_mismatch_odd         (gf_compare_mismatch_odd     ),
    .gf_compare_mismatch_even        (gf_compare_mismatch_even    ),
    .gf_access_addr                  (                            ),
    .gf_read_expected_beat           (                            ),
    .gf_cnt_ba                       (gf_cnt_ba                   ),
    .gf_cnt_bg                       (gf_cnt_bg                   ),
    .gf_cnt_row                      (gf_cnt_row                  ),
    .gf_cnt_col                      (gf_cnt_col                  ),
    .gf_cnt_row_ns                   (                            ),
    .ascii_state                     (                            ),
    .wave_ck_a_run_en                (                            ),
    .wave_cs_a_0_fall                  (                            ),
    .wave_cs_a_0_rise                  (                            ),
    .wave_ca_a_fall                    (                            ),
    .wave_ca_a_rise                    (                            ),
    .wave_wck_a_run_en                   (                            ),
    .wave_wck_a_phase                   (                            ),
    .wave_dq_a_tx_word               (wave_dq_a_tx_word           ),
    .wave_dq_oe                      (                            )
);

always #2.5 clk = ~clk;

always @(negedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) begin
        dq_a_burst_flat_r  <= 256'd0;
        dq_a_burst_valid_r <= 1'b0;
    end
    else if ((resp_level > 0) &&
             (cycle_count >= resp_due_cycle[resp_rd_ptr])) begin
        dq_a_burst_flat_r  <= tb_address_toggle_burst(resp_expected[resp_rd_ptr]);
        dq_a_burst_valid_r <= 1'b1;
        resp_rd_ptr        = (resp_rd_ptr + 1) % 256;
        resp_level         = resp_level - 1;
    end
    else begin
        dq_a_burst_flat_r  <= 256'd0;
        dq_a_burst_valid_r <= 1'b0;
    end
end

always @(posedge clk) begin
    if ((rst_n == 1'b1) && (engine.gf_pass_start_pulse == 1'b1)) begin
        pass_start_count = pass_start_count + 1;
        $display("PASS_START t=%0t pass=%0d mode=%0d",
                 $time, pass_start_count, gf_op_mode);
    end

    if (rst_n == 1'b1) begin
        cycle_count = cycle_count + 1;

        if (engine.w_read_fifo_push == 1'b1) begin
            resp_due_cycle[resp_wr_ptr] = cycle_count + RESP_DELAY_CYCLES;
            resp_expected[resp_wr_ptr]  = engine.w_read_expected_beat;
            resp_wr_ptr                 = (resp_wr_ptr + 1) % 256;
            resp_level                  = resp_level + 1;
        end
    end

    if ((rst_n == 1'b1) && (gf_compare_window == 1'b1)) begin
        compare_count = compare_count + 1;
        if (compare_count == 1) begin
            $display("FIRST_COMPARE t=%0t mode=%0d col=%0d bg=%0d ba=%0d",
                     $time, gf_op_mode, gf_cnt_col, gf_cnt_bg, gf_cnt_ba);
        end
        if ((gf_compare_mismatch_odd == 1'b1) ||
            (gf_compare_mismatch_even == 1'b1)) begin
            mismatch_count = mismatch_count + 1;
            if (mismatch_count <= 4) begin
                $display("MISMATCH t=%0t col=%0d bg=%0d ba=%0d odd=%0b even=%0b",
                         $time,
                         gf_cnt_col,
                         gf_cnt_bg,
                         gf_cnt_ba,
                         gf_compare_mismatch_odd,
                         gf_compare_mismatch_even);
            end
        end
    end
end

initial begin
    clk              = 1'b0;
    rst_n            = 1'b0;
    gf_total_en      = 1'b0;
    dq_a_burst_flat_r  = 256'd0;
    dq_a_burst_valid_r = 1'b0;
    timeout_count    = 0;
    compare_count    = 0;
    mismatch_count   = 0;
    pass_start_count = 0;
    cycle_count      = 0;
    resp_wr_ptr      = 0;
    resp_rd_ptr      = 0;
    resp_level       = 0;

    force ctrl.gf_start_col_bus = {8{6'd0}};
    force ctrl.gf_end_col_bus   = {8{END_COL_TEST[5:0]}};
    force ctrl.gf_start_row_bus = {8{18'd0}};
    force ctrl.gf_end_row_bus   = {8{END_ROW_TEST[17:0]}};

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (3) @(posedge clk);
    gf_total_en = 1'b1;

    while ((gf_total_done == 1'b0) && (timeout_count < 800000)) begin
        @(posedge clk);
        timeout_count = timeout_count + 1;
    end

    if (timeout_count >= 800000) begin
        $display("TB FAIL: timeout");
    end
    else if (pass_start_count != PASS_COUNT) begin
        $display("TB FAIL: expected %0d pass starts, got %0d",
                 PASS_COUNT, pass_start_count);
    end
    else if (compare_count == 0) begin
        $display("TB FAIL: no read comparisons");
    end
    else if (mismatch_count != 0) begin
        $display("TB FAIL: mismatches=%0d compares=%0d",
                 mismatch_count, compare_count);
    end
    else begin
        $display("TB PASS: pass handoff clean, compares=%0d", compare_count);
    end

    $finish;
end

endmodule
