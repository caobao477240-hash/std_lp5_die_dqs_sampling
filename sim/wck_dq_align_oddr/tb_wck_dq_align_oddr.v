`timescale 1ps/1ps

module tb_wck_dq_align_oddr;

localparam integer START_CHECK_PS = 30000;

integer    wck_phase_ps = 625;
reg        clk_400m     = 1'b0;
reg        clk_400m_wck = 1'b0;
reg        clk_200m     = 1'b0;
reg        rst_n        = 1'b0;
reg [15:0] beat0        = 16'h0000;
reg [15:0] beat1        = 16'h0001;
reg [15:0] beat2        = 16'h0002;
reg [15:0] beat3        = 16'h0003;
reg [4:0]  word_base    = 5'd0;
reg        wck_run_en   = 1'b1;
reg        wck_phase    = 1'b0;

wire       dq0_q;
wire       wck_q;

time last_dq_edge_ps;
integer dq_edges;
integer wck_edges;
integer same_edge;
integer center_edge;
integer target_edge;
time    min_delta_ps;
time    max_delta_ps;

always #1250 clk_400m = ~clk_400m;
always #2500 clk_200m = ~clk_200m;

initial begin
    if ($value$plusargs("WCK_PHASE_PS=%d", wck_phase_ps))
        $display("CONFIG WCK_PHASE_PS=%0d", wck_phase_ps);
    else
        $display("CONFIG WCK_PHASE_PS default=%0d", wck_phase_ps);
    #(wck_phase_ps);
    forever #1250 clk_400m_wck = ~clk_400m_wck;
end

initial begin
    last_dq_edge_ps = 0;
    dq_edges        = 0;
    wck_edges       = 0;
    same_edge       = 0;
    center_edge     = 0;
    target_edge     = 0;
    min_delta_ps    = 999999;
    max_delta_ps    = 0;

    repeat (6) @(posedge clk_200m);
    @(negedge clk_200m);
    rst_n = 1'b1;

    repeat (28) @(negedge clk_200m);
    $display("SUMMARY dq_edges=%0d", dq_edges);
    $display("SUMMARY oddr_wck_edges=%0d same_edge=%0d center_625ps=%0d target_phase_edges=%0d min_delta_ps=%0t max_delta_ps=%0t",
             wck_edges, same_edge, center_edge, target_edge, min_delta_ps, max_delta_ps);
    if (same_edge >= 8 && center_edge == 0)
        $display("RESULT ODDR_WCK: EDGE_ALIGNED_TO_DQ_TRANSITIONS");
    else if (center_edge >= 8)
        $display("RESULT ODDR_WCK: CENTER_ALIGNED_625PS_FROM_DQ_TRANSITIONS");
    else
        $display("RESULT ODDR_WCK: INCONCLUSIVE");
    $finish;
end

always @(negedge clk_200m) begin
    if (!rst_n) begin
        word_base <= 5'd0;
        beat0     <= 16'h0000;
        beat1     <= 16'h0001;
        beat2     <= 16'h0002;
        beat3     <= 16'h0003;
    end
    else begin
        beat0     <= {11'h000, word_base};
        beat1     <= {11'h000, word_base + 5'd1};
        beat2     <= {11'h000, word_base + 5'd2};
        beat3     <= {11'h000, word_base + 5'd3};
        word_base <= word_base + 5'd4;
    end
end

OSERDESE3 #(
    .DATA_WIDTH(4),
    .INIT(1'b0),
    .IS_CLKDIV_INVERTED(1'b0),
    .IS_CLK_INVERTED(1'b0),
    .IS_RST_INVERTED(1'b0),
    .SIM_DEVICE("ULTRASCALE")
) u_dq0 (
    .OQ     (dq0_q),
    .T_OUT  (),
    .CLK    (clk_400m),
    .CLKDIV (clk_200m),
    .D      ({4'b0000, beat3[0], beat2[0], beat1[0], beat0[0]}),
    .RST    (~rst_n),
    .T      (1'b0)
);

lpddr5_serdes_wck_1bit u_wck (
    .clk_200m (clk_200m),
    .clk_400m (clk_400m_wck),
    .rst_n    (rst_n),
    .run_en   (wck_run_en),
    .phase    (wck_phase ),
    .out_q    (wck_q)
);

always @(dq0_q) begin
    if (rst_n && ($time > START_CHECK_PS) && (dq0_q !== 1'bx)) begin
        last_dq_edge_ps = $time;
        dq_edges = dq_edges + 1;
        $display("DQ0_EDGE t=%0t dq0=%b beats=%h_%h_%h_%h",
                 $time, dq0_q, beat3[3:0], beat2[3:0], beat1[3:0], beat0[3:0]);
    end
end

always @(wck_q) begin
    if (rst_n && ($time > START_CHECK_PS) && (wck_q !== 1'bx)) begin
        wck_edges = wck_edges + 1;
        if (($time - last_dq_edge_ps) == 0)
            same_edge = same_edge + 1;
        if (($time - last_dq_edge_ps) == 625)
            center_edge = center_edge + 1;
        if (($time - last_dq_edge_ps) >= (wck_phase_ps - 25) &&
            ($time - last_dq_edge_ps) <= (wck_phase_ps + 25))
            target_edge = target_edge + 1;
        if (($time - last_dq_edge_ps) < min_delta_ps)
            min_delta_ps = $time - last_dq_edge_ps;
        if (($time - last_dq_edge_ps) > max_delta_ps)
            max_delta_ps = $time - last_dq_edge_ps;
        $display("WCK_EDGE t=%0t wck=%b dq0=%b delta_from_dq_edge_ps=%0t",
                 $time, wck_q, dq0_q, $time - last_dq_edge_ps);
    end
end

endmodule
