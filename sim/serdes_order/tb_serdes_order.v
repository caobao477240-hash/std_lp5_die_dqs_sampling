`timescale 1ps/1ps

module tb_serdes_order;

reg        clk_400m = 1'b0;
reg        clk_200m = 1'b0;
reg        rst_n    = 1'b0;
reg  [3:0] tx_word  = 4'b0001;
wire       serial_q;
wire [7:0] iserdes_q;

always #1250 clk_400m = ~clk_400m;
always #2500 clk_200m = ~clk_200m;

OSERDESE3 #(
    .DATA_WIDTH(4),
    .INIT(1'b0),
    .IS_CLKDIV_INVERTED(1'b0),
    .IS_CLK_INVERTED(1'b0),
    .IS_RST_INVERTED(1'b0),
    .SIM_DEVICE("ULTRASCALE")
) u_oserdes (
    .OQ     (serial_q),
    .T_OUT  (),
    .CLK    (clk_400m),
    .CLKDIV (clk_200m),
    .D      ({4'b0000, tx_word[3], tx_word[2], tx_word[1], tx_word[0]}),
    .RST    (~rst_n),
    .T      (1'b0)
);

ISERDESE3 #(
    .DATA_WIDTH(4),
    .FIFO_ENABLE("FALSE"),
    .FIFO_SYNC_MODE("FALSE"),
    .IS_CLK_B_INVERTED(1'b1),
    .IS_CLK_INVERTED(1'b0),
    .IS_RST_INVERTED(1'b0),
    .SIM_DEVICE("ULTRASCALE")
) u_iserdes (
    .FIFO_EMPTY      (),
    .INTERNAL_DIVCLK (),
    .Q               (iserdes_q),
    .CLK             (clk_400m),
    .CLKDIV          (clk_200m),
    .CLK_B           (clk_400m),
    .D               (serial_q),
    .FIFO_RD_CLK     (clk_200m),
    .FIFO_RD_EN      (1'b0),
    .RST             (~rst_n)
);

initial begin
    repeat (6) @(posedge clk_200m);
    rst_n = 1'b1;

    repeat (2) @(posedge clk_200m);
    tx_word <= 4'b0001;
    @(posedge clk_200m);
    tx_word <= 4'b0010;
    @(posedge clk_200m);
    tx_word <= 4'b0100;
    @(posedge clk_200m);
    tx_word <= 4'b1000;
    @(posedge clk_200m);
    tx_word <= 4'b1010;
    @(posedge clk_200m);
    tx_word <= 4'b0101;
    repeat (8) @(posedge clk_200m);
    $finish;
end

always @(posedge clk_200m) begin
    if (rst_n) begin
        $display(
            "ORDER t=%0t tx_word=%04b q=%08b q3_0=%04b q0_3=%04b",
            $time,
            tx_word,
            iserdes_q,
            iserdes_q[3:0],
            {iserdes_q[0], iserdes_q[1], iserdes_q[2], iserdes_q[3]}
        );
    end
end

endmodule
