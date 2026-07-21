`timescale 1ps/1ps

module tb_ck_ca_align;

localparam integer START_CHECK_PS = 30000;
localparam integer RUN_CYCLES     = 32;

reg clk_200m = 1'b0;
reg clk_400m = 1'b0;
reg rst_n    = 1'b0;

reg wave_ck_fall = 1'b1;
reg wave_ck_rise = 1'b0;
reg ca_rise      = 1'b0;
reg ca_fall      = 1'b0;

wire ck_current_q;
wire ck_0011_q;
wire ck_0110_q;
wire ck_1001_q;
wire ca_q;

integer ck_current_edges;
integer ck_0011_edges;
integer ck_0110_edges;
integer ck_1001_edges;
integer ca_edges;
integer ca_at_current_ck_edge;
integer ca_center_after_current_ck_edge;
integer ca_at_0011_ck_edge;
integer ca_center_after_0011_ck_edge;
integer ca_at_0110_ck_edge;
integer ca_center_after_0110_ck_edge;
integer ca_at_1001_ck_edge;
integer ca_center_after_1001_ck_edge;
integer ck_current_period_sum;
integer ck_0011_period_sum;
integer ck_0110_period_sum;
integer ck_1001_period_sum;
time    last_ck_current_edge_ps;
time    last_ck_0011_edge_ps;
time    last_ck_0110_edge_ps;
time    last_ck_1001_edge_ps;
time    last_ca_edge_ps;
time    ca_delta_from_current_ck_ps;
time    ca_delta_from_0011_ck_ps;
time    ca_delta_from_0110_ck_ps;
time    ca_delta_from_1001_ck_ps;

always #1250 clk_400m = ~clk_400m;
always #2500 clk_200m = ~clk_200m;

initial begin
    ck_current_edges = 0;
    ck_0011_edges    = 0;
    ck_0110_edges    = 0;
    ck_1001_edges    = 0;
    ca_edges         = 0;
    ca_at_current_ck_edge = 0;
    ca_center_after_current_ck_edge = 0;
    ca_at_0011_ck_edge = 0;
    ca_center_after_0011_ck_edge = 0;
    ca_at_0110_ck_edge = 0;
    ca_center_after_0110_ck_edge = 0;
    ca_at_1001_ck_edge = 0;
    ca_center_after_1001_ck_edge = 0;
    ck_current_period_sum = 0;
    ck_0011_period_sum = 0;
    ck_0110_period_sum = 0;
    ck_1001_period_sum = 0;
    last_ck_current_edge_ps = 0;
    last_ck_0011_edge_ps = 0;
    last_ck_0110_edge_ps = 0;
    last_ck_1001_edge_ps = 0;
    last_ca_edge_ps = 0;

    repeat (6) @(posedge clk_200m);
    @(negedge clk_200m);
    rst_n = 1'b1;

    repeat (RUN_CYCLES) @(negedge clk_200m);
    $display("SUMMARY ck_current_edges=%0d avg_edge_delta_ps=%0d",
             ck_current_edges,
             (ck_current_edges > 1) ? (ck_current_period_sum / (ck_current_edges - 1)) : 0);
    $display("SUMMARY ck_0011_edges=%0d avg_edge_delta_ps=%0d",
             ck_0011_edges,
             (ck_0011_edges > 1) ? (ck_0011_period_sum / (ck_0011_edges - 1)) : 0);
    $display("SUMMARY ck_0110_edges=%0d avg_edge_delta_ps=%0d",
             ck_0110_edges,
             (ck_0110_edges > 1) ? (ck_0110_period_sum / (ck_0110_edges - 1)) : 0);
    $display("SUMMARY ck_1001_edges=%0d avg_edge_delta_ps=%0d",
             ck_1001_edges,
             (ck_1001_edges > 1) ? (ck_1001_period_sum / (ck_1001_edges - 1)) : 0);
    $display("SUMMARY ca_edges=%0d", ca_edges);
    $display("SUMMARY ca_vs_current100 at_edge=%0d center_2500ps_after_edge=%0d",
             ca_at_current_ck_edge, ca_center_after_current_ck_edge);
    $display("SUMMARY ca_vs_0011 at_edge=%0d center_1250ps_after_edge=%0d",
             ca_at_0011_ck_edge, ca_center_after_0011_ck_edge);
    $display("SUMMARY ca_vs_0110 at_edge=%0d center_1250ps_after_edge=%0d",
             ca_at_0110_ck_edge, ca_center_after_0110_ck_edge);
    $display("SUMMARY ca_vs_1001 at_edge=%0d center_1250ps_after_edge=%0d",
             ca_at_1001_ck_edge, ca_center_after_1001_ck_edge);

    if ((ck_current_edges > 1) &&
        ((ck_current_period_sum / (ck_current_edges - 1)) >= 4500) &&
        ((ck_current_period_sum / (ck_current_edges - 1)) <= 5500))
        $display("RESULT CK_CURRENT_4TO1: CK_100M_HALF_PERIOD_5000PS");
    else
        $display("RESULT CK_CURRENT_4TO1: UNEXPECTED_CK_PERIOD");

    if (ca_center_after_current_ck_edge >= (ca_edges - 2))
        $display("RESULT CA_VS_CURRENT100: CENTER_BETWEEN_CK_EDGES");
    else if (ca_at_current_ck_edge > 0)
        $display("RESULT CA_VS_CURRENT100: EDGE_ALIGNED_TO_CK");
    else
        $display("RESULT CA_VS_CURRENT100: INCONCLUSIVE");

    if (ca_at_0011_ck_edge > 0)
        $display("RESULT CA_VS_0011: EDGE_ALIGNED_TO_CK");
    else if (ca_center_after_0011_ck_edge >= 2)
        $display("RESULT CA_VS_0011: CENTER_BETWEEN_CK_EDGES");
    else
        $display("RESULT CA_VS_0011: INCONCLUSIVE");

    if (ca_at_0110_ck_edge > 0)
        $display("RESULT CA_VS_0110: EDGE_ALIGNED_TO_CK");
    else if (ca_center_after_0110_ck_edge >= 2)
        $display("RESULT CA_VS_0110: CENTER_BETWEEN_CK_EDGES");
    else
        $display("RESULT CA_VS_0110: INCONCLUSIVE");

    if (ca_at_1001_ck_edge > 0)
        $display("RESULT CA_VS_1001: EDGE_ALIGNED_TO_CK");
    else if (ca_center_after_1001_ck_edge >= 2)
        $display("RESULT CA_VS_1001: CENTER_BETWEEN_CK_EDGES");
    else
        $display("RESULT CA_VS_1001: INCONCLUSIVE");

    $finish;
end

always @(posedge clk_200m or negedge rst_n) begin
    if (!rst_n) begin
        wave_ck_fall <= 1'b1;
        wave_ck_rise <= 1'b0;
    end
    else begin
        wave_ck_fall <= ~wave_ck_fall;
        wave_ck_rise <= ~wave_ck_rise;
    end
end

always @(posedge clk_200m or negedge rst_n) begin
    if (!rst_n) begin
        ca_rise <= 1'b0;
        ca_fall <= 1'b0;
    end
    else begin
        ca_rise <= ~ca_rise;
        ca_fall <= ~ca_fall;
    end
end

// Historical CK-data path retained only for phase comparison in this test.
lpddr5_serdes_ddr_1bit u_ck_current (
    .clk_200m (clk_200m),
    .clk_400m (clk_400m),
    .rst_n    (rst_n),
    .data_rise(wave_ck_rise),
    .data_fall(wave_ck_fall),
    .out_q    (ck_current_q)
);

// Candidate fixed CK paths. D0 is launched first in the existing project notes.
oserdes_pattern_1bit #(.PATTERN(4'b1100)) u_ck_0011 (
    .clk_200m (clk_200m),
    .clk_400m (clk_400m),
    .rst_n    (rst_n),
    .out_q    (ck_0011_q)
);

oserdes_pattern_1bit #(.PATTERN(4'b0110)) u_ck_0110 (
    .clk_200m (clk_200m),
    .clk_400m (clk_400m),
    .rst_n    (rst_n),
    .out_q    (ck_0110_q)
);

oserdes_pattern_1bit #(.PATTERN(4'b1001)) u_ck_1001 (
    .clk_200m (clk_200m),
    .clk_400m (clk_400m),
    .rst_n    (rst_n),
    .out_q    (ck_1001_q)
);

// Current CA serializer path. When CA data changes once per 200 MHz cycle,
// the serializer duplicates each half-cycle value for two 400 MHz DDR UIs.
lpddr5_serdes_ddr_1bit u_ca (
    .clk_200m (clk_200m),
    .clk_400m (clk_400m),
    .rst_n    (rst_n),
    .data_rise(ca_rise),
    .data_fall(ca_fall),
    .out_q    (ca_q)
);

always @(ck_current_q) begin
    if (rst_n && ($time > START_CHECK_PS) && (ck_current_q !== 1'bx)) begin
        if (last_ck_current_edge_ps != 0)
            ck_current_period_sum = ck_current_period_sum + ($time - last_ck_current_edge_ps);
        last_ck_current_edge_ps = $time;
        ck_current_edges = ck_current_edges + 1;
        $display("CK_CURRENT_EDGE t=%0t ck=%b wave_ck_fall/rise=%b/%b ca=%b",
                 $time, ck_current_q, wave_ck_fall, wave_ck_rise, ca_q);
    end
end

always @(ck_0011_q) begin
    if (rst_n && ($time > START_CHECK_PS) && (ck_0011_q !== 1'bx)) begin
        if (last_ck_0011_edge_ps != 0)
            ck_0011_period_sum = ck_0011_period_sum + ($time - last_ck_0011_edge_ps);
        last_ck_0011_edge_ps = $time;
        ck_0011_edges = ck_0011_edges + 1;
        $display("CK_0011_EDGE    t=%0t ck=%b ca=%b delta_ca_edge_ps=%0t",
                 $time, ck_0011_q, ca_q, $time - last_ca_edge_ps);
    end
end

always @(ck_0110_q) begin
    if (rst_n && ($time > START_CHECK_PS) && (ck_0110_q !== 1'bx)) begin
        if (last_ck_0110_edge_ps != 0)
            ck_0110_period_sum = ck_0110_period_sum + ($time - last_ck_0110_edge_ps);
        last_ck_0110_edge_ps = $time;
        ck_0110_edges = ck_0110_edges + 1;
        $display("CK_0110_EDGE    t=%0t ck=%b ca=%b delta_ca_edge_ps=%0t",
                 $time, ck_0110_q, ca_q, $time - last_ca_edge_ps);
    end
end

always @(ck_1001_q) begin
    if (rst_n && ($time > START_CHECK_PS) && (ck_1001_q !== 1'bx)) begin
        if (last_ck_1001_edge_ps != 0)
            ck_1001_period_sum = ck_1001_period_sum + ($time - last_ck_1001_edge_ps);
        last_ck_1001_edge_ps = $time;
        ck_1001_edges = ck_1001_edges + 1;
        $display("CK_1001_EDGE    t=%0t ck=%b ca=%b delta_ca_edge_ps=%0t",
                 $time, ck_1001_q, ca_q, $time - last_ca_edge_ps);
    end
end

always @(ca_q) begin
    if (rst_n && ($time > START_CHECK_PS) && (ca_q !== 1'bx)) begin
        ca_delta_from_current_ck_ps = $time - last_ck_current_edge_ps;
        ca_delta_from_0011_ck_ps = $time - last_ck_0011_edge_ps;
        ca_delta_from_0110_ck_ps = $time - last_ck_0110_edge_ps;
        ca_delta_from_1001_ck_ps = $time - last_ck_1001_edge_ps;
        last_ca_edge_ps = $time;
        ca_edges = ca_edges + 1;
        if (ca_delta_from_current_ck_ps == 0)
            ca_at_current_ck_edge = ca_at_current_ck_edge + 1;
        if (ca_delta_from_current_ck_ps >= 2450 && ca_delta_from_current_ck_ps <= 2550)
            ca_center_after_current_ck_edge = ca_center_after_current_ck_edge + 1;
        if (ca_delta_from_0011_ck_ps == 0)
            ca_at_0011_ck_edge = ca_at_0011_ck_edge + 1;
        if (ca_delta_from_0011_ck_ps >= 1200 && ca_delta_from_0011_ck_ps <= 1300)
            ca_center_after_0011_ck_edge = ca_center_after_0011_ck_edge + 1;
        if (ca_delta_from_0110_ck_ps == 0)
            ca_at_0110_ck_edge = ca_at_0110_ck_edge + 1;
        if (ca_delta_from_0110_ck_ps >= 1200 && ca_delta_from_0110_ck_ps <= 1300)
            ca_center_after_0110_ck_edge = ca_center_after_0110_ck_edge + 1;
        if (ca_delta_from_1001_ck_ps == 0)
            ca_at_1001_ck_edge = ca_at_1001_ck_edge + 1;
        if (ca_delta_from_1001_ck_ps >= 1200 && ca_delta_from_1001_ck_ps <= 1300)
            ca_center_after_1001_ck_edge = ca_center_after_1001_ck_edge + 1;
        $display("CA_EDGE         t=%0t ca=%b dcur=%0t d0011=%0t d0110=%0t d1001=%0t",
                 $time, ca_q,
                 ca_delta_from_current_ck_ps,
                 ca_delta_from_0011_ck_ps,
                 ca_delta_from_0110_ck_ps,
                 ca_delta_from_1001_ck_ps);
    end
end

endmodule

module oserdes_pattern_1bit #(
    parameter [3:0] PATTERN = 4'b1100
) (
    input  clk_200m,
    input  clk_400m,
    input  rst_n,
    output out_q
);

OSERDESE3 #(
    .DATA_WIDTH(4),
    .INIT(1'b0),
    .IS_CLKDIV_INVERTED(1'b0),
    .IS_CLK_INVERTED(1'b0),
    .IS_RST_INVERTED(1'b0),
    .SIM_DEVICE("ULTRASCALE")
) u_oserdes (
    .OQ     (out_q),
    .T_OUT  (),
    .CLK    (clk_400m),
    .CLKDIV (clk_200m),
    .D      ({4'b0000, PATTERN}),
    .RST    (~rst_n),
    .T      (1'b0)
);

endmodule
