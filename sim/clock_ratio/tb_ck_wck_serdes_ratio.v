`timescale 1ps / 1ps

module tb_ck_wck_serdes_ratio;

reg clk_200m = 1'b0;
reg clk_400m = 1'b0;
reg rst_n    = 1'b0;

reg cmd_fall   = 1'b1;
reg cmd_rise   = 1'b0;
reg ck_run_en  = 1'b1;
reg wck_run_en = 1'b1;
reg wck_phase  = 1'b0;

wire ck_out;
wire wck_out;
wire ca_out;

integer ck_rise_count;
integer wck_rise_count;
integer ck_last_rise;
integer wck_last_rise;
integer ck_period_sum;
integer wck_period_sum;
integer ca_checked;
integer error_count;
integer ck_stop_snapshot;

real ck_avg_period;
real wck_avg_period;

always #2500 clk_200m = ~clk_200m;  // 200 MHz
always #1250 clk_400m = ~clk_400m;  // 400 MHz

lpddr5_serdes_ck_1bit U_CK (
    .clk_200m (clk_200m),
    .clk_400m (clk_400m),
    .rst_n    (rst_n   ),
    .ck_run_en(ck_run_en),
    .out_q    (ck_out  )
);

lpddr5_serdes_wck_1bit U_WCK (
    .clk_200m (clk_200m),
    .clk_400m (clk_400m),
    .rst_n    (rst_n   ),
    .run_en    (wck_run_en),
    .phase     (wck_phase ),
    .out_q    (wck_out )
);

lpddr5_serdes_ddr_1bit U_CA (
    .clk_200m (clk_200m),
    .clk_400m (clk_400m),
    .rst_n    (rst_n   ),
    .data_rise(cmd_rise),
    .data_fall(cmd_fall),
    .out_q    (ca_out  )
);

initial begin
    ck_rise_count  = 0;
    wck_rise_count = 0;
    ck_last_rise   = 0;
    wck_last_rise  = 0;
    ck_period_sum  = 0;
    wck_period_sum = 0;
    ca_checked     = 0;
    error_count    = 0;
    ck_stop_snapshot = 0;

    repeat (8) @(posedge clk_200m);
    rst_n = 1'b1;

    // Flip the DDR command inputs once so CA stretching can be inspected.
    repeat (20) @(posedge clk_200m);
    cmd_fall = 1'b0;
    cmd_rise = 1'b1;
    wck_phase = 1'b1;

    repeat (80) @(posedge clk_200m);

    if (ck_rise_count < 8) begin
        $display("SIM FAIL: CK did not toggle enough, ck_rise_count=%0d", ck_rise_count);
        error_count = error_count + 1;
    end
    if (wck_rise_count < 16) begin
        $display("SIM FAIL: WCK did not toggle enough, wck_rise_count=%0d", wck_rise_count);
        error_count = error_count + 1;
    end

    if (ck_rise_count > 1)
        ck_avg_period = ck_period_sum * 1.0 / (ck_rise_count - 1);
    else
        ck_avg_period = 0.0;

    if (wck_rise_count > 1)
        wck_avg_period = wck_period_sum * 1.0 / (wck_rise_count - 1);
    else
        wck_avg_period = 0.0;

    $display("CK  rise_count=%0d avg_period_ps=%0.1f target=5000.0", ck_rise_count, ck_avg_period);
    $display("WCK rise_count=%0d avg_period_ps=%0.1f target=2500.0", wck_rise_count, wck_avg_period);

    if ((ck_avg_period < 4900.0) || (ck_avg_period > 5100.0)) begin
        $display("SIM FAIL: CK period is not 200 MHz");
        error_count = error_count + 1;
    end
    if ((wck_avg_period < 2400.0) || (wck_avg_period > 2600.0)) begin
        $display("SIM FAIL: WCK period is not 400 MHz");
        error_count = error_count + 1;
    end

    // Stop CK, wait past the OSERDES pipeline, and verify that it stays low.
    @(negedge clk_200m);
    ck_run_en = 1'b0;
    repeat (6) @(posedge clk_200m);
    ck_stop_snapshot = ck_rise_count;
    repeat (8) @(posedge clk_200m);

    if (ck_out !== 1'b0) begin
        $display("SIM FAIL: CK is not low while ck_run_en=0");
        error_count = error_count + 1;
    end
    if (ck_rise_count != ck_stop_snapshot) begin
        $display("SIM FAIL: CK toggled while stopped");
        error_count = error_count + 1;
    end

    // Restart CK and verify that the fixed 200 MHz pattern resumes.
    @(negedge clk_200m);
    ck_run_en = 1'b1;
    repeat (8) @(posedge clk_200m);

    if (ck_rise_count <= ck_stop_snapshot) begin
        $display("SIM FAIL: CK did not restart");
        error_count = error_count + 1;
    end

    if (error_count == 0)
        $display("SIM PASS: CK run/stop/restart and WCK:CK=2:1");
    else
        $display("SIM FAIL: error_count=%0d", error_count);

    $finish;
end

always @(posedge ck_out) begin
    if (rst_n && ($time > 60000)) begin
        if (ck_rise_count != 0)
            ck_period_sum = ck_period_sum + ($time - ck_last_rise);
        ck_last_rise  = $time;
        ck_rise_count = ck_rise_count + 1;
    end
end

always @(posedge wck_out) begin
    if (rst_n && ($time > 60000)) begin
        if (wck_rise_count != 0)
            wck_period_sum = wck_period_sum + ($time - wck_last_rise);
        wck_last_rise  = $time;
        wck_rise_count = wck_rise_count + 1;
    end
end

endmodule
