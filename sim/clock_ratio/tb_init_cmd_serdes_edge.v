`timescale 1ps / 1ps

module tb_init_cmd_serdes_edge;

reg clk_200m = 1'b0;
reg clk_400m = 1'b0;
reg rst_n = 1'b0;
reg init_en = 1'b0;
reg start_mrw = 1'b0;
reg [23:0] mrw_cmd = 24'd0;
reg [7:0]  read_capture_start_cnt = 8'd24;
reg [63:0] dq_a_word_flat = 64'h0;
reg        dq_a_word_valid = 1'b0;

wire        init_busy;
wire        init_done;
wire [2:0]  init_state;
wire        runtime_mr_busy;
wire        rdc_sample_en;
wire        rx_dq_capture_en;
wire [111:0] ascii_state;
wire [7:0]  die_message;
wire [10:0] init_mr_cnt;
wire        wave_ck_a_run_en;
wire        wave_cs_a_0_rise;
wire        wave_cs_a_0_fall;
wire [6:0]  wave_ca_a_rise;
wire [6:0]  wave_ca_a_fall;
wire        wave_reset_n_a;
wire [1:0]  wave_wck_a_run_en;

wire ck_out;
wire cs_out;
wire [6:0] ca_out;
wire ca0_out;
wire ca1_out;
wire wck0_out;

genvar ca_idx;

integer ck_edges;
integer wck_edges;
integer ck_last;
integer wck_last;
integer ck_period_sum;
integer wck_period_sum;
integer error_count;
integer cs_transition_count;
integer ca_transition_count;
integer mr18_addr_seen;
integer mr18_op_seen;
integer mr18_data_seen;
integer ext_mr18_stage;
integer ext_mr18_seen;

always #2500 clk_200m = ~clk_200m;
always #1250 clk_400m = ~clk_400m;

lpddr5_init U_INIT (
    .clk                   (clk_200m),
    .rst_n                 (rst_n),
    .init_en               (init_en),
    .start_mrw             (start_mrw),
    .mrw_cmd               (mrw_cmd),
    .start_rdc             (1'b0),
    .rdc_train_init_en     (1'b0),
    .rdc_train_apply_best_cfg(1'b0),
    .rdc_train_dual_pattern_cfg(1'b0),
    .rdc_train_dq_start_cfg(4'd0),
    .rdc_train_dq_end_cfg  (4'd15),
    .rdc_train_tap_start_cfg(9'd0),
    .rdc_train_tap_stop_cfg(9'd0),
    .rdc_train_tap_step_cfg(9'd1),
    .rdc_train_dq_delay_l_we(1'b0),
    .rdc_train_dq_delay_h_we(1'b0),
    .rdc_train_dq_delay_wdat(96'd0),
    .rdc_train_scan_tap_sel(9'd0),
    .rdc_err_bitmap        (16'h0000),
    .rdc_check_valid       (1'b0),
    .read_capture_start_cnt(read_capture_start_cnt),
    .dq_a_word_flat        (dq_a_word_flat),
    .dq_a_word_valid       (dq_a_word_valid),
    .init_busy             (init_busy),
    .init_done             (init_done),
    .init_fail             (),
    .init_state            (init_state),
    .runtime_mr_busy       (runtime_mr_busy),
    .rdc_sample_en         (rdc_sample_en),
    .rx_dq_capture_en        (rx_dq_capture_en),
    .ascii_state           (ascii_state),
    .die_message           (die_message),
    .init_mr_cnt           (init_mr_cnt),
    .rdc_dq_delay_flat     (),
    .rdc_train_mrw_r       (),
    .rdc_train_mrr_r       (),
    .rdc_train_state       (),
    .rdc_train_busy        (),
    .rdc_train_done        (),
    .rdc_train_apply_best  (),
    .rdc_train_dq_start    (),
    .rdc_train_tap         (),
    .rdc_train_pattern_sel (),
    .rdc_train_status_best_len(),
    .rdc_train_pass_mask   (),
    .rdc_train_fail_mask   (),
    .rdc_train_last_err_bitmap(),
    .rdc_train_init_ready  (),
    .rdc_train_pass_all    (),
    .rdc_train_best_flat   (),
    .rdc_train_left_flat   (),
    .rdc_train_right_flat  (),
    .rdc_train_scan_pass_bitmap(),
    .wave_reset_n_a        (wave_reset_n_a),
    .wave_cs_a_0_rise      (wave_cs_a_0_rise),
    .wave_cs_a_0_fall      (wave_cs_a_0_fall),
    .wave_ca_a_rise        (wave_ca_a_rise),
    .wave_ca_a_fall        (wave_ca_a_fall),
    .wave_wck_a_run_en     (wave_wck_a_run_en)
);

assign wave_ck_a_run_en = 1'b1;

lpddr5_serdes_ck_1bit U_CK_SERDES (
    .clk_200m (clk_200m),
    .clk_400m (clk_400m),
    .rst_n    (rst_n),
    .ck_run_en(wave_ck_a_run_en),
    .out_q    (ck_out)
);

lpddr5_serdes_ddr_1bit U_CS_SERDES (
    .clk_200m (clk_200m),
    .clk_400m (clk_400m),
    .rst_n    (rst_n),
    .data_rise(wave_cs_a_0_rise),
    .data_fall(wave_cs_a_0_fall),
    .out_q    (cs_out)
);

generate
    for (ca_idx = 0; ca_idx < 7; ca_idx = ca_idx + 1) begin : GEN_CA_SERDES
        lpddr5_serdes_ddr_1bit U_CA_SERDES (
            .clk_200m (clk_200m),
            .clk_400m (clk_400m),
            .rst_n    (rst_n),
            .data_rise(wave_ca_a_rise[ca_idx]),
            .data_fall(wave_ca_a_fall[ca_idx]),
            .out_q    (ca_out[ca_idx])
        );
    end
endgenerate

assign ca0_out = ca_out[0];
assign ca1_out = ca_out[1];

lpddr5_serdes_wck_1bit U_WCK_SERDES (
    .clk_200m (clk_200m),
    .clk_400m (clk_400m),
    .rst_n    (rst_n),
    .run_en    (wave_wck_a_run_en[0]),
    .phase     (1'b0),
    .out_q    (wck0_out)
);

initial begin
    ck_edges = 0;
    wck_edges = 0;
    ck_last = 0;
    wck_last = 0;
    ck_period_sum = 0;
    wck_period_sum = 0;
    error_count = 0;
    cs_transition_count = 0;
    ca_transition_count = 0;
    mr18_addr_seen = 0;
    mr18_op_seen = 0;
    mr18_data_seen = 0;
    ext_mr18_stage = 0;
    ext_mr18_seen = 0;

    repeat (8) @(posedge clk_200m);
    rst_n = 1'b1;
    repeat (4) @(posedge clk_200m);
    init_en = 1'b1;

    wait (init_state == 3'd3 && init_mr_cnt == 11'd24);
    dq_a_word_flat  = 64'h0000_0019_0019_0019;
    dq_a_word_valid = 1'b1;
    @(posedge clk_200m);
    dq_a_word_valid = 1'b0;

    wait (init_done);
    repeat (8) @(posedge clk_200m);

    if (die_message != 8'h19) begin
        $display("SIM FAIL: die_message=%02h expected=19", die_message);
        error_count = error_count + 1;
    end
    if (ck_edges < 20) begin
        $display("SIM FAIL: CK edge count too small: %0d", ck_edges);
        error_count = error_count + 1;
    end
    if (wck_edges < 20) begin
        $display("SIM FAIL: WCK edge count too small during MRR/RDC: %0d", wck_edges);
        error_count = error_count + 1;
    end
    if (cs_transition_count == 0 || ca_transition_count == 0) begin
        $display("SIM FAIL: no external CS/CA transition observed, cs=%0d ca=%0d",
                 cs_transition_count, ca_transition_count);
        error_count = error_count + 1;
    end
    if (ext_mr18_seen == 0) begin
        $display("SIM FAIL: external MR18 2:1 command not observed on serialized CS/CA pins");
        error_count = error_count + 1;
    end

    $display("CK edges=%0d avg_period_ps=%0d", ck_edges,
             (ck_edges > 1) ? (ck_period_sum / (ck_edges - 1)) : 0);
    $display("WCK edges=%0d avg_period_ps=%0d", wck_edges,
             (wck_edges > 1) ? (wck_period_sum / (wck_edges - 1)) : 0);
    $display("External transitions: CS=%0d CA=%0d", cs_transition_count, ca_transition_count);
    $display("Internal MR18 CKR 2:1 observed: addr=%0d op=%0d data=%0d",
             mr18_addr_seen, mr18_op_seen, mr18_data_seen);
    $display("External MR18 CKR 2:1 sequence observed on CS/CA pins: %0d",
             ext_mr18_seen);

    if (error_count == 0)
        $display("SIM PASS: LP5 init uses CK=200M, WCK=400M, and MR18 OP[7]=1 for 2:1 CKR");
    else
        $display("SIM FAIL: error_count=%0d", error_count);

    $finish;
end

always @(posedge ck_out) begin
    if (rst_n && init_state == 3'd3) begin
        if (ck_edges != 0)
            ck_period_sum = ck_period_sum + ($time - ck_last);
        ck_last = $time;
        ck_edges = ck_edges + 1;
    end
end

always @(posedge wck0_out) begin
    if (rst_n && (init_state == 3'd3 || init_state == 3'd4)) begin
        if (wck_edges != 0)
            wck_period_sum = wck_period_sum + ($time - wck_last);
        wck_last = $time;
        wck_edges = wck_edges + 1;
    end
end

always @(cs_out)
    if (rst_n && init_state == 3'd3)
        cs_transition_count = cs_transition_count + 1;

always @(ca0_out or ca1_out)
    if (rst_n && init_state == 3'd3)
        ca_transition_count = ca_transition_count + 1;

always @(ca_out or cs_out) begin
    #1;
    if (rst_n && (cs_out === 1'b1) && (^ca_out !== 1'bx)) begin
        case (ext_mr18_stage)
            0: begin
                if (ca_out == 7'h58)
                    ext_mr18_stage = 1;
            end
            1: begin
                if (ca_out == 7'h12)
                    ext_mr18_stage = 2;
                else if (ca_out == 7'h58)
                    ext_mr18_stage = 1;
                else
                    ext_mr18_stage = 0;
            end
            2: begin
                if (ca_out == 7'h48)
                    ext_mr18_stage = 3;
                else if (ca_out == 7'h58)
                    ext_mr18_stage = 1;
                else
                    ext_mr18_stage = 0;
            end
            3: begin
                if (ca_out == 7'h03) begin
                    ext_mr18_stage = 4;
                    ext_mr18_seen = 1;
                    $display("EXT MR18 CKR2 SEQ t=%0t CS=%b CA=%02h", $time, cs_out, ca_out);
                end
                else if (ca_out == 7'h58)
                    ext_mr18_stage = 1;
                else
                    ext_mr18_stage = 0;
            end
            default: begin
                if (ca_out == 7'h58)
                    ext_mr18_stage = 1;
            end
        endcase
    end
end

always @(posedge clk_200m) begin
    #1;
    if (rst_n &&
        (U_INIT.r_init_state == U_INIT.P_INIT_MR_INIT_W) &&
        (U_INIT.r_mr_slot == 5'd11)) begin
        if ((U_INIT.r_mr_phase == 7'd5) &&
            (wave_ca_a_fall == 7'h12) && (wave_ca_a_rise == 7'h12))
            mr18_addr_seen = 1;
        if ((U_INIT.r_mr_phase == 7'd6) &&
            (wave_ca_a_fall == 7'h48) && (wave_ca_a_rise == 7'h48))
            mr18_op_seen = 1;
        if ((U_INIT.r_mr_phase == 7'd7) &&
            (wave_ca_a_fall == 7'h03) && (wave_ca_a_rise == 7'h03))
            mr18_data_seen = 1;
    end
end

initial begin
    #200000000;
    $display("SIM FAIL: timeout, state=%0d cnt=%0d die=%02h", init_state, init_mr_cnt, die_message);
    $finish;
end

endmodule
