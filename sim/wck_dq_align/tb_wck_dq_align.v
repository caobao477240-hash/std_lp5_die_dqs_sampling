`timescale 1ps/1ps

module tb_wck_dq_align;

localparam integer START_CHECK_PS = 30000;

reg        clk_400m = 1'b0;
reg        clk_400m_wck90 = 1'b0;
reg        clk_400m_wck270 = 1'b0;
reg        clk_200m = 1'b0;
reg        rst_n    = 1'b0;
reg  [3:0] beat0    = 4'h0;
reg  [3:0] beat1    = 4'h1;
reg  [3:0] beat2    = 4'h2;
reg  [3:0] beat3    = 4'h3;
reg  [4:0] word_base = 5'd0;

wire       wck_norm_q;
wire       wck_inv_q;
wire       wck_90_q;
wire       wck_270_q;
wire [3:0] dq_q;

time last_dq0_edge_ps;
integer dq0_edges;
integer wck_norm_edges;
integer wck_inv_edges;
integer wck_90_edges;
integer wck_270_edges;
integer norm_same_edge;
integer inv_same_edge;
integer wck90_same_edge;
integer wck270_same_edge;
integer norm_center_edge;
integer inv_center_edge;
integer wck90_center_edge;
integer wck270_center_edge;

always #1250 clk_400m = ~clk_400m;
initial begin
    #625;
    forever #1250 clk_400m_wck90 = ~clk_400m_wck90;
end
initial begin
    #1875;
    forever #1250 clk_400m_wck270 = ~clk_400m_wck270;
end
always #2500 clk_200m = ~clk_200m;

initial begin
    last_dq0_edge_ps = 0;
    dq0_edges        = 0;
    wck_norm_edges   = 0;
    wck_inv_edges    = 0;
    wck_90_edges     = 0;
    wck_270_edges    = 0;
    norm_same_edge   = 0;
    inv_same_edge    = 0;
    wck90_same_edge  = 0;
    wck270_same_edge = 0;
    norm_center_edge = 0;
    inv_center_edge  = 0;
    wck90_center_edge = 0;
    wck270_center_edge = 0;

    repeat (6) @(posedge clk_200m);
    @(negedge clk_200m);
    rst_n = 1'b1;

    repeat (28) @(negedge clk_200m);
    $display("SUMMARY dq0_edges=%0d", dq0_edges);
    $display("SUMMARY normal_wck_edges=%0d same_edge=%0d center_625ps=%0d",
             wck_norm_edges, norm_same_edge, norm_center_edge);
    $display("SUMMARY inverted_wck_edges=%0d same_edge=%0d center_625ps=%0d",
             wck_inv_edges, inv_same_edge, inv_center_edge);
    $display("SUMMARY wck90_edges=%0d same_edge=%0d center_625ps=%0d",
             wck_90_edges, wck90_same_edge, wck90_center_edge);
    $display("SUMMARY wck270_edges=%0d same_edge=%0d center_625ps=%0d",
             wck_270_edges, wck270_same_edge, wck270_center_edge);

    if (norm_same_edge >= 8 && norm_center_edge == 0)
        $display("RESULT NORMAL_WCK: EDGE_ALIGNED_TO_DQ_TRANSITIONS");
    else if (norm_center_edge >= 8)
        $display("RESULT NORMAL_WCK: CENTER_ALIGNED_625PS_FROM_DQ_TRANSITIONS");
    else
        $display("RESULT NORMAL_WCK: INCONCLUSIVE");

    if (inv_same_edge >= 8 && inv_center_edge == 0)
        $display("RESULT INVERTED_WCK: EDGE_ALIGNED_TO_DQ_TRANSITIONS");
    else if (inv_center_edge >= 8)
        $display("RESULT INVERTED_WCK: CENTER_ALIGNED_625PS_FROM_DQ_TRANSITIONS");
    else
        $display("RESULT INVERTED_WCK: INCONCLUSIVE");

    if (wck90_same_edge >= 8 && wck90_center_edge == 0)
        $display("RESULT WCK_90: EDGE_ALIGNED_TO_DQ_TRANSITIONS");
    else if (wck90_center_edge >= 8)
        $display("RESULT WCK_90: CENTER_ALIGNED_625PS_FROM_DQ_TRANSITIONS");
    else
        $display("RESULT WCK_90: INCONCLUSIVE");

    if (wck270_same_edge >= 8 && wck270_center_edge == 0)
        $display("RESULT WCK_270: EDGE_ALIGNED_TO_DQ_TRANSITIONS");
    else if (wck270_center_edge >= 8)
        $display("RESULT WCK_270: CENTER_ALIGNED_625PS_FROM_DQ_TRANSITIONS");
    else
        $display("RESULT WCK_270: INCONCLUSIVE");

    $finish;
end

always @(negedge clk_200m) begin
    if (!rst_n) begin
        word_base <= 5'd0;
        beat0     <= 4'h0;
        beat1     <= 4'h1;
        beat2     <= 4'h2;
        beat3     <= 4'h3;
    end
    else begin
        beat0     <= word_base[3:0];
        beat1     <= (word_base + 5'd1) & 4'hf;
        beat2     <= (word_base + 5'd2) & 4'hf;
        beat3     <= (word_base + 5'd3) & 4'hf;
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
) u_wck_norm (
    .OQ     (wck_norm_q),
    .T_OUT  (),
    .CLK    (clk_400m),
    .CLKDIV (clk_200m),
    .D      (8'b0000_1010),
    .RST    (~rst_n),
    .T      (1'b0)
);

OSERDESE3 #(
    .DATA_WIDTH(4),
    .INIT(1'b0),
    .IS_CLKDIV_INVERTED(1'b0),
    .IS_CLK_INVERTED(1'b0),
    .IS_RST_INVERTED(1'b0),
    .SIM_DEVICE("ULTRASCALE")
) u_wck_inv (
    .OQ     (wck_inv_q),
    .T_OUT  (),
    .CLK    (clk_400m),
    .CLKDIV (clk_200m),
    .D      (8'b0000_0101),
    .RST    (~rst_n),
    .T      (1'b0)
);

OSERDESE3 #(
    .DATA_WIDTH(4),
    .INIT(1'b0),
    .IS_CLKDIV_INVERTED(1'b0),
    .IS_CLK_INVERTED(1'b0),
    .IS_RST_INVERTED(1'b0),
    .SIM_DEVICE("ULTRASCALE")
) u_wck_90 (
    .OQ     (wck_90_q),
    .T_OUT  (),
    .CLK    (clk_400m_wck90),
    .CLKDIV (clk_200m),
    .D      (8'b0000_1010),
    .RST    (~rst_n),
    .T      (1'b0)
);

OSERDESE3 #(
    .DATA_WIDTH(4),
    .INIT(1'b0),
    .IS_CLKDIV_INVERTED(1'b0),
    .IS_CLK_INVERTED(1'b0),
    .IS_RST_INVERTED(1'b0),
    .SIM_DEVICE("ULTRASCALE")
) u_wck_270 (
    .OQ     (wck_270_q),
    .T_OUT  (),
    .CLK    (clk_400m_wck270),
    .CLKDIV (clk_200m),
    .D      (8'b0000_1010),
    .RST    (~rst_n),
    .T      (1'b0)
);

genvar gi;
generate
    for (gi = 0; gi < 4; gi = gi + 1) begin : gen_dq
        OSERDESE3 #(
            .DATA_WIDTH(4),
            .INIT(1'b0),
            .IS_CLKDIV_INVERTED(1'b0),
            .IS_CLK_INVERTED(1'b0),
            .IS_RST_INVERTED(1'b0),
            .SIM_DEVICE("ULTRASCALE")
        ) u_dq (
            .OQ     (dq_q[gi]),
            .T_OUT  (),
            .CLK    (clk_400m),
            .CLKDIV (clk_200m),
            .D      ({4'b0000, beat3[gi], beat2[gi], beat1[gi], beat0[gi]}),
            .RST    (~rst_n),
            .T      (1'b0)
        );
    end
endgenerate

always @(dq_q[0]) begin
    if (rst_n && ($time > START_CHECK_PS) && (dq_q[0] !== 1'bx)) begin
        last_dq0_edge_ps = $time;
        dq0_edges = dq0_edges + 1;
        $display("DQ0_EDGE       t=%0t dq[3:0]=%b beats=%h_%h_%h_%h",
                 $time, dq_q, beat3, beat2, beat1, beat0);
    end
end

always @(wck_norm_q) begin
    time edge_ps;
    time delta_ps;

    if (rst_n && ($time > START_CHECK_PS) && (wck_norm_q !== 1'bx)) begin
        edge_ps = $time;
        #1;
        delta_ps = edge_ps - last_dq0_edge_ps;
        wck_norm_edges = wck_norm_edges + 1;
        if (last_dq0_edge_ps == edge_ps)
            norm_same_edge = norm_same_edge + 1;
        if (delta_ps >= 575 && delta_ps <= 675)
            norm_center_edge = norm_center_edge + 1;
        $display("WCK_N_EDGE     t=%0t wck=%b dq[3:0]=%b delta_from_dq0_edge_ps=%0t",
                 edge_ps, wck_norm_q, dq_q, delta_ps);
    end
end

always @(wck_inv_q) begin
    time edge_ps;
    time delta_ps;

    if (rst_n && ($time > START_CHECK_PS) && (wck_inv_q !== 1'bx)) begin
        edge_ps = $time;
        #1;
        delta_ps = edge_ps - last_dq0_edge_ps;
        wck_inv_edges = wck_inv_edges + 1;
        if (last_dq0_edge_ps == edge_ps)
            inv_same_edge = inv_same_edge + 1;
        if (delta_ps >= 575 && delta_ps <= 675)
            inv_center_edge = inv_center_edge + 1;
        $display("WCK_I_EDGE     t=%0t wck=%b dq[3:0]=%b delta_from_dq0_edge_ps=%0t",
                 edge_ps, wck_inv_q, dq_q, delta_ps);
    end
end

always @(wck_90_q) begin
    time edge_ps;
    time delta_ps;

    if (rst_n && ($time > START_CHECK_PS) && (wck_90_q !== 1'bx)) begin
        edge_ps = $time;
        #1;
        delta_ps = edge_ps - last_dq0_edge_ps;
        wck_90_edges = wck_90_edges + 1;
        if (last_dq0_edge_ps == edge_ps)
            wck90_same_edge = wck90_same_edge + 1;
        if (delta_ps >= 575 && delta_ps <= 675)
            wck90_center_edge = wck90_center_edge + 1;
        $display("WCK_90_EDGE    t=%0t wck=%b dq[3:0]=%b delta_from_dq0_edge_ps=%0t",
                 edge_ps, wck_90_q, dq_q, delta_ps);
    end
end

always @(wck_270_q) begin
    time edge_ps;
    time delta_ps;

    if (rst_n && ($time > START_CHECK_PS) && (wck_270_q !== 1'bx)) begin
        edge_ps = $time;
        #1;
        delta_ps = edge_ps - last_dq0_edge_ps;
        wck_270_edges = wck_270_edges + 1;
        if (last_dq0_edge_ps == edge_ps)
            wck270_same_edge = wck270_same_edge + 1;
        if (delta_ps >= 575 && delta_ps <= 675)
            wck270_center_edge = wck270_center_edge + 1;
        $display("WCK_270_EDGE   t=%0t wck=%b dq[3:0]=%b delta_from_dq0_edge_ps=%0t",
                 edge_ps, wck_270_q, dq_q, delta_ps);
    end
end

endmodule
