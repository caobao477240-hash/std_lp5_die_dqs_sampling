`timescale 1ns / 1ps

/**
 * clock_manage_top
 * LPDDR5 fixed clock generation.
 */
module clock_manage_top (
    input  wire                 i_sys_clk_p                ,
    input  wire                 i_sys_clk_n                ,
    input  wire                 i_reset                    ,
    input  wire                 i_idelayctrl_ready         ,
    output wire                 o_clk_periph_40m           ,
    output wire                 o_clk_core_200m            ,
    output wire                 o_core_reset_n             ,
    output wire                 o_clk_lp5_dq_tx_400m       ,
    output wire                 o_clk_lp5_ca_wck_400m      ,
    output wire                 o_clk_lp5_dq_rx_400m       ,
    output wire                 o_lp5_serdes_reset_n       ,
    output wire                 o_lp5_idelayctrl_reset     ,
    output wire                 o_lp5_phy_ready            ,
    output wire                 o_mmcm_locked
);

/***************parameter*************/
localparam [2:0] P_STARTUP_WAIT_LOCK          = 3'd0;
localparam [2:0] P_STARTUP_RELEASE_SERDES     = 3'd1;
localparam [2:0] P_STARTUP_RELEASE_IDELAYCTRL = 3'd2;
localparam [2:0] P_STARTUP_WAIT_IDELAYCTRL    = 3'd3;
localparam [2:0] P_STARTUP_SETTLE             = 3'd4;
localparam [2:0] P_STARTUP_READY              = 3'd5;

localparam [6:0] P_PHY_SETTLE_LAST            = 7'd63;

/***************reg*******************/
(* ASYNC_REG = "TRUE" *) reg [3:0] r_mmcm_locked_sync;
(* ASYNC_REG = "TRUE" *) reg [1:0] r_idelayctrl_ready_sync;

reg  [2:0]                 r_startup_state;
reg  [6:0]                 r_phy_settle_cnt;
reg                        ro_lp5_serdes_reset_n;
reg                        ro_lp5_idelayctrl_reset;
reg                        ro_lp5_phy_ready;

/***************wire******************/
wire                       w_clk_unused_20m;
wire                       w_mmcm_locked;
wire                       w_startup_reset;

/***************component*************/
clk_wiz_0 clk_wiz_0_u0 (
    .clk_out1                           (w_clk_unused_20m           ),
    .clk_out2                           (o_clk_periph_40m           ),
    .clk_out3                           (o_clk_core_200m            ),
    .clk_out4                           (o_clk_lp5_dq_tx_400m       ),
    .clk_out5                           (o_clk_lp5_ca_wck_400m      ),
    .clk_out6                           (o_clk_lp5_dq_rx_400m       ),
    .reset                              (i_reset                    ),
    .locked                             (w_mmcm_locked              ),
    .clk_in1_p                          (i_sys_clk_p                ),
    .clk_in1_n                          (i_sys_clk_n                )
);

/***************assign****************/
assign w_startup_reset          = i_reset | (~w_mmcm_locked);
assign o_core_reset_n           = r_mmcm_locked_sync[3];
assign o_mmcm_locked            = w_mmcm_locked;
assign o_lp5_serdes_reset_n     = ro_lp5_serdes_reset_n;
assign o_lp5_idelayctrl_reset   = ro_lp5_idelayctrl_reset;
assign o_lp5_phy_ready          = ro_lp5_phy_ready;

/***************always****************/
// LOCKED can assert asynchronously to the 200M core clock. Four sampled
// cycles provide one deterministic reset release point for the 200M control
// domain and the LPDDR5 PHY startup FSM.
always @(posedge o_clk_core_200m or posedge w_startup_reset) begin
    if (w_startup_reset) begin
        r_mmcm_locked_sync <= 4'b0000;
    end
    else begin
        r_mmcm_locked_sync <= {r_mmcm_locked_sync[2:0], w_mmcm_locked};
    end
end

always @(posedge o_clk_core_200m or posedge w_startup_reset) begin
    if (w_startup_reset) begin
        r_idelayctrl_ready_sync <= 2'b00;
    end
    else begin
        r_idelayctrl_ready_sync <= {r_idelayctrl_ready_sync[0], i_idelayctrl_ready};
    end
end

// Startup order: MMCM stable -> SERDES release -> IDELAYCTRL release ->
// IDELAYCTRL ready -> 64 core clocks -> LPDDR5 controller release.
always @(posedge o_clk_core_200m or posedge w_startup_reset) begin
    if (w_startup_reset) begin
        r_startup_state           <= P_STARTUP_WAIT_LOCK;
        r_phy_settle_cnt          <= 7'd0;
        ro_lp5_serdes_reset_n     <= 1'b0;
        ro_lp5_idelayctrl_reset   <= 1'b1;
        ro_lp5_phy_ready          <= 1'b0;
    end
    else begin
        case (r_startup_state)
            P_STARTUP_WAIT_LOCK: begin
                r_phy_settle_cnt        <= 7'd0;
                ro_lp5_serdes_reset_n   <= 1'b0;
                ro_lp5_idelayctrl_reset <= 1'b1;
                ro_lp5_phy_ready        <= 1'b0;

                if (&r_mmcm_locked_sync) begin
                    r_startup_state <= P_STARTUP_RELEASE_SERDES;
                end
                else begin
                    r_startup_state <= r_startup_state;
                end
            end

            P_STARTUP_RELEASE_SERDES: begin
                r_startup_state         <= P_STARTUP_RELEASE_IDELAYCTRL;
                r_phy_settle_cnt        <= 7'd0;
                ro_lp5_serdes_reset_n   <= 1'b1;
                ro_lp5_idelayctrl_reset <= 1'b1;
                ro_lp5_phy_ready        <= 1'b0;
            end

            P_STARTUP_RELEASE_IDELAYCTRL: begin
                r_startup_state         <= P_STARTUP_WAIT_IDELAYCTRL;
                r_phy_settle_cnt        <= 7'd0;
                ro_lp5_serdes_reset_n   <= 1'b1;
                ro_lp5_idelayctrl_reset <= 1'b0;
                ro_lp5_phy_ready        <= 1'b0;
            end

            P_STARTUP_WAIT_IDELAYCTRL: begin
                r_phy_settle_cnt        <= 7'd0;
                ro_lp5_serdes_reset_n   <= 1'b1;
                ro_lp5_idelayctrl_reset <= 1'b0;
                ro_lp5_phy_ready        <= 1'b0;

                if (r_idelayctrl_ready_sync[1] == 1'b1) begin
                    r_startup_state <= P_STARTUP_SETTLE;
                end
                else begin
                    r_startup_state <= r_startup_state;
                end
            end

            P_STARTUP_SETTLE: begin
                ro_lp5_serdes_reset_n   <= 1'b1;
                ro_lp5_idelayctrl_reset <= 1'b0;
                ro_lp5_phy_ready        <= 1'b0;

                if (r_phy_settle_cnt >= P_PHY_SETTLE_LAST) begin
                    r_startup_state  <= P_STARTUP_READY;
                    r_phy_settle_cnt <= r_phy_settle_cnt;
                    ro_lp5_phy_ready <= 1'b1;
                end
                else begin
                    r_startup_state  <= r_startup_state;
                    r_phy_settle_cnt <= r_phy_settle_cnt + 7'd1;
                end
            end

            P_STARTUP_READY: begin
                r_startup_state         <= r_startup_state;
                r_phy_settle_cnt        <= r_phy_settle_cnt;
                ro_lp5_serdes_reset_n   <= 1'b1;
                ro_lp5_idelayctrl_reset <= 1'b0;
                ro_lp5_phy_ready        <= 1'b1;
            end

            default: begin
                r_startup_state         <= P_STARTUP_WAIT_LOCK;
                r_phy_settle_cnt        <= 7'd0;
                ro_lp5_serdes_reset_n   <= 1'b0;
                ro_lp5_idelayctrl_reset <= 1'b1;
                ro_lp5_phy_ready        <= 1'b0;
            end
        endcase
    end
end

endmodule
