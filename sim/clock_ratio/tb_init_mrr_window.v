`timescale 1ns / 1ps

module tb_init_mrr_window;

reg clk = 1'b0;
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
wire        wave_reset_n_a;
wire        wave_cs_a_0_rise;
wire        wave_cs_a_0_fall;
wire [6:0]  wave_ca_a_rise;
wire [6:0]  wave_ca_a_fall;
wire [1:0]  wave_wck_a_run_en;

integer error_count;

always #2.5 clk = ~clk;

lpddr5_init U_INIT (
    .clk                   (clk),
    .rst_n                 (rst_n),
    .init_en               (init_en),
    .start_mrw             (start_mrw),
    .mrw_cmd               (mrw_cmd),
    .read_capture_start_cnt(read_capture_start_cnt),
    .dq_a_word_flat        (dq_a_word_flat),
    .dq_a_word_valid       (dq_a_word_valid),
    .init_busy             (init_busy),
    .init_done             (init_done),
    .init_state            (init_state),
    .runtime_mr_busy       (runtime_mr_busy),
    .rdc_sample_en         (rdc_sample_en),
    .rx_dq_capture_en        (rx_dq_capture_en),
    .ascii_state           (ascii_state),
    .die_message           (die_message),
    .init_mr_cnt           (init_mr_cnt),
    .wave_reset_n_a        (wave_reset_n_a),
    .wave_cs_a_0_rise      (wave_cs_a_0_rise),
    .wave_cs_a_0_fall      (wave_cs_a_0_fall),
    .wave_ca_a_rise        (wave_ca_a_rise),
    .wave_ca_a_fall        (wave_ca_a_fall),
    .wave_wck_a_run_en     (wave_wck_a_run_en)
);

assign wave_ck_a_run_en = 1'b1;

initial begin
    error_count = 0;

    repeat (8) @(posedge clk);
    rst_n = 1'b1;
    repeat (4) @(posedge clk);
    init_en = 1'b1;

    wait (init_state == 3'd3 && init_mr_cnt == 11'd24);
    if (!rx_dq_capture_en) begin
        $display("SIM FAIL: rx_dq_capture_en is not active at capture start cnt=24");
        error_count = error_count + 1;
    end
    dq_a_word_flat  = 64'h0000_0019_0019_0019;
    dq_a_word_valid = 1'b1;
    @(posedge clk);
    dq_a_word_valid = 1'b0;

    repeat (2) @(posedge clk);
    if (die_message != 8'h19) begin
        $display("SIM FAIL: die_message=%02h, expected 19", die_message);
        error_count = error_count + 1;
    end

    wait (init_state == 3'd3 && init_mr_cnt == 11'd29);
    if (!rx_dq_capture_en) begin
        $display("SIM FAIL: rx_dq_capture_en dropped before cnt=29");
        error_count = error_count + 1;
    end
    wait (init_state == 3'd3 && init_mr_cnt == 11'd30);
    #1;
    if (init_state == 3'd3 && rx_dq_capture_en) begin
        $display("SIM FAIL: rx_dq_capture_en still active at cnt=30");
        error_count = error_count + 1;
    end

    wait (init_done);

    if (error_count == 0)
        $display("SIM PASS: direct MRR window start=24 captures MR8 and arms DQS 24..29");
    else
        $display("SIM FAIL: error_count=%0d", error_count);

    $finish;
end

initial begin
    #200000;
    $display("SIM FAIL: timeout, state=%0d cnt=%0d die=%02h dqs=%0b", init_state, init_mr_cnt, die_message, rx_dq_capture_en);
    $finish;
end

endmodule
