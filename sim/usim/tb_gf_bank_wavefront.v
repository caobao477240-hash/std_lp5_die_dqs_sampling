`timescale 1ns / 1ps

// Bank-wavefront GF stream check.
// Range: 2 banks, 1 row, 4 columns, READ_WRITE pass.
module tb_gf_bank_wavefront #(
    parameter [9:0] ACT_GAP_CYCLES = 10'd16,
    parameter [9:0] RD_GAP_CYCLES  = 10'd12,
    parameter [9:0] WR_GAP_CYCLES  = 10'd10,
    parameter [9:0] PRE_GAP_CYCLES = 10'd16
);

reg         clk;
reg         rst_n;
reg         gf_test_en;
reg         gf_pass_start;
reg [255:0] dq_a_burst_flat;
reg         dq_a_burst_valid;

wire [20:0] gf_state;
wire        gf_pass_done;
wire        gf_en_read;
wire        gf_en_write;
wire        rx_dq_capture_en;
wire [9:0]  gf_cnt_read;
wire [9:0]  gf_cnt_write;
wire        gf_compare_window;
wire        gf_compare_mismatch_odd;
wire        gf_compare_mismatch_even;
wire [27:0] gf_access_addr;
wire [15:0] gf_read_expected_beat;
wire [1:0]  gf_cnt_ba;
wire [1:0]  gf_cnt_bg;
wire [17:0] gf_cnt_row;
wire [5:0]  gf_cnt_col;
wire [17:0] gf_cnt_row_ns;
wire [111:0] ascii_state;
wire        wave_ck_a_run_en;
wire        wave_cs_a_0_fall;
wire        wave_cs_a_0_rise;
wire [6:0]  wave_ca_a_fall;
wire [6:0]  wave_ca_a_rise;
wire [1:0]  wave_wck_a_run_en;
wire [1:0]  wave_wck_a_phase;
wire [63:0] wave_dq_a_tx_word;
wire        wave_dq_oe;

localparam [9:0] RESP_DELAY_CYCLES = 10'd18;
localparam [7:0] READ_CAPTURE_START = 8'd10;
localparam [1:0] GF_OP_READ_WRITE = 2'd2;

localparam [20:0] GF_READ_STATE             = 21'b0_0000_0000_0100_0000_0000;
localparam [20:0] GF_WRITE_AFTER_READ_STATE = 21'b0_0000_0000_0100_0000_0001;

integer cycle_count;
integer errors;
integer timeout;
integer total_rd_cmd;
integer total_wr_cmd;
integer total_capture;
integer total_compare;
integer total_wr_payload;
integer col_idx;
integer last_rd_cycle;
integer last_wr_cycle;
integer last_rd_col;
integer last_wr_col;
integer last_rd_wck_cycle;
integer last_wr_wck_cycle;
integer resp_wr_ptr;
integer resp_rd_ptr;
integer resp_level;

integer rd_cmd_count [0:3];
integer wr_cmd_count [0:3];
reg [1:0] rd_bank_seen [0:3];
reg [1:0] wr_bank_seen [0:3];

reg [31:0] resp_due_cycle [0:31];
reg [15:0] resp_expected  [0:31];
reg [27:0] resp_addr      [0:31];
reg [27:0] compare_addr_expected;

function [15:0] tb_addr_beat;
    input [17:0] addr_row;
    input [1:0]  addr_bg;
    input [1:0]  addr_ba;
    input [5:0]  addr_col;
    begin
        tb_addr_beat = {addr_row[5:0], addr_bg, addr_ba, addr_col};
    end
endfunction

function [15:0] tb_march_beat;
    input        data_sel;
    input [17:0] addr_row;
    input [1:0]  addr_bg;
    input [1:0]  addr_ba;
    input [5:0]  addr_col;
    reg   [15:0] addr_beat;
    begin
        addr_beat = tb_addr_beat(addr_row, addr_bg, addr_ba, addr_col);

        if (data_sel == addr_beat[0])
            tb_march_beat = addr_beat;
        else
            tb_march_beat = ~addr_beat;
    end
endfunction

function [63:0] tb_march_word;
    input        data_sel;
    input [17:0] addr_row;
    input [1:0]  addr_bg;
    input [1:0]  addr_ba;
    input [5:0]  addr_col;
    input [9:0]  payload_cnt;
    reg   [15:0] addr_pattern;
    reg   [15:0] beat0;
    begin
        addr_pattern = tb_march_beat(data_sel, addr_row, addr_bg, addr_ba, addr_col);
        beat0 = {4'b0000, payload_cnt, 2'b00} - 16'd1;
        tb_march_word = {
            ((beat0 + 16'd3) & 16'd1) ? ~addr_pattern : addr_pattern,
            ((beat0 + 16'd2) & 16'd1) ? ~addr_pattern : addr_pattern,
            ((beat0 + 16'd1) & 16'd1) ? ~addr_pattern : addr_pattern,
            ( beat0           & 16'd1) ? ~addr_pattern : addr_pattern
        };
    end
endfunction

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

lpddr5_gf_engine #(
    .T_RCD         (8   ),
    .T_READ        (32  ),
    .T_WRITE       (24  ),
    .T_RPab        (8   ),
    .TRFCab        (40  ),
    .T_REFI_CYCLES (1000)
) dut (
    .clk                             (clk                         ),
    .rst_n                           (rst_n                       ),
    .engine_inhibit                  (1'b0                        ),
    .idd_ck_stop                     (1'b0                        ),
    .GF_start_col                    (6'd0                        ),
    .GF_end_col                      (6'd3                        ),
    .GF_start_row                    (18'd0                       ),
    .GF_end_row                      (18'd0                       ),
    .GF_start_bg                     (2'd0                        ),
    .GF_end_bg                       (2'd0                        ),
    .GF_start_ba                     (2'd0                        ),
    .GF_end_ba                       (2'd1                        ),
    .gf_test_en                      (gf_test_en                  ),
    .gf_pass_start                   (gf_pass_start               ),
    .gf_op_mode                      (GF_OP_READ_WRITE            ),
    .gf_read_data_sel                (1'b0                        ),
    .gf_write_data_sel               (1'b1                        ),
    .march_y_sequence                (1'b0                        ),
    .die_message                     (8'h18                       ),
    .read_capture_start_cnt          (READ_CAPTURE_START          ),
    .gf_rd_wck_start_cnt             (10'd4                       ),
    .gf_rd_wck_last_cnt              (10'd20                      ),
    .gf_wr_wck_start_cnt             (10'd4                       ),
    .gf_wr_wck_last_cnt              (10'd18                      ),
    .gf_read_done_cnt                (10'd31                      ),
    .gf_write_done_cnt               (10'd23                      ),
    .gf_act_cmd_gap_cnt              (ACT_GAP_CYCLES              ),
    .gf_rd_cmd_gap_cnt               (RD_GAP_CYCLES               ),
    .gf_wr_cmd_gap_cnt               (WR_GAP_CYCLES               ),
    .gf_pre_cmd_gap_cnt              (PRE_GAP_CYCLES              ),
    .gf_refresh_batch_num            (3'd1                        ),
    .gf_pattern_mode_cfg             (2'd0                        ),
    .dq_a_burst_flat                 (dq_a_burst_flat             ),
    .dq_a_burst_valid                (dq_a_burst_valid            ),
    .err_cnt_GF                      (                            ),
    .err_block_cnt                   (                            ),
    .err_block_message               (                            ),
    .gf_pass_done                    (gf_pass_done                ),
    .gf_state                        (gf_state                    ),
    .gf_pass_start_d                 (                            ),
    .gf_en_read                      (gf_en_read                  ),
    .gf_en_write                     (gf_en_write                 ),
    .rx_dq_capture_en                (rx_dq_capture_en            ),
    .gf_err_flag                     (                            ),
    .gf_cnt_read_value               (gf_cnt_read                 ),
    .gf_cnt_write_value              (gf_cnt_write                ),
    .gf_compare_window               (gf_compare_window           ),
    .gf_compare_mismatch_odd         (gf_compare_mismatch_odd     ),
    .gf_compare_mismatch_even        (gf_compare_mismatch_even    ),
    .gf_access_addr                  (gf_access_addr              ),
    .gf_read_expected_beat           (gf_read_expected_beat       ),
    .gf_cnt_ba                       (gf_cnt_ba                   ),
    .gf_cnt_bg                       (gf_cnt_bg                   ),
    .gf_cnt_row                      (gf_cnt_row                  ),
    .gf_cnt_col                      (gf_cnt_col                  ),
    .gf_cnt_row_ns                   (gf_cnt_row_ns               ),
    .ascii_state                     (ascii_state                 ),
    .wave_ck_a_run_en                (wave_ck_a_run_en            ),
    .wave_cs_a_0_fall                  (wave_cs_a_0_fall              ),
    .wave_cs_a_0_rise                  (wave_cs_a_0_rise              ),
    .wave_ca_a_fall                    (wave_ca_a_fall                ),
    .wave_ca_a_rise                    (wave_ca_a_rise                ),
    .wave_wck_a_run_en                   (wave_wck_a_run_en               ),
    .wave_wck_a_phase                   (wave_wck_a_phase               ),
    .wave_dq_a_tx_word               (wave_dq_a_tx_word           ),
    .wave_dq_oe                      (wave_dq_oe                  )
);

always #2.5 clk = ~clk;

always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0)
        cycle_count <= 0;
    else
        cycle_count <= cycle_count + 1;
end

always @(posedge clk) begin
    if ((rst_n == 1'b1) && (dut.w_read_cmd_first == 1'b1)) begin
        total_rd_cmd = total_rd_cmd + 1;

        if (dut.w_access_col > 6'd3) begin
            errors = errors + 1;
            $display("TB ERR: RD col out of range col=%0d t=%0t", dut.w_access_col, $time);
        end
        else begin
            col_idx = dut.w_access_col;

            if (dut.w_read_bank_index > 4'd1) begin
                errors = errors + 1;
                $display("TB ERR: RD bank out of range bank=%0d col=%0d t=%0t",
                         dut.w_read_bank_index, col_idx, $time);
            end

            if ((col_idx > 0) && (rd_cmd_count[col_idx] == 0) &&
                (wr_cmd_count[col_idx - 1] != 2)) begin
                errors = errors + 1;
                $display("TB ERR: col advanced before previous col WR stream finished col=%0d prev_wr=%0d t=%0t",
                         col_idx, wr_cmd_count[col_idx - 1], $time);
            end

            if (wr_cmd_count[col_idx] != 0) begin
                errors = errors + 1;
                $display("TB ERR: RD after WR in same col col=%0d t=%0t", col_idx, $time);
            end

            if (((rd_cmd_count[col_idx] == 0) && (dut.w_read_bank_index != 4'd0)) ||
                ((rd_cmd_count[col_idx] == 1) && (dut.w_read_bank_index != 4'd1)) ||
                (rd_cmd_count[col_idx] > 1)) begin
                errors = errors + 1;
                $display("TB ERR: RD bank order col=%0d count=%0d bank=%0d t=%0t",
                         col_idx, rd_cmd_count[col_idx], dut.w_read_bank_index, $time);
            end

            if ((last_rd_col == col_idx) && ((cycle_count - last_rd_cycle) != RD_GAP_CYCLES)) begin
                errors = errors + 1;
                $display("TB ERR: RD gap col=%0d gap=%0d t=%0t",
                         col_idx, cycle_count - last_rd_cycle, $time);
            end

            rd_cmd_count[col_idx] = rd_cmd_count[col_idx] + 1;
            rd_bank_seen[col_idx][dut.w_read_bank_index[0]] = 1'b1;
            last_rd_col = col_idx;
            last_rd_cycle = cycle_count;

            resp_due_cycle[resp_wr_ptr] = cycle_count + RESP_DELAY_CYCLES + {30'd0, dut.w_read_bank_index[0], 1'b0};
            resp_expected[resp_wr_ptr]  = tb_march_beat(1'b0,
                                                        dut.w_access_row,
                                                        dut.w_read_bg,
                                                        dut.w_read_ba,
                                                        dut.w_access_col);
            resp_addr[resp_wr_ptr]      = {dut.w_read_ba, dut.w_read_bg, dut.w_access_row, dut.w_access_col};

            if (dut.w_read_expected_beat !== resp_expected[resp_wr_ptr]) begin
                errors = errors + 1;
                $display("TB ERR: RD expected pattern mismatch got=%h exp=%h col=%0d bank=%0d t=%0t",
                         dut.w_read_expected_beat, resp_expected[resp_wr_ptr],
                         dut.w_access_col, dut.w_read_bank_index, $time);
            end

            resp_wr_ptr = resp_wr_ptr + 1;
            resp_level  = resp_level + 1;
        end
    end

    if ((rst_n == 1'b1) && (dut.w_write_cmd_first == 1'b1)) begin
        total_wr_cmd = total_wr_cmd + 1;

        if (dut.w_access_col > 6'd3) begin
            errors = errors + 1;
            $display("TB ERR: WR col out of range col=%0d t=%0t", dut.w_access_col, $time);
        end
        else begin
            col_idx = dut.w_access_col;

            if (dut.w_write_bank_index > 4'd1) begin
                errors = errors + 1;
                $display("TB ERR: WR bank out of range bank=%0d col=%0d t=%0t",
                         dut.w_write_bank_index, col_idx, $time);
            end

            if (rd_cmd_count[col_idx] != 2) begin
                errors = errors + 1;
                $display("TB ERR: WR before full RD stream col=%0d rd_count=%0d t=%0t",
                         col_idx, rd_cmd_count[col_idx], $time);
            end

            if (rd_bank_seen[col_idx][dut.w_write_bank_index[0]] != 1'b1) begin
                errors = errors + 1;
                $display("TB ERR: WR before RD same bank col=%0d bank=%0d t=%0t",
                         col_idx, dut.w_write_bank_index, $time);
            end

            if (((wr_cmd_count[col_idx] == 0) && (dut.w_write_bank_index != 4'd0)) ||
                ((wr_cmd_count[col_idx] == 1) && (dut.w_write_bank_index != 4'd1)) ||
                (wr_cmd_count[col_idx] > 1)) begin
                errors = errors + 1;
                $display("TB ERR: WR bank order col=%0d count=%0d bank=%0d t=%0t",
                         col_idx, wr_cmd_count[col_idx], dut.w_write_bank_index, $time);
            end

            if ((last_wr_col == col_idx) && ((cycle_count - last_wr_cycle) != WR_GAP_CYCLES)) begin
                errors = errors + 1;
                $display("TB ERR: WR gap col=%0d gap=%0d t=%0t",
                         col_idx, cycle_count - last_wr_cycle, $time);
            end

            wr_cmd_count[col_idx] = wr_cmd_count[col_idx] + 1;
            wr_bank_seen[col_idx][dut.w_write_bank_index[0]] = 1'b1;
            last_wr_col = col_idx;
            last_wr_cycle = cycle_count;
        end
    end

    if ((rst_n == 1'b1) &&
        (dut.w_wr_dq_oe_active == 1'b1) &&
        (dut.cnt_write >= 10'd10) &&
        ((dut.w_write_payload_rel % WR_GAP_CYCLES) == 10'd1) &&
        (dut.w_write_payload_slot < dut.w_bank_count)) begin
        total_wr_payload = total_wr_payload + 1;

        if (wave_dq_a_tx_word !== tb_march_word(1'b1,
                                                dut.w_access_row,
                                                dut.w_write_data_bg,
                                                dut.w_write_data_ba,
                                                dut.w_access_col,
                                                dut.w_write_payload_rel)) begin
            errors = errors + 1;
            $display("TB ERR: WR payload pattern mismatch got=%h exp=%h col=%0d bank=%0d t=%0t",
                     wave_dq_a_tx_word,
                     tb_march_word(1'b1,
                                   dut.w_access_row,
                                   dut.w_write_data_bg,
                                   dut.w_write_data_ba,
                                   dut.w_access_col,
                                   dut.w_write_payload_rel),
                     dut.w_access_col, dut.w_write_data_bank_index, $time);
        end
    end

    if ((rst_n == 1'b1) && (rx_dq_capture_en == 1'b1))
        total_capture = total_capture + 1;

    if ((rst_n == 1'b1) && (gf_compare_window == 1'b1)) begin
        total_compare = total_compare + 1;

        if (gf_access_addr !== compare_addr_expected) begin
            errors = errors + 1;
            $display("TB ERR: compare addr mismatch got=%h exp=%h t=%0t",
                     gf_access_addr, compare_addr_expected, $time);
        end

        if ((gf_compare_mismatch_odd == 1'b1) ||
            (gf_compare_mismatch_even == 1'b1)) begin
            errors = errors + 1;
            $display("TB ERR: compare data mismatch odd=%0b even=%0b t=%0t",
                     gf_compare_mismatch_odd, gf_compare_mismatch_even, $time);
        end
    end

    if ((rst_n == 1'b1) && (dut.w_wck_rd_active == 1'b1)) begin
        if ((last_rd_wck_cycle >= 0) &&
            (gf_state == GF_READ_STATE) &&
            ((cycle_count - last_rd_wck_cycle) != 1)) begin
            errors = errors + 1;
            $display("TB ERR: RD WCK gap=%0d t=%0t", cycle_count - last_rd_wck_cycle, $time);
        end
        last_rd_wck_cycle = cycle_count;
    end
    else if (gf_state != GF_READ_STATE) begin
        last_rd_wck_cycle = -1;
    end

    if ((rst_n == 1'b1) && (dut.w_wck_wr_active == 1'b1)) begin
        if ((last_wr_wck_cycle >= 0) &&
            (gf_state == GF_WRITE_AFTER_READ_STATE) &&
            ((cycle_count - last_wr_wck_cycle) != 1)) begin
            errors = errors + 1;
            $display("TB ERR: WR WCK gap=%0d t=%0t", cycle_count - last_wr_wck_cycle, $time);
        end
        last_wr_wck_cycle = cycle_count;
    end
    else if (gf_state != GF_WRITE_AFTER_READ_STATE) begin
        last_wr_wck_cycle = -1;
    end
end

always @(negedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) begin
        dq_a_burst_flat      <= 256'h0;
        dq_a_burst_valid     <= 1'b0;
        compare_addr_expected <= 28'h0;
    end
    else if ((resp_level > 0) && (cycle_count >= resp_due_cycle[resp_rd_ptr])) begin
        dq_a_burst_flat      <= tb_address_toggle_burst(resp_expected[resp_rd_ptr]);
        dq_a_burst_valid     <= 1'b1;
        compare_addr_expected <= resp_addr[resp_rd_ptr];
        resp_rd_ptr          = resp_rd_ptr + 1;
        resp_level           = resp_level - 1;
    end
    else begin
        dq_a_burst_flat  <= 256'h0;
        dq_a_burst_valid <= 1'b0;
    end
end

initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    gf_test_en = 1'b0;
    gf_pass_start = 1'b0;
    dq_a_burst_flat = 256'h0;
    dq_a_burst_valid = 1'b0;
    compare_addr_expected = 28'h0;
    cycle_count = 0;
    errors = 0;
    timeout = 0;
    total_rd_cmd = 0;
    total_wr_cmd = 0;
    total_capture = 0;
    total_compare = 0;
    total_wr_payload = 0;
    last_rd_cycle = -1;
    last_wr_cycle = -1;
    last_rd_col = -1;
    last_wr_col = -1;
    last_rd_wck_cycle = -1;
    last_wr_wck_cycle = -1;
    resp_wr_ptr = 0;
    resp_rd_ptr = 0;
    resp_level = 0;

    for (col_idx = 0; col_idx < 4; col_idx = col_idx + 1) begin
        rd_cmd_count[col_idx] = 0;
        wr_cmd_count[col_idx] = 0;
        rd_bank_seen[col_idx] = 2'b00;
        wr_bank_seen[col_idx] = 2'b00;
    end

    repeat (8) @(posedge clk);
    rst_n = 1'b1;
    repeat (4) @(posedge clk);
    gf_test_en = 1'b1;
    gf_pass_start = 1'b1;

    while ((gf_pass_done == 1'b0) && (timeout < 5000)) begin
        @(posedge clk);
        timeout = timeout + 1;
    end

    repeat (10) @(posedge clk);

    for (col_idx = 0; col_idx < 4; col_idx = col_idx + 1) begin
        if (rd_cmd_count[col_idx] != 2) begin
            errors = errors + 1;
            $display("TB ERR: final RD count col=%0d count=%0d", col_idx, rd_cmd_count[col_idx]);
        end

        if (wr_cmd_count[col_idx] != 2) begin
            errors = errors + 1;
            $display("TB ERR: final WR count col=%0d count=%0d", col_idx, wr_cmd_count[col_idx]);
        end
    end

    if (timeout >= 5000) begin
        errors = errors + 1;
        $display("TB ERR: timeout state=%h rd=%0d wr=%0d cmp=%0d", gf_state, total_rd_cmd, total_wr_cmd, total_compare);
    end

    if (total_rd_cmd != 8) begin
        errors = errors + 1;
        $display("TB ERR: total RD command count=%0d", total_rd_cmd);
    end

    if (total_wr_cmd != 8) begin
        errors = errors + 1;
        $display("TB ERR: total WR command count=%0d", total_wr_cmd);
    end

    if (total_capture != 8) begin
        errors = errors + 1;
        $display("TB ERR: total capture count=%0d", total_capture);
    end

    if (total_compare != 8) begin
        errors = errors + 1;
        $display("TB ERR: total compare count=%0d", total_compare);
    end

    if (total_wr_payload != 8) begin
        errors = errors + 1;
        $display("TB ERR: total write payload count=%0d", total_wr_payload);
    end

    if (resp_level != 0) begin
        errors = errors + 1;
        $display("TB ERR: response queue not empty level=%0d", resp_level);
    end

    if (errors == 0) begin
        $display("TB PASS: GF bank wavefront rd=%0d wr=%0d payload=%0d capture=%0d compare=%0d",
                 total_rd_cmd, total_wr_cmd, total_wr_payload, total_capture, total_compare);
    end
    else begin
        $display("TB FAIL: GF bank wavefront errors=%0d rd=%0d wr=%0d payload=%0d capture=%0d compare=%0d",
                 errors, total_rd_cmd, total_wr_cmd, total_wr_payload, total_capture, total_compare);
    end

    $finish;
end

endmodule
