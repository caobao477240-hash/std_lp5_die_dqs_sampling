`timescale 1ns / 1ps

module tb_lp5_phy_reset_sequence;

reg         r_sys_clk_p;
reg         r_reset;
reg         r_idelayctrl_ready;

wire        w_sys_clk_n;
wire        w_clk_core_200m;
wire        w_core_reset_n;
wire        w_lp5_serdes_reset_n;
wire        w_lp5_idelayctrl_reset;
wire        w_lp5_phy_ready;
wire        w_mmcm_locked;

integer     r_ready_wait_cycles;
integer     r_core_reset_wait_cycles;

assign w_sys_clk_n = ~r_sys_clk_p;

always #2.5 r_sys_clk_p = ~r_sys_clk_p;

clock_manage_top clock_manage_top_u0 (
    .i_sys_clk_p                        (r_sys_clk_p               ),
    .i_sys_clk_n                        (w_sys_clk_n               ),
    .i_reset                            (r_reset                   ),
    .i_idelayctrl_ready                 (r_idelayctrl_ready        ),
    .o_clk_periph_40m                   (                          ),
    .o_clk_core_200m                    (w_clk_core_200m           ),
    .o_core_reset_n                     (w_core_reset_n            ),
    .o_clk_lp5_dq_tx_400m               (                          ),
    .o_clk_lp5_ca_wck_400m              (                          ),
    .o_clk_lp5_dq_rx_400m               (                          ),
    .o_lp5_serdes_reset_n               (w_lp5_serdes_reset_n      ),
    .o_lp5_idelayctrl_reset             (w_lp5_idelayctrl_reset    ),
    .o_lp5_phy_ready                    (w_lp5_phy_ready           ),
    .o_mmcm_locked                      (w_mmcm_locked             )
);

initial begin
    r_sys_clk_p              = 1'b0;
    r_reset                  = 1'b1;
    r_idelayctrl_ready       = 1'b0;
    r_ready_wait_cycles      = 0;
    r_core_reset_wait_cycles = 0;

    repeat (4) @(posedge r_sys_clk_p);
    r_reset = 1'b0;

    wait (w_mmcm_locked == 1'b1);

    while (w_core_reset_n == 1'b0) begin
        @(posedge w_clk_core_200m);
        r_core_reset_wait_cycles = r_core_reset_wait_cycles + 1;
    end

    if (r_core_reset_wait_cycles < 4) begin
        $display("SIM FAIL: core reset released too early, cycles=%0d",
                 r_core_reset_wait_cycles);
        $finish;
    end

    wait (w_lp5_serdes_reset_n == 1'b1);

    if (w_lp5_idelayctrl_reset != 1'b1) begin
        $display("SIM FAIL: IDELAYCTRL reset released with SERDES reset");
        $finish;
    end

    wait (w_lp5_idelayctrl_reset == 1'b0);
    repeat (4) @(posedge w_clk_core_200m);
    r_idelayctrl_ready = 1'b1;

    while (w_lp5_phy_ready == 1'b0) begin
        @(posedge w_clk_core_200m);
        r_ready_wait_cycles = r_ready_wait_cycles + 1;
    end

    if (r_ready_wait_cycles < 64) begin
        $display("SIM FAIL: PHY ready wait too short, cycles=%0d", r_ready_wait_cycles);
        $finish;
    end

    repeat (20) @(posedge w_clk_core_200m);
    if ((w_lp5_serdes_reset_n != 1'b1) ||
        (w_lp5_idelayctrl_reset != 1'b0) ||
        (w_lp5_phy_ready != 1'b1)) begin
        $display("SIM FAIL: PHY startup outputs changed after ready");
        $finish;
    end

    force clock_manage_top_u0.w_mmcm_locked = 1'b0;
    #1;
    if ((w_core_reset_n != 1'b0) ||
        (w_lp5_serdes_reset_n != 1'b0) ||
        (w_lp5_idelayctrl_reset != 1'b1) ||
        (w_lp5_phy_ready != 1'b0)) begin
        $display("SIM FAIL: asynchronous lock-loss reset assertion failed");
        $finish;
    end
    release clock_manage_top_u0.w_mmcm_locked;

    r_reset = 1'b1;
    #1;
    if ((w_core_reset_n != 1'b0) ||
        (w_lp5_serdes_reset_n != 1'b0) ||
        (w_lp5_idelayctrl_reset != 1'b1) ||
        (w_lp5_phy_ready != 1'b0)) begin
        $display("SIM FAIL: asynchronous reset assertion failed");
        $finish;
    end

    $display("SIM PASS: core_reset_wait_cycles=%0d, ready_wait_cycles=%0d",
             r_core_reset_wait_cycles, r_ready_wait_cycles);
    $finish;
end

endmodule

// Clock Wizard behavior needed by this reset-only regression.
module clk_wiz_0 (
    output wire clk_out1,
    output wire clk_out2,
    output wire clk_out3,
    output wire clk_out4,
    output wire clk_out5,
    output wire clk_out6,
    input  wire reset,
    output reg  locked,
    input  wire clk_in1_p,
    input  wire clk_in1_n
);

reg [2:0] r_lock_cnt;

assign clk_out1 = clk_in1_p;
assign clk_out2 = clk_in1_p;
assign clk_out3 = clk_in1_p;
assign clk_out4 = clk_in1_p;
assign clk_out5 = clk_in1_p;
assign clk_out6 = clk_in1_p;

always @(posedge clk_in1_p or posedge reset) begin
    if (reset) begin
        r_lock_cnt <= 3'd0;
        locked     <= 1'b0;
    end
    else if (r_lock_cnt >= 3'd3) begin
        r_lock_cnt <= r_lock_cnt;
        locked     <= 1'b1;
    end
    else begin
        r_lock_cnt <= r_lock_cnt + 3'd1;
        locked     <= 1'b0;
    end
end

endmodule
