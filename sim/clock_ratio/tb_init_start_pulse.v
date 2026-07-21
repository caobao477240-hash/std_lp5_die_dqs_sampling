`timescale 1ns / 1ps

module tb_init_start_pulse;

reg         clk = 1'b0;
reg         rst_n = 1'b0;
reg         init_en = 1'b0;
reg         start_mrw = 1'b0;
reg [23:0]  mrw_cmd = 24'd0;
reg [7:0]   read_capture_start_cnt = 8'd16;
reg [63:0]  dq_a_word_flat = 64'd0;
reg         dq_a_word_valid = 1'b0;

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

integer     timeout_cnt;

always #2.5 clk = ~clk;

lpddr5_init u_lpddr5_init (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .init_en                (init_en),
    .start_mrw              (start_mrw),
    .mrw_cmd                (mrw_cmd),
    .read_capture_start_cnt (read_capture_start_cnt),
    .dq_a_word_flat         (dq_a_word_flat),
    .dq_a_word_valid        (dq_a_word_valid),
    .init_busy              (init_busy),
    .init_done              (init_done),
    .init_state             (init_state),
    .runtime_mr_busy        (runtime_mr_busy),
    .rdc_sample_en          (rdc_sample_en),
    .rx_dq_capture_en         (rx_dq_capture_en),
    .ascii_state            (ascii_state),
    .die_message            (die_message),
    .init_mr_cnt            (init_mr_cnt),
    .wave_reset_n_a         (wave_reset_n_a),
    .wave_cs_a_0_rise       (wave_cs_a_0_rise),
    .wave_cs_a_0_fall       (wave_cs_a_0_fall),
    .wave_ca_a_rise         (wave_ca_a_rise),
    .wave_ca_a_fall         (wave_ca_a_fall),
    .wave_wck_a_run_en      (wave_wck_a_run_en)
);

assign wave_ck_a_run_en = 1'b1;

task send_init_pulse;
    begin
        @(posedge clk);
        init_en <= 1'b1;
        @(posedge clk);
        init_en <= 1'b0;
    end
endtask

task wait_init_done;
    begin
        timeout_cnt = 0;
        while (!init_done && (timeout_cnt < 1200)) begin
            @(posedge clk);
            timeout_cnt = timeout_cnt + 1;
        end

        if (!init_done) begin
            $display("SIM FAIL: init_done timeout, state=%0d busy=%0d", init_state, init_busy);
            $finish;
        end
    end
endtask

initial begin
    repeat (4) begin
        @(posedge clk);
    end
    rst_n <= 1'b1;

    send_init_pulse();
    wait_init_done();

    send_init_pulse();

    timeout_cnt = 0;
    while (init_done && (timeout_cnt < 20)) begin
        @(posedge clk);
        timeout_cnt = timeout_cnt + 1;
    end

    if (init_done) begin
        $display("SIM FAIL: second init pulse did not clear init_done");
        $finish;
    end

    wait_init_done();

    $display("SIM PASS: one-cycle init_en pulse completes init twice");
    $finish;
end

endmodule
