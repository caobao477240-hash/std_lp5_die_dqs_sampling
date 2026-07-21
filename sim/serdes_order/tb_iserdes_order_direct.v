`timescale 1ps/1ps

module tb_iserdes_order_direct;

reg        clk_400m = 1'b0;
reg        clk_200m = 1'b0;
reg        rst_n    = 1'b0;
reg        d_in     = 1'b0;
wire [7:0] q;

integer bit_idx = 0;
reg [0:63] serial_bits;

// Align the first rising edge of CLK and CLKDIV, then keep 400M/200M locked.
initial begin
    #100;
    clk_400m = 1'b1;
    forever #1250 clk_400m = ~clk_400m;
end

initial begin
    #100;
    clk_200m = 1'b1;
    forever #2500 clk_200m = ~clk_200m;
end

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
    .Q               (q),
    .CLK             (clk_400m),
    .CLKDIV          (clk_200m),
    .CLK_B           (clk_400m),
    .D               (d_in),
    .FIFO_RD_CLK     (clk_200m),
    .FIFO_RD_EN      (1'b0),
    .RST             (~rst_n)
);

initial begin
    // Serial order is grouped as b0,b1,b2,b3 for these one-hot words:
    // 0001, 0010, 0100, 1000, then alternating patterns.
    serial_bits = {
        4'b1000, 4'b0100, 4'b0010, 4'b0001,
        4'b1010, 4'b0101, 4'b1100, 4'b0011,
        4'b1000, 4'b0100, 4'b0010, 4'b0001,
        4'b1010, 4'b0101, 4'b1100, 4'b0011
    };

    repeat (4) @(posedge clk_200m);
    rst_n = 1'b1;
    d_in = serial_bits[0];

    repeat (36) @(posedge clk_200m);
    $finish;
end

// Update D shortly after each sample edge so it is stable for the next edge.
always @(posedge clk_400m or negedge clk_400m) begin
    if (rst_n) begin
        #100;
        bit_idx = bit_idx + 1;
        d_in = serial_bits[bit_idx % 64];
    end
end

always @(posedge clk_200m) begin
    #10;
    if (rst_n) begin
        $display("ISERDES_DIRECT t=%0t bit_idx=%0d q=%08b q3_0=%04b q0_3=%04b",
                 $time, bit_idx, q, q[3:0], {q[0], q[1], q[2], q[3]});
    end
end

endmodule
