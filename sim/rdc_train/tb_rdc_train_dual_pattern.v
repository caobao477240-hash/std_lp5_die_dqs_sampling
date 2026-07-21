`timescale 1ns / 1ps

module tb_rdc_train_dual_pattern;

/***************parameter*************/
localparam [3:0]  RDC_TRAIN_SET_MR33 = 4'd4;
localparam [3:0]  RDC_TRAIN_SET_MR34 = 4'd6;
localparam [6:0]  MR33_ADDR          = 7'h21;
localparam [6:0]  MR34_ADDR          = 7'h22;

/***************reg*******************/
reg                 clk;
reg                 rst_n;
reg                 train_start;
reg                 train_clear;
reg                 train_apply_best_cfg;
reg                 train_dual_pattern_cfg;
reg  [  3:0]        train_dq_start_cfg;
reg  [  3:0]        train_dq_end_cfg;
reg  [  8:0]        train_tap_start_cfg;
reg  [  8:0]        train_tap_stop_cfg;
reg  [  8:0]        train_tap_step_cfg;
reg                 dq_delay_l_we;
reg                 dq_delay_h_we;
reg  [ 95:0]        dq_delay_wdat;
reg                 train_init_ready_in;
reg                 runtime_mr_busy;
reg  [ 15:0]        rdc_err_bitmap;
reg                 rdc_check_valid;
reg  [  8:0]        train_scan_tap_sel;
reg                 mrr_start_d;
reg                 mrw_start_d;
reg  [  7:0]        runtime_busy_cnt;
reg  [  7:0]        rdc_latency_cnt;
reg  [  7:0]        expected_op;
reg  [  6:0]        expected_addr;
reg  [ 15:0]        result_bitmap;
reg                 inject_hole_en;
reg                 center_fail_en;
reg                 narrow_window_en;

integer             idx;
integer             timeout_cnt;
integer             error_count;
integer             mrw_cmd_count;
integer             mrr_cmd_count;
integer             transient_hole_count;
integer             transient_pass_count;
integer             persistent_hole_count;
integer             center_fail_count;
integer             scan_clear_cycle_count;

/***************wire******************/
wire [143:0]        dq_delay_flat;
wire [ 23:0]        mrw_r;
wire [ 31:0]        mrr_r;
wire [  3:0]        train_state;
wire                train_busy;
wire                train_done;
wire                train_apply_best;
wire [  3:0]        train_dq_start;
wire [  8:0]        train_tap;
wire                train_pattern_sel;
wire [  9:0]        train_status_best_len;
wire [ 15:0]        train_pass_mask;
wire [ 15:0]        train_fail_mask;
wire [ 15:0]        train_last_err_bitmap;
wire                train_init_ready;
wire                train_pass_all;
wire [143:0]        train_best_flat;
wire [143:0]        train_left_flat;
wire [143:0]        train_right_flat;
wire [ 15:0]        train_scan_pass_bitmap;

/***************component*************/
rdc_train rdc_train_u0 (
    .clk                         (clk                         ),
    .rst_n                       (rst_n                       ),
    .train_start                 (train_start                 ),
    .train_clear                 (train_clear                 ),
    .train_apply_best_cfg        (train_apply_best_cfg        ),
    .train_dual_pattern_cfg      (train_dual_pattern_cfg      ),
    .train_dq_start_cfg          (train_dq_start_cfg          ),
    .train_dq_end_cfg            (train_dq_end_cfg            ),
    .train_tap_start_cfg         (train_tap_start_cfg         ),
    .train_tap_stop_cfg          (train_tap_stop_cfg          ),
    .train_tap_step_cfg          (train_tap_step_cfg          ),
    .dq_delay_l_we               (dq_delay_l_we               ),
    .dq_delay_h_we               (dq_delay_h_we               ),
    .dq_delay_wdat               (dq_delay_wdat               ),
    .train_init_ready_in         (train_init_ready_in         ),
    .runtime_mr_busy             (runtime_mr_busy             ),
    .rdc_err_bitmap              (rdc_err_bitmap              ),
    .rdc_check_valid             (rdc_check_valid             ),
    .train_scan_tap_sel          (train_scan_tap_sel          ),
    .dq_delay_flat               (dq_delay_flat               ),
    .mrw_r                       (mrw_r                       ),
    .mrr_r                       (mrr_r                       ),
    .train_state                 (train_state                 ),
    .train_busy                  (train_busy                  ),
    .train_done                  (train_done                  ),
    .train_apply_best            (train_apply_best            ),
    .train_dq_start              (train_dq_start              ),
    .train_tap                   (train_tap                   ),
    .train_pattern_sel           (train_pattern_sel           ),
    .train_status_best_len       (train_status_best_len       ),
    .train_pass_mask             (train_pass_mask             ),
    .train_fail_mask             (train_fail_mask             ),
    .train_last_err_bitmap       (train_last_err_bitmap       ),
    .train_init_ready            (train_init_ready            ),
    .train_pass_all              (train_pass_all              ),
    .train_best_flat             (train_best_flat             ),
    .train_left_flat             (train_left_flat             ),
    .train_right_flat            (train_right_flat            ),
    .train_scan_pass_bitmap      (train_scan_pass_bitmap      )
);

/***************function**************/
function rdc_pattern_pass;
    input [3:0] dq_idx;
    input [8:0] tap_value;
    input       pattern_sel;
    begin
        rdc_pattern_pass = 1'b0;

        if (pattern_sel == 1'b0) begin
            case (dq_idx)
                4'd0: rdc_pattern_pass = ((tap_value >= 9'd4 ) && (tap_value <= 9'd20));
                4'd1: rdc_pattern_pass = ((tap_value >= 9'd0 ) && (tap_value <= 9'd30));
                4'd2: rdc_pattern_pass = ((tap_value >= 9'd6 ) && (tap_value <= 9'd18));
                4'd3: rdc_pattern_pass = ((tap_value >= 9'd20) && (tap_value <= 9'd30));
                default: rdc_pattern_pass = 1'b1;
            endcase
        end
        else begin
            case (dq_idx)
                4'd0: rdc_pattern_pass = ((tap_value >= 9'd8 ) && (tap_value <= 9'd16));
                4'd1: rdc_pattern_pass = ((tap_value >= 9'd12) && (tap_value <= 9'd22));
                4'd2: rdc_pattern_pass = ((tap_value >= 9'd10) && (tap_value <= 9'd24));
                4'd3: rdc_pattern_pass = ((tap_value >= 9'd0 ) && (tap_value <= 9'd24));
                default: rdc_pattern_pass = 1'b1;
            endcase
        end
    end
endfunction

function [8:0] expected_best_tap;
    input [3:0] dq_idx;
    begin
        case (dq_idx)
            4'd0: expected_best_tap = 9'd9;
            4'd1: expected_best_tap = 9'd17;
            4'd2: expected_best_tap = 9'd14;
            4'd3: expected_best_tap = 9'd22;
            default: expected_best_tap = 9'd0;
        endcase
    end
endfunction

function [8:0] expected_best_tap_single;
    input [3:0] dq_idx;
    begin
        case (dq_idx)
            4'd0: expected_best_tap_single = 9'd12;
            4'd1: expected_best_tap_single = 9'd15;
            4'd2: expected_best_tap_single = 9'd12;
            4'd3: expected_best_tap_single = 9'd25;
            default: expected_best_tap_single = 9'd0;
        endcase
    end
endfunction

/***************assign****************/
/***************always****************/
always begin
    clk = 1'b0;
    #2.5;
    clk = 1'b1;
    #2.5;
end

always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) begin
        runtime_mr_busy <= 1'b0;
        runtime_busy_cnt <= 8'd0;
    end
    else if (((mrw_start_d == 1'b0) && (mrw_r[16] == 1'b1)) ||
             ((mrr_start_d == 1'b0) && (mrr_r[24] == 1'b1))) begin
        runtime_mr_busy <= 1'b1;
        runtime_busy_cnt <= 8'd24;
    end
    else if (runtime_busy_cnt > 8'd0) begin
        runtime_mr_busy <= 1'b1;
        runtime_busy_cnt <= runtime_busy_cnt - 8'd1;
    end
    else begin
        runtime_mr_busy <= 1'b0;
        runtime_busy_cnt <= runtime_busy_cnt;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) begin
        mrr_start_d     <= 1'b0;
        rdc_latency_cnt <= 8'd0;
        rdc_check_valid <= 1'b0;
        rdc_err_bitmap  <= 16'h0000;
    end
    else begin
        mrr_start_d     <= mrr_r[24];
        rdc_check_valid <= 1'b0;

        if ((mrr_start_d == 1'b0) && (mrr_r[24] == 1'b1)) begin
            rdc_latency_cnt <= 8'd8;
        end
        else if (rdc_latency_cnt > 8'd0) begin
            rdc_latency_cnt <= rdc_latency_cnt - 8'd1;

            if (rdc_latency_cnt == 8'd1) begin
                result_bitmap = 16'h0000;

                for (idx = 0; idx < 16; idx = idx + 1) begin
                    if (rdc_pattern_pass(
                            idx[3:0],
                            dq_delay_flat[(idx * 9) +: 9],
                            train_pattern_sel) == 1'b0) begin
                        result_bitmap[idx] = 1'b1;
                    end
                end

                if ((inject_hole_en == 1'b1) &&
                    (train_pattern_sel == 1'b1) &&
                    (train_tap == 9'd14) &&
                    (transient_hole_count == 0)) begin
                    result_bitmap[2] = 1'b1;
                    transient_hole_count = transient_hole_count + 1;
                end

                if ((inject_hole_en == 1'b1) &&
                    (train_pattern_sel == 1'b1) &&
                    (train_tap == 9'd12)) begin
                    result_bitmap[0] = 1'b1;
                    persistent_hole_count = persistent_hole_count + 1;
                end

                if ((inject_hole_en == 1'b1) &&
                    (train_pattern_sel == 1'b0) &&
                    (train_tap == 9'd19) &&
                    (transient_pass_count == 0)) begin
                    result_bitmap[3] = 1'b0;
                    transient_pass_count = transient_pass_count + 1;
                end

                // The fifth MRW starts the post-scan center verification.
                // Inject one physical failure in that verification only.
                if ((center_fail_en == 1'b1) &&
                    (train_pattern_sel == 1'b0) &&
                    (mrw_cmd_count >= 5) &&
                    (center_fail_count == 0)) begin
                    result_bitmap[2] = 1'b1;
                    center_fail_count = center_fail_count + 1;
                end

                // Leave only three consecutive pattern-1 pass points for DQ2.
                // The scan must reject this as an undersized window.
                if ((narrow_window_en == 1'b1) &&
                    (train_pattern_sel == 1'b1) &&
                    ((train_tap < 9'd10) || (train_tap > 9'd12))) begin
                    result_bitmap[2] = 1'b1;
                end

                rdc_err_bitmap  <= result_bitmap;
                rdc_check_valid <= 1'b1;
            end
        end
        else begin
            rdc_latency_cnt <= rdc_latency_cnt;
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) begin
        mrw_start_d   <= 1'b0;
        mrw_cmd_count <= 0;
    end
    else begin
        mrw_start_d <= mrw_r[16];

        if ((mrw_start_d == 1'b0) && (mrw_r[16] == 1'b1)) begin
            mrw_cmd_count = mrw_cmd_count + 1;

            if (runtime_mr_busy == 1'b1) begin
                $display("SIM FAIL: MRW starts while runtime_mr_busy is high, state=%0d", train_state);
                error_count = error_count + 1;
            end

            if (train_state == RDC_TRAIN_SET_MR33) begin
                expected_addr = MR33_ADDR;
                expected_op = train_pattern_sel ? 8'h3c : 8'h5a;
            end
            else if (train_state == RDC_TRAIN_SET_MR34) begin
                expected_addr = MR34_ADDR;
                expected_op = train_pattern_sel ? 8'hc3 : 8'ha5;
            end
            else begin
                expected_addr = 7'h00;
                $display("SIM FAIL: MRW pulse in unexpected state=%0d", train_state);
                error_count = error_count + 1;
            end

            if ({mrw_r[15], mrw_r[14:8]} != expected_op) begin
                $display("SIM FAIL: MRW op=%02h expected=%02h state=%0d",
                         {mrw_r[15], mrw_r[14:8]}, expected_op, train_state);
                error_count = error_count + 1;
            end

            if (mrw_r[7] != 1'b0) begin
                $display("SIM FAIL: MRW bit7 should stay 0, mrw=%06h", mrw_r);
                error_count = error_count + 1;
            end

            if (mrw_r[6:0] != expected_addr) begin
                $display("SIM FAIL: MRW addr=%02h expected=%02h state=%0d",
                         mrw_r[6:0], expected_addr, train_state);
                error_count = error_count + 1;
            end
        end
    end
end

always @(posedge clk) begin
    if ((rst_n == 1'b1) &&
        (mrr_start_d == 1'b0) &&
        (mrr_r[24] == 1'b1)) begin
        mrr_cmd_count = mrr_cmd_count + 1;

        if (runtime_mr_busy == 1'b1) begin
            $display("SIM FAIL: MRR starts while runtime_mr_busy is high, state=%0d", train_state);
            error_count = error_count + 1;
        end
    end
end

initial begin
    rst_n                = 1'b0;
    train_start          = 1'b0;
    train_clear          = 1'b0;
    train_apply_best_cfg = 1'b1;
    train_dual_pattern_cfg = 1'b1;
    train_dq_start_cfg   = 4'd0;
    train_dq_end_cfg     = 4'd3;
    train_tap_start_cfg  = 9'd0;
    train_tap_stop_cfg   = 9'd31;
    train_tap_step_cfg   = 9'd1;
    dq_delay_l_we        = 1'b0;
    dq_delay_h_we        = 1'b0;
    dq_delay_wdat        = 96'd0;
    train_init_ready_in  = 1'b0;
    runtime_mr_busy      = 1'b0;
    train_scan_tap_sel   = 9'd0;
    runtime_busy_cnt     = 8'd0;
    timeout_cnt          = 0;
    error_count          = 0;
    mrr_cmd_count        = 0;
    transient_hole_count = 0;
    transient_pass_count = 0;
    persistent_hole_count = 0;
    center_fail_count     = 0;
    scan_clear_cycle_count = 0;
    inject_hole_en       = 1'b1;
    center_fail_en        = 1'b0;
    narrow_window_en     = 1'b0;

    repeat (8) @(posedge clk);
    rst_n = 1'b1;
    repeat (8) @(posedge clk);

    if (train_scan_pass_bitmap !== 16'h0000) begin
        $display("SIM FAIL: scan bitmap is not zero after reset");
        error_count = error_count + 1;
    end

    train_init_ready_in = 1'b1;
    train_start         = 1'b1;
    @(posedge clk);
    train_start         = 1'b0;

    while ((train_busy == 1'b1) || (train_done == 1'b0)) begin
        @(posedge clk);
        timeout_cnt = timeout_cnt + 1;

        if (timeout_cnt > 200000) begin
            $display("SIM FAIL: timeout state=%0d tap=%0d pattern=%0d pass=%04h fail=%04h",
                     train_state,
                     train_tap,
                     train_pattern_sel,
                     train_pass_mask,
                     train_fail_mask);
            $finish;
        end
    end

    $display("SIM INFO: dual-pattern training complete");

    repeat (10) @(posedge clk);

    if (mrw_cmd_count != 8) begin
        $display("SIM FAIL: mrw_cmd_count=%0d expected=8", mrw_cmd_count);
        error_count = error_count + 1;
    end

    if (train_pass_mask[3:0] != 4'hf) begin
        $display("SIM FAIL: pass_mask[3:0]=%01h expected=f", train_pass_mask[3:0]);
        error_count = error_count + 1;
    end

    if (train_fail_mask[3:0] != 4'h0) begin
        $display("SIM FAIL: fail_mask[3:0]=%01h expected=0", train_fail_mask[3:0]);
        error_count = error_count + 1;
    end

    if (mrr_cmd_count <= 64) begin
        $display("SIM FAIL: adaptive retry did not add MRR reads, count=%0d", mrr_cmd_count);
        error_count = error_count + 1;
    end

    if (transient_hole_count != 1) begin
        $display("SIM FAIL: transient_hole_count=%0d expected=1", transient_hole_count);
        error_count = error_count + 1;
    end

    if (persistent_hole_count != 3) begin
        $display("SIM FAIL: persistent_hole_count=%0d expected=3", persistent_hole_count);
        error_count = error_count + 1;
    end

    if (transient_pass_count != 1) begin
        $display("SIM FAIL: transient_pass_count=%0d expected=1", transient_pass_count);
        error_count = error_count + 1;
    end

    if ((train_left_flat[(2 * 9) +: 9] != 9'd10) ||
        (train_right_flat[(2 * 9) +: 9] != 9'd18)) begin
        $display("SIM FAIL: transient DQ2 window=%0d..%0d expected=10..18",
                 train_left_flat[(2 * 9) +: 9],
                 train_right_flat[(2 * 9) +: 9]);
        error_count = error_count + 1;
    end

    if ((train_left_flat[8:0] != 9'd8) ||
        (train_right_flat[8:0] != 9'd11)) begin
        $display("SIM FAIL: persistent DQ0 window=%0d..%0d expected=8..11",
                 train_left_flat[8:0],
                 train_right_flat[8:0]);
        error_count = error_count + 1;
    end

    if ((train_left_flat[(3 * 9) +: 9] != 9'd20) ||
        (train_right_flat[(3 * 9) +: 9] != 9'd24)) begin
        $display("SIM FAIL: transient-pass DQ3 window=%0d..%0d expected=20..24",
                 train_left_flat[(3 * 9) +: 9],
                 train_right_flat[(3 * 9) +: 9]);
        error_count = error_count + 1;
    end

    train_scan_tap_sel = 9'd14;
    repeat (2) @(posedge clk);
    if (train_scan_pass_bitmap[2] != 1'b1) begin
        $display("SIM FAIL: DQ2 transient hole remains in final scan map");
        error_count = error_count + 1;
    end

    train_scan_tap_sel = 9'd12;
    repeat (2) @(posedge clk);
    if (train_scan_pass_bitmap[0] != 1'b0) begin
        $display("SIM FAIL: DQ0 persistent hole missing from final scan map");
        error_count = error_count + 1;
    end

    train_scan_tap_sel = 9'd19;
    repeat (2) @(posedge clk);
    if (train_scan_pass_bitmap[3] != 1'b0) begin
        $display("SIM FAIL: DQ3 transient false pass remains in final scan map");
        error_count = error_count + 1;
    end

    for (idx = 0; idx < 4; idx = idx + 1) begin
        $display("DQ%0d trained=%0d expected=%0d left=%0d right=%0d",
                 idx,
                 dq_delay_flat[(idx * 9) +: 9],
                 expected_best_tap(idx[3:0]),
                 train_left_flat[(idx * 9) +: 9],
                 train_right_flat[(idx * 9) +: 9]);

        if (dq_delay_flat[(idx * 9) +: 9] != expected_best_tap(idx[3:0])) begin
            error_count = error_count + 1;
        end
    end

    // Seed every location so the next train_clear must clear the full 512x16
    // map rather than only the taps used by the first training run.
    @(negedge clk);
    for (idx = 0; idx < 512; idx = idx + 1) begin
        rdc_train_u0.rdc_train_pat0_pass_mem[idx] = 16'hffff;
    end
    train_scan_tap_sel = 9'd511;
    repeat (2) @(posedge clk);
    #1;
    if (train_scan_pass_bitmap !== 16'hffff) begin
        $display("SIM FAIL: scan map seed was not observable before clear");
        error_count = error_count + 1;
    end

    @(negedge clk);
    train_clear = 1'b1;
    @(posedge clk);
    #1;
    train_clear = 1'b0;

    train_dual_pattern_cfg = 1'b0;
    timeout_cnt            = 0;
    mrw_cmd_count          = 0;
    mrr_cmd_count          = 0;
    inject_hole_en         = 1'b0;
    scan_clear_cycle_count = 0;

    if (train_scan_pass_bitmap !== 16'h0000) begin
        $display("SIM FAIL: scan bitmap is not zero when clear starts");
        error_count = error_count + 1;
    end

    // Pulse start before clear completes. The DUT must queue the request,
    // finish all 512 writes, and only then start the next training run.
    while (rdc_train_u0.r_rdc_train_scan_clear_active == 1'b1) begin
        @(negedge clk);
        if (scan_clear_cycle_count == 8) begin
            train_start = 1'b1;
        end
        else if (scan_clear_cycle_count == 9) begin
            train_start = 1'b0;
        end

        if (train_busy != 1'b0) begin
            $display("SIM FAIL: training started during scan-map clear");
            error_count = error_count + 1;
        end

        @(posedge clk);
        #1;
        scan_clear_cycle_count = scan_clear_cycle_count + 1;

        if (train_scan_pass_bitmap !== 16'h0000) begin
            $display("SIM FAIL: scan bitmap is not zero during clear, cycle=%0d",
                     scan_clear_cycle_count);
            error_count = error_count + 1;
        end
    end

    train_start = 1'b0;
    if (scan_clear_cycle_count != 512) begin
        $display("SIM FAIL: scan clear cycles=%0d expected=512",
                 scan_clear_cycle_count);
        error_count = error_count + 1;
    end

    for (idx = 0; idx < 512; idx = idx + 1) begin
        if (rdc_train_u0.rdc_train_pat0_pass_mem[idx] !== 16'h0000) begin
            $display("SIM FAIL: scan map tap %0d was not cleared", idx);
            error_count = error_count + 1;
        end
    end

    @(posedge clk);
    #1;
    if (train_busy != 1'b1) begin
        $display("SIM FAIL: queued training did not start after scan-map clear");
        error_count = error_count + 1;
    end

    while ((train_busy == 1'b1) || (train_done == 1'b0)) begin
        @(posedge clk);
        timeout_cnt = timeout_cnt + 1;

        if (timeout_cnt > 120000) begin
            $display("SIM FAIL: single-pattern timeout state=%0d tap=%0d pattern=%0d pass=%04h fail=%04h",
                     train_state,
                     train_tap,
                     train_pattern_sel,
                     train_pass_mask,
                     train_fail_mask);
            $finish;
        end
    end

    repeat (10) @(posedge clk);

    if (mrw_cmd_count != 4) begin
        $display("SIM FAIL: single-pattern mrw_cmd_count=%0d expected=4", mrw_cmd_count);
        error_count = error_count + 1;
    end

    if (train_pass_mask[3:0] != 4'hf) begin
        $display("SIM FAIL: single pass_mask[3:0]=%01h expected=f", train_pass_mask[3:0]);
        error_count = error_count + 1;
    end

    if (train_fail_mask[3:0] != 4'h0) begin
        $display("SIM FAIL: single fail_mask[3:0]=%01h expected=0", train_fail_mask[3:0]);
        error_count = error_count + 1;
    end

    for (idx = 0; idx < 4; idx = idx + 1) begin
        $display("DQ%0d single-trained=%0d expected=%0d left=%0d right=%0d",
                 idx,
                 dq_delay_flat[(idx * 9) +: 9],
                 expected_best_tap_single(idx[3:0]),
                 train_left_flat[(idx * 9) +: 9],
                 train_right_flat[(idx * 9) +: 9]);

        if (dq_delay_flat[(idx * 9) +: 9] != expected_best_tap_single(idx[3:0])) begin
            error_count = error_count + 1;
        end
    end

    // Verify that a single center-read failure rejects the candidate and
    // restores the tap values saved before this training run.
    train_dual_pattern_cfg = 1'b1;
    timeout_cnt            = 0;
    mrw_cmd_count          = 0;
    mrr_cmd_count          = 0;
    center_fail_count      = 0;
    center_fail_en         = 1'b1;
    train_start            = 1'b1;
    @(posedge clk);
    train_start            = 1'b0;
    repeat (2) @(posedge clk);

    while ((train_busy == 1'b1) || (train_done == 1'b0)) begin
        @(posedge clk);
        timeout_cnt = timeout_cnt + 1;

        if (timeout_cnt > 200000) begin
            $display("SIM FAIL: center-check timeout state=%0d tap=%0d pattern=%0d pass=%04h fail=%04h",
                     train_state,
                     train_tap,
                     train_pattern_sel,
                     train_pass_mask,
                     train_fail_mask);
            $finish;
        end
    end

    repeat (10) @(posedge clk);

    if (mrw_cmd_count != 6) begin
        $display("SIM FAIL: center-check mrw_cmd_count=%0d expected=6", mrw_cmd_count);
        error_count = error_count + 1;
    end

    if (train_pass_all != 1'b0) begin
        $display("SIM FAIL: center-check unexpectedly passed");
        error_count = error_count + 1;
    end

    if (train_fail_mask[3:0] != 4'b0100) begin
        $display("SIM FAIL: center-check fail_mask[3:0]=%01h expected=4", train_fail_mask[3:0]);
        error_count = error_count + 1;
    end

    if (center_fail_count != 1) begin
        $display("SIM FAIL: center_fail_count=%0d expected=1", center_fail_count);
        error_count = error_count + 1;
    end

    for (idx = 0; idx < 4; idx = idx + 1) begin
        if (dq_delay_flat[(idx * 9) +: 9] != expected_best_tap_single(idx[3:0])) begin
            $display("SIM FAIL: center-check did not restore DQ%0d tap=%0d expected=%0d",
                     idx,
                     dq_delay_flat[(idx * 9) +: 9],
                     expected_best_tap_single(idx[3:0]));
            error_count = error_count + 1;
        end
    end

    // Verify that a contiguous run shorter than P_MIN_WINDOW_POINTS is
    // rejected before any center verification is started.
    center_fail_en     = 1'b0;
    narrow_window_en   = 1'b1;
    train_dual_pattern_cfg = 1'b1;
    timeout_cnt        = 0;
    mrw_cmd_count      = 0;
    mrr_cmd_count      = 0;
    train_start        = 1'b1;
    @(posedge clk);
    train_start        = 1'b0;
    repeat (2) @(posedge clk);

    while ((train_busy == 1'b1) || (train_done == 1'b0)) begin
        @(posedge clk);
        timeout_cnt = timeout_cnt + 1;

        if (timeout_cnt > 200000) begin
            $display("SIM FAIL: narrow-window timeout state=%0d tap=%0d pattern=%0d pass=%04h fail=%04h",
                     train_state,
                     train_tap,
                     train_pattern_sel,
                     train_pass_mask,
                     train_fail_mask);
            $finish;
        end
    end

    repeat (10) @(posedge clk);

    if (mrw_cmd_count != 4) begin
        $display("SIM FAIL: narrow-window mrw_cmd_count=%0d expected=4", mrw_cmd_count);
        error_count = error_count + 1;
    end

    if (train_pass_all != 1'b0) begin
        $display("SIM FAIL: narrow-window unexpectedly passed");
        error_count = error_count + 1;
    end

    if (train_fail_mask[3:0] != 4'b0100) begin
        $display("SIM FAIL: narrow-window fail_mask[3:0]=%01h expected=4", train_fail_mask[3:0]);
        error_count = error_count + 1;
    end

    if (train_pass_mask[3:0] != 4'b1011) begin
        $display("SIM FAIL: narrow-window pass_mask[3:0]=%01h expected=b", train_pass_mask[3:0]);
        error_count = error_count + 1;
    end

    for (idx = 0; idx < 4; idx = idx + 1) begin
        if (dq_delay_flat[(idx * 9) +: 9] != expected_best_tap_single(idx[3:0])) begin
            $display("SIM FAIL: narrow-window did not restore DQ%0d tap=%0d expected=%0d",
                     idx,
                     dq_delay_flat[(idx * 9) +: 9],
                     expected_best_tap_single(idx[3:0]));
            error_count = error_count + 1;
        end
    end

    if (error_count == 0) begin
        $display("SIM PASS: RDC training supports window qualification and center verification");
    end
    else begin
        $display("SIM FAIL: error_count=%0d", error_count);
    end

    $finish;
end

endmodule
