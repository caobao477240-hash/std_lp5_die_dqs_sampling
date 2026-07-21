`timescale 1ns / 1ps

// =========================================================================
//  LPDDR5 DQS SERDES PHY
// =========================================================================
// 200 MHz fabric side, 400 MHz serial side.
// TX and RX use independent fixed 400M clocks. Both SERDES CLKDIV ports,
// IDELAY control, and the RX packer remain in the main 200M core domain.
module lpddr5_dqs_serdes_phy (
    input                               i_clk_core_200m            ,
    input                               i_clk_dq_tx_400m           ,
    input                               i_clk_dq_rx_400m           ,
    input                               i_serdes_reset_n           ,

    inout                [  15: 0]      dq_a                       ,
    inout                [   1: 0]      rdqs_t_a                   ,
    inout                [   1: 0]      rdqs_c_a                   ,
    inout                [   1: 0]      dmi_a                      ,

    input                [  63: 0]      dq_a_tx_word               ,
    input                [   7: 0]      dmi_a_tx_word              ,
    input                [   1: 0]      rdqs_t_a_in_dh             ,
    input                [   1: 0]      rdqs_t_a_in_dl             ,
    input                               dq_a_tx_oe                 ,
    input                               cha_group_0_strobe_out_en  ,
    input                               rx_dq_capture_en           ,
    input                [   3: 0]      rx_burst_beat_offset       ,
    input                [ 143: 0]      delay_value_dq_a           ,
    input                               idelay_en_vtc              ,
    input                               idelay_load                ,

    output reg           [  63: 0]      dq_a_word_flat             ,
    output reg                          dq_a_word_valid            ,
    output reg           [ 255: 0]      dq_a_burst_flat            ,
    output reg                          dq_a_burst_valid           ,
    output reg           [  63: 0]      dbg_dq_word_raw
);

genvar i;
genvar l;

    wire                 [  15: 0]      dq_in_raw                  ;
    wire                 [  15: 0]      dq_in_dly                  ;
    wire                 [  15: 0]      dq_out_ser                 ;
    wire                 [  15: 0]      dq_t_ser                   ;
    wire                 [   1: 0]      dmi_in_raw                 ;
    wire                 [   1: 0]      dmi_out_ser                ;
    wire                 [   1: 0]      dmi_t_ser                  ;
    wire                 [   1: 0]      rdqs_in_raw                ;
    wire                 [   1: 0]      rdqs_in_dly                ;
    wire                 [   1: 0]      rdqs_out_ser               ;
    wire                 [   1: 0]      rdqs_t_ser                 ;

    wire                 [   7: 0]      dq_q [0:15]                ;
    wire                 [   7: 0]      rdqs_q[0:1]                ;

    reg                  [   1: 0]      rdqs_t_a_in_dh_d           ;
    reg                  [   1: 0]      rdqs_t_a_in_dl_d           ;

    reg                                 rx_dq_capture_en_d         ;
    reg                  [   5: 0]      rx_capture_req_pipe        ;
    reg                  [  63: 0]      rx_word0                   ;
    reg                  [  63: 0]      rx_word1                   ;
    reg                  [  63: 0]      rx_word2                   ;
    reg                  [  63: 0]      rx_word3                   ;
    reg                  [  63: 0]      rx_word4                   ;
    reg                  [  63: 0]      rx_word5                   ;

    wire                 [  15: 0]      dq_q_beat0                 ;
    wire                 [  15: 0]      dq_q_beat1                 ;
    wire                 [  15: 0]      dq_q_beat2                 ;
    wire                 [  15: 0]      dq_q_beat3                 ;
    wire                 [  63: 0]      dq_q_word_full             ;
    wire                 [ 383: 0]      rx_sample_flat_comb        ;
    wire                 [ 255: 0]      rx_burst_flat_comb         ;
    wire                                rx_capture_start           ;
    wire                                w_rx_word_valid             ;
    wire                                w_rx_serdes_reset           ;

// The outer init/GF logic opens a six-cycle capture window.  The rising edge
// starts six consecutive 64-bit samples.  A host-programmable beat offset
// (bar06 CAPTURE_CFG, 0..8) selects one BL16 burst from the 24 captured
// 16-bit beats; the legacy hardwired value was 3.
localparam [3:0] RX_BURST_BEAT_OFFSET_MAX = 4'd8;

    wire                 [   3: 0]      w_burst_beat_offset        ;
    wire                 [   8: 0]      w_burst_bit_offset         ;

assign dq_q_beat0 = {
    dq_q[15][0], dq_q[14][0], dq_q[13][0], dq_q[12][0],
    dq_q[11][0], dq_q[10][0], dq_q[9][0],  dq_q[8][0],
    dq_q[7][0],  dq_q[6][0],  dq_q[5][0],  dq_q[4][0],
    dq_q[3][0],  dq_q[2][0],  dq_q[1][0],  dq_q[0][0]
};
assign dq_q_beat1 = {
    dq_q[15][1], dq_q[14][1], dq_q[13][1], dq_q[12][1],
    dq_q[11][1], dq_q[10][1], dq_q[9][1],  dq_q[8][1],
    dq_q[7][1],  dq_q[6][1],  dq_q[5][1],  dq_q[4][1],
    dq_q[3][1],  dq_q[2][1],  dq_q[1][1],  dq_q[0][1]
};
assign dq_q_beat2 = {
    dq_q[15][2], dq_q[14][2], dq_q[13][2], dq_q[12][2],
    dq_q[11][2], dq_q[10][2], dq_q[9][2],  dq_q[8][2],
    dq_q[7][2],  dq_q[6][2],  dq_q[5][2],  dq_q[4][2],
    dq_q[3][2],  dq_q[2][2],  dq_q[1][2],  dq_q[0][2]
};
assign dq_q_beat3 = {
    dq_q[15][3], dq_q[14][3], dq_q[13][3], dq_q[12][3],
    dq_q[11][3], dq_q[10][3], dq_q[9][3],  dq_q[8][3],
    dq_q[7][3],  dq_q[6][3],  dq_q[5][3],  dq_q[4][3],
    dq_q[3][3],  dq_q[2][3],  dq_q[1][3],  dq_q[0][3]
};

assign dq_q_word_full      = {dq_q_beat3, dq_q_beat2, dq_q_beat1, dq_q_beat0};
assign rx_sample_flat_comb = {rx_word5, rx_word4, rx_word3, rx_word2, rx_word1, rx_word0};
assign w_burst_beat_offset = (rx_burst_beat_offset > RX_BURST_BEAT_OFFSET_MAX) ? RX_BURST_BEAT_OFFSET_MAX : rx_burst_beat_offset;
assign w_burst_bit_offset  = {1'b0, w_burst_beat_offset, 4'b0000};
assign rx_burst_flat_comb  = rx_sample_flat_comb[w_burst_bit_offset +: 256];
assign rx_capture_start    = (rx_dq_capture_en == 1'b1) && (rx_dq_capture_en_d == 1'b0);
assign w_rx_word_valid     = (rx_capture_start == 1'b1) || (|rx_capture_req_pipe[4:0]);
assign w_rx_serdes_reset   = ~i_serdes_reset_n;

always @(posedge i_clk_core_200m or negedge i_serdes_reset_n) begin
    if (!i_serdes_reset_n) begin
        rdqs_t_a_in_dh_d  <= 2'b00;
        rdqs_t_a_in_dl_d  <= 2'b00;
    end
    else begin
        rdqs_t_a_in_dh_d  <= rdqs_t_a_in_dh;
        rdqs_t_a_in_dl_d  <= rdqs_t_a_in_dl;
    end
end

// Free-running pin loopback view for ILA: the bidirectional IOBUF input
// path stays live while the FPGA drives a write burst, so this register
// shows the actual pin stream with no capture-window gating.
always @(posedge i_clk_core_200m or negedge i_serdes_reset_n) begin
    if (!i_serdes_reset_n) begin
        dbg_dq_word_raw <= 64'h0;
    end
    else begin
        dbg_dq_word_raw <= dq_q_word_full;
    end
end

// -------------------------------------------------------------------------
// TX / bidirectional DQ path
// -------------------------------------------------------------------------
generate
    for (i = 0; i < 16; i = i + 1) begin : GEN_DQ_IO
        wire [8:0] dq_delay_value;
        assign dq_delay_value = delay_value_dq_a[(i * 9) +: 9];

        IOBUFE3 #(
            .SIM_DEVICE("ULTRASCALE"),
            .SIM_INPUT_BUFFER_OFFSET(0),
            .USE_IBUFDISABLE("FALSE")
        ) U_dq_iobuf (
            .O              (dq_in_raw[i]),
            .DCITERMDISABLE (1'b0),
            .I              (dq_out_ser[i]),
            .IBUFDISABLE    (1'b0),
            .IO             (dq_a[i]),
            .OSC            (4'd0),
            .OSC_EN         (1'b0),
            .T              (dq_t_ser[i]),
            .VREF           (1'b0)
        );

        IDELAYE3 #(
            .CASCADE("NONE"),
            .DELAY_FORMAT("COUNT"),
            .DELAY_SRC("DATAIN"),
            .DELAY_TYPE("VAR_LOAD"),
            .DELAY_VALUE(0),
            .IS_CLK_INVERTED(1'b0),
            .IS_RST_INVERTED(1'b0),
            .REFCLK_FREQUENCY(200.0),
            .SIM_DEVICE("ULTRASCALE"),
            .UPDATE_MODE("ASYNC")
        ) U_dq_idelay (
            .CASC_OUT    (),
            .CNTVALUEOUT (),
            .DATAOUT     (dq_in_dly[i]),
            .CASC_IN     (1'b0),
            .CASC_RETURN (1'b0),
            .CE          (1'b0),
            .CLK         (i_clk_core_200m),
            .CNTVALUEIN  (dq_delay_value),
            .DATAIN      (dq_in_raw[i]),
            .EN_VTC      (idelay_en_vtc),
            .IDATAIN     (1'b0),
            .INC         (1'b0),
            .LOAD        (idelay_load),
            .RST         (w_rx_serdes_reset)
        );

        OSERDESE3 #(
            .DATA_WIDTH(4),
            .INIT(1'b0),
            .IS_CLKDIV_INVERTED(1'b0),
            .IS_CLK_INVERTED(1'b0),
            .IS_RST_INVERTED(1'b0),
            .SIM_DEVICE("ULTRASCALE")
        ) U_dq_oserdes (
            .OQ     (dq_out_ser[i]),
            .T_OUT  (dq_t_ser[i]),
            .CLK    (i_clk_dq_tx_400m),
            .CLKDIV (i_clk_core_200m),
            .D      ({4'b0000, dq_a_tx_word[48+i], dq_a_tx_word[32+i], dq_a_tx_word[16+i], dq_a_tx_word[i]}),
            .RST    (w_rx_serdes_reset),
            .T      (~dq_a_tx_oe)
        );

        ISERDESE3 #(
            .DATA_WIDTH(4),
            .FIFO_ENABLE("FALSE"),
            .FIFO_SYNC_MODE("FALSE"),
            .IS_CLK_B_INVERTED(1'b1),
            .IS_CLK_INVERTED(1'b0),
            .IS_RST_INVERTED(1'b0),
            .SIM_DEVICE("ULTRASCALE")
        ) U_dq_iserdes (
            .FIFO_EMPTY      (),
            .INTERNAL_DIVCLK (),
            .Q               (dq_q[i]),
            .CLK             (i_clk_dq_rx_400m),
            .CLKDIV          (i_clk_core_200m),
            .CLK_B           (i_clk_dq_rx_400m),
            .D               (dq_in_dly[i]),
            .FIFO_RD_CLK     (i_clk_core_200m),
            .FIFO_RD_EN      (1'b0),
            .RST             (w_rx_serdes_reset)
        );
    end
endgenerate

// -------------------------------------------------------------------------
// DMI TX path. DMI is not used for read comparison in this first bring-up.
// -------------------------------------------------------------------------
generate
    for (i = 0; i < 2; i = i + 1) begin : GEN_DMI_IO
        IOBUFE3 #(
            .SIM_DEVICE("ULTRASCALE"),
            .SIM_INPUT_BUFFER_OFFSET(0),
            .USE_IBUFDISABLE("FALSE")
        ) U_dmi_iobuf (
            .O              (dmi_in_raw[i]),
            .DCITERMDISABLE (1'b0),
            .I              (dmi_out_ser[i]),
            .IBUFDISABLE    (1'b0),
            .IO             (dmi_a[i]),
            .OSC            (4'd0),
            .OSC_EN         (1'b0),
            .T              (dmi_t_ser[i]),
            .VREF           (1'b0)
        );

        OSERDESE3 #(
            .DATA_WIDTH(4),
            .INIT(1'b0),
            .IS_CLKDIV_INVERTED(1'b0),
            .IS_CLK_INVERTED(1'b0),
            .IS_RST_INVERTED(1'b0),
            .SIM_DEVICE("ULTRASCALE")
        ) U_dmi_oserdes (
            .OQ     (dmi_out_ser[i]),
            .T_OUT  (dmi_t_ser[i]),
            .CLK    (i_clk_dq_tx_400m),
            .CLKDIV (i_clk_core_200m),
            .D      ({4'b0000, dmi_a_tx_word[6+i], dmi_a_tx_word[4+i],
                      dmi_a_tx_word[2+i], dmi_a_tx_word[i]}),
            .RST    (w_rx_serdes_reset),
            .T      (~dq_a_tx_oe)
        );
    end
endgenerate

// -------------------------------------------------------------------------
// RDQS/DQS bidirectional path
// -------------------------------------------------------------------------
generate
    for (l = 0; l < 2; l = l + 1) begin : GEN_RDQS_IO
        IOBUFDS U_rdqs_iobuf (
            .O   (rdqs_in_raw[l]),
            .I   (rdqs_out_ser[l]),
            .IO  (rdqs_t_a[l]),
            .IOB (rdqs_c_a[l]),
            .T   (rdqs_t_ser[l])
        );

        IDELAYE3 #(
            .CASCADE("NONE"),
            .DELAY_FORMAT("COUNT"),
            .DELAY_SRC("DATAIN"),
            .DELAY_TYPE("VAR_LOAD"),
            .DELAY_VALUE(0),
            .IS_CLK_INVERTED(1'b0),
            .IS_RST_INVERTED(1'b0),
            .REFCLK_FREQUENCY(200.0),
            .SIM_DEVICE("ULTRASCALE"),
            .UPDATE_MODE("ASYNC")
        ) U_rdqs_idelay (
            .CASC_OUT    (),
            .CNTVALUEOUT (),
            .DATAOUT     (rdqs_in_dly[l]),
            .CASC_IN     (1'b0),
            .CASC_RETURN (1'b0),
            .CE          (1'b0),
            .CLK         (i_clk_core_200m),
            .CNTVALUEIN  (9'd0),
            .DATAIN      (rdqs_in_raw[l]),
            .EN_VTC      (idelay_en_vtc),
            .IDATAIN     (1'b0),
            .INC         (1'b0),
            .LOAD        (idelay_load),
            .RST         (w_rx_serdes_reset)
        );

        ISERDESE3 #(
            .DATA_WIDTH(4),
            .FIFO_ENABLE("FALSE"),
            .FIFO_SYNC_MODE("FALSE"),
            .IS_CLK_B_INVERTED(1'b1),
            .IS_CLK_INVERTED(1'b0),
            .IS_RST_INVERTED(1'b0),
            .SIM_DEVICE("ULTRASCALE")
        ) U_rdqs_iserdes (
            .FIFO_EMPTY      (),
            .INTERNAL_DIVCLK (),
            .Q               (rdqs_q[l]),
            .CLK             (i_clk_dq_tx_400m),
            .CLKDIV          (i_clk_core_200m),
            .CLK_B           (i_clk_dq_tx_400m),
            .D               (rdqs_in_dly[l]),
            .FIFO_RD_CLK     (i_clk_core_200m),
            .FIFO_RD_EN      (1'b0),
            .RST             (w_rx_serdes_reset)
        );

        OSERDESE3 #(
            .DATA_WIDTH(4),
            .INIT(1'b0),
            .IS_CLKDIV_INVERTED(1'b0),
            .IS_CLK_INVERTED(1'b0),
            .IS_RST_INVERTED(1'b0),
            .SIM_DEVICE("ULTRASCALE")
        ) U_rdqs_oserdes (
            .OQ     (rdqs_out_ser[l]),
            .T_OUT  (rdqs_t_ser[l]),
            .CLK    (i_clk_dq_tx_400m),
            .CLKDIV (i_clk_core_200m),
            .D      ({4'b0000, rdqs_t_a_in_dh[l], rdqs_t_a_in_dl[l], rdqs_t_a_in_dh_d[l], rdqs_t_a_in_dl_d[l]}),
            .RST    (w_rx_serdes_reset),
            .T      (~cha_group_0_strobe_out_en)
        );
    end
endgenerate

// -------------------------------------------------------------------------
// RX packer in the main 200 MHz domain.  The raw word window shifts every
// cycle.  Each capture request carries a six-cycle marker, so overlapping
// read windows can share the same sampled word history without dropping a
// request.  The marker latency keeps dq_a_burst_valid aligned with the old
// one-shot packer.
// -------------------------------------------------------------------------
always @(posedge i_clk_core_200m or negedge i_serdes_reset_n) begin
    if (!i_serdes_reset_n) begin
        rx_dq_capture_en_d <= 1'b0;
    end
    else begin
        rx_dq_capture_en_d <= rx_dq_capture_en;
    end
end

always @(posedge i_clk_core_200m or negedge i_serdes_reset_n) begin
    if (!i_serdes_reset_n) begin
        rx_capture_req_pipe <= 6'b000000;
    end
    else begin
        rx_capture_req_pipe <= {rx_capture_req_pipe[4:0], rx_capture_start};
    end
end

always @(posedge i_clk_core_200m or negedge i_serdes_reset_n) begin
    if (!i_serdes_reset_n) begin
        rx_word0 <= 64'h0;
    end
    else begin
        rx_word0 <= rx_word1;
    end
end

always @(posedge i_clk_core_200m or negedge i_serdes_reset_n) begin
    if (!i_serdes_reset_n) begin
        rx_word1 <= 64'h0;
    end
    else begin
        rx_word1 <= rx_word2;
    end
end

always @(posedge i_clk_core_200m or negedge i_serdes_reset_n) begin
    if (!i_serdes_reset_n) begin
        rx_word2 <= 64'h0;
    end
    else begin
        rx_word2 <= rx_word3;
    end
end

always @(posedge i_clk_core_200m or negedge i_serdes_reset_n) begin
    if (!i_serdes_reset_n) begin
        rx_word3 <= 64'h0;
    end
    else begin
        rx_word3 <= rx_word4;
    end
end

always @(posedge i_clk_core_200m or negedge i_serdes_reset_n) begin
    if (!i_serdes_reset_n) begin
        rx_word4 <= 64'h0;
    end
    else begin
        rx_word4 <= rx_word5;
    end
end

always @(posedge i_clk_core_200m or negedge i_serdes_reset_n) begin
    if (!i_serdes_reset_n) begin
        rx_word5 <= 64'h0;
    end
    else begin
        rx_word5 <= dq_q_word_full;
    end
end

always @(posedge i_clk_core_200m or negedge i_serdes_reset_n) begin
    if (!i_serdes_reset_n) begin
        dq_a_word_flat <= 64'h0;
    end
    else if (w_rx_word_valid == 1'b1) begin
        dq_a_word_flat <= dq_q_word_full;
    end
    else begin
        dq_a_word_flat <= dq_a_word_flat;
    end
end

always @(posedge i_clk_core_200m or negedge i_serdes_reset_n) begin
    if (!i_serdes_reset_n) begin
        dq_a_word_valid <= 1'b0;
    end
    else if (w_rx_word_valid == 1'b1) begin
        dq_a_word_valid <= 1'b1;
    end
    else begin
        dq_a_word_valid <= 1'b0;
    end
end

always @(posedge i_clk_core_200m or negedge i_serdes_reset_n) begin
    if (!i_serdes_reset_n) begin
        dq_a_burst_flat <= 256'h0;
    end
    else if (rx_capture_req_pipe[5] == 1'b1) begin
        dq_a_burst_flat <= rx_burst_flat_comb;
    end
    else begin
        dq_a_burst_flat <= dq_a_burst_flat;
    end
end

always @(posedge i_clk_core_200m or negedge i_serdes_reset_n) begin
    if (!i_serdes_reset_n) begin
        dq_a_burst_valid <= 1'b0;
    end
    else if (rx_capture_req_pipe[5] == 1'b1) begin
        dq_a_burst_valid <= 1'b1;
    end
    else begin
        dq_a_burst_valid <= 1'b0;
    end
end

endmodule
