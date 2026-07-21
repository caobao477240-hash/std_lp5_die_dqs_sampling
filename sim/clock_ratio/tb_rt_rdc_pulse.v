`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Module Name:     tb_rt_rdc_pulse
// Description:
//   Focused check for the runtime RDC entry of lpddr5_init:
//     1. run one fast init to reach P_INIT_IDLE;
//     2. pulse start_rdc for one cycle;
//     3. expect the RDC CS/CA pair (CAS rise=7'h2C then RDC rise=7'h50),
//        a WCK open window, and one six-cycle rx_dq_capture_en window
//        starting at read_capture_start_cnt inside the runtime slot;
//     4. repeat the pulse to prove the runtime slot re-arms;
//     5. prove start_mrw still works after a runtime RDC.
//   Compile with +define+LP5_SIM_FAST.
//////////////////////////////////////////////////////////////////////////////////

module tb_rt_rdc_pulse;

reg          clk;
reg          rst_n;
reg          init_en;
reg          start_mrw;
reg  [23:0]  mrw_cmd;
reg          start_rdc;
reg  [7:0]   read_capture_start_cnt;

wire         init_busy;
wire         init_done;
wire [2:0]   init_state;
wire         runtime_mr_busy;
wire         rdc_sample_en;
wire         rx_dq_capture_en;
wire [111:0] ascii_state;
wire [7:0]   die_message;
wire [10:0]  init_mr_cnt;
wire         wave_ck_a_run_en;
wire         wave_reset_n_a;
wire         wave_cs_a_0_rise;
wire         wave_cs_a_0_fall;
wire [6:0]   wave_ca_a_rise;
wire [6:0]   wave_ca_a_fall;
wire [1:0]   wave_wck_a_run_en;

integer      err_cnt;
integer      cs_pulse_cnt;
integer      cap_cycle_cnt;
integer      wck_on_during_cap;
reg  [6:0]   cs_ca_rise_first;
reg  [6:0]   cs_ca_rise_second;
integer      loop_idx;

lpddr5_init U_lpddr5_init (
    .clk                    (clk                    ),
    .rst_n                  (rst_n                  ),
    .init_en                (init_en                ),
    .start_mrw              (start_mrw              ),
    .mrw_cmd                (mrw_cmd                ),
    .start_rdc              (start_rdc              ),
    .read_capture_start_cnt (read_capture_start_cnt ),
    .dq_a_word_flat         (64'h0018001800180018   ),
    .dq_a_word_valid        (1'b0                   ),
    .init_busy              (init_busy              ),
    .init_done              (init_done              ),
    .init_state             (init_state             ),
    .runtime_mr_busy        (runtime_mr_busy        ),
    .rdc_sample_en          (rdc_sample_en          ),
    .rx_dq_capture_en       (rx_dq_capture_en       ),
    .ascii_state            (ascii_state            ),
    .die_message            (die_message            ),
    .init_mr_cnt            (init_mr_cnt            ),
    .wave_reset_n_a         (wave_reset_n_a         ),
    .wave_cs_a_0_rise       (wave_cs_a_0_rise       ),
    .wave_cs_a_0_fall       (wave_cs_a_0_fall       ),
    .wave_ca_a_rise         (wave_ca_a_rise         ),
    .wave_ca_a_fall         (wave_ca_a_fall         ),
    .wave_wck_a_run_en      (wave_wck_a_run_en      )
);

assign wave_ck_a_run_en = 1'b1;

always #2.5 clk = ~clk;

task run_one_rdc_slot;
    integer wait_idx;
    begin
        cs_pulse_cnt      = 0;
        cap_cycle_cnt     = 0;
        wck_on_during_cap = 0;
        cs_ca_rise_first  = 7'h00;
        cs_ca_rise_second = 7'h00;

        @(posedge clk);
        start_rdc <= 1'b1;
        @(posedge clk);
        start_rdc <= 1'b0;

        for (wait_idx = 0; wait_idx < 200; wait_idx = wait_idx + 1) begin
            @(posedge clk);
            if (wave_cs_a_0_fall) begin
                cs_pulse_cnt = cs_pulse_cnt + 1;
                if (cs_pulse_cnt == 1) begin
                    cs_ca_rise_first = wave_ca_a_rise;
                end
                if (cs_pulse_cnt == 2) begin
                    cs_ca_rise_second = wave_ca_a_rise;
                end
            end
            if (rx_dq_capture_en) begin
                cap_cycle_cnt = cap_cycle_cnt + 1;
                if (wave_wck_a_run_en == 2'b11) begin
                    wck_on_during_cap = wck_on_during_cap + 1;
                end
            end
        end

        if (cs_pulse_cnt != 2) begin
            err_cnt = err_cnt + 1;
            $display("FAIL: RDC CS pulse count = %0d, expect 2", cs_pulse_cnt);
        end
        if (cs_ca_rise_first != 7'h2C) begin
            err_cnt = err_cnt + 1;
            $display("FAIL: first CA rise = %02h, expect 2C (CAS)", cs_ca_rise_first);
        end
        if (cs_ca_rise_second != 7'h50) begin
            err_cnt = err_cnt + 1;
            $display("FAIL: second CA rise = %02h, expect 50 (RDC)", cs_ca_rise_second);
        end
        if (cap_cycle_cnt != 6) begin
            err_cnt = err_cnt + 1;
            $display("FAIL: capture_en cycles = %0d, expect 6", cap_cycle_cnt);
        end
        if (wck_on_during_cap != cap_cycle_cnt) begin
            err_cnt = err_cnt + 1;
            $display("FAIL: WCK not open through capture window (%0d/%0d)",
                     wck_on_during_cap, cap_cycle_cnt);
        end
        if (runtime_mr_busy) begin
            err_cnt = err_cnt + 1;
            $display("FAIL: runtime slot still busy after RDC window");
        end
    end
endtask

initial begin
    clk                    = 1'b0;
    rst_n                  = 1'b0;
    init_en                = 1'b0;
    start_mrw              = 1'b0;
    mrw_cmd                = 24'd0;
    start_rdc              = 1'b0;
    read_capture_start_cnt = 8'd18;
    err_cnt                = 0;

    repeat (10) @(posedge clk);
    rst_n = 1'b1;
    repeat (10) @(posedge clk);

    // one-cycle host init pulse, wait for fast init to finish
    init_en <= 1'b1;
    @(posedge clk);
    init_en <= 1'b0;
    wait (init_done == 1'b1);
    repeat (20) @(posedge clk);

    // two back-to-back runtime RDC slots prove the entry re-arms
    for (loop_idx = 0; loop_idx < 2; loop_idx = loop_idx + 1) begin
        run_one_rdc_slot;
    end

    // runtime MRW must still work after runtime RDC
    @(posedge clk);
    start_mrw <= 1'b1;
    mrw_cmd   <= 24'h00AA08;
    @(posedge clk);
    start_mrw <= 1'b0;
    repeat (5) @(posedge clk);
    if (!runtime_mr_busy) begin
        err_cnt = err_cnt + 1;
        $display("FAIL: MRW slot did not start after runtime RDC");
    end
    wait (runtime_mr_busy == 1'b0);

    if (err_cnt == 0) begin
        $display("SIM PASS: runtime RDC slot fires CAS+RDC, capture window, and re-arms");
    end
    else begin
        $display("SIM FAIL: %0d errors", err_cnt);
    end
    $finish;
end

initial begin
    #2_000_000;
    $display("SIM FAIL: timeout");
    $finish;
end

endmodule
