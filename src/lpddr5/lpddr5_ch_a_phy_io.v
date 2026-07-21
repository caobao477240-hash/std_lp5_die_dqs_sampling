`timescale 1ns / 1ps

// =========================================================================
//  LPDDR5 Channel A PHY IO
// =========================================================================
// Contains only the UltraScale IO primitives for LPDDR5 channel A.
module lpddr5_ch_a_phy_io (
    input               i_clk_core_200m             ,
    input               i_clk_dq_tx_400m            ,
    input               i_clk_ca_wck_400m           ,
    input               i_clk_dq_rx_400m            ,
    input               i_serdes_reset_n            ,

    output              reset_n_a                   ,
    output              ck_t_a                      ,
    output              ck_c_a                      ,
    output              cs0_a                       ,
    output      [6:0]   ca_a                        ,
    inout       [15:0]  dq_a                        ,
    output      [1:0]   wck_t_a                     ,
    output      [1:0]   wck_c_a                     ,
    inout       [1:0]   rdqs_t_a                    ,
    inout       [1:0]   rdqs_c_a                    ,
    inout       [1:0]   dmi_a                       ,

    input               ck_a_run_en                 ,
    input       [1:0]   wck_a_run_en                ,
    input       [1:0]   wck_a_phase                 ,
    input               reset_n_a_level             ,
    input               cs_a_0_rise                 ,
    input               cs_a_0_fall                 ,
    input       [6:0]   ca_a_rise                   ,
    input       [6:0]   ca_a_fall                   ,

    input       [63:0]  dq_a_tx_word                ,
    input       [7:0]   dmi_a_tx_word               ,
    output      [63:0]  dq_a_word_flat              ,
    output              dq_a_word_valid             ,
    input       [1:0]   rdqs_t_a_in_dh              ,
    input       [1:0]   rdqs_t_a_in_dl              ,

    input               dq_a_tx_oe                  ,
    input               cha_group_0_strobe_out_en   ,
    input       [143:0] delay_value_dq_a            ,
    input               idelay_en_vtc               ,
    input               idelay_load                 ,
    input               rx_dq_capture_en            ,
    input       [3:0]   rx_burst_beat_offset        ,
    output      [255:0] dq_a_burst_flat             ,
    output              dq_a_burst_valid            ,
    output      [63:0]  dbg_dq_word_raw
);

genvar i;
genvar b;

wire            ck_a;
wire [1:0]      wck_a;

// ck_a differential output buffer
OBUFDS OBUFDS_inst_a (
    .O                                  (ck_t_a                    ),
    .OB                                 (ck_c_a                    ),
    .I                                  (ck_a                      )
);

lpddr5_serdes_ck_1bit U_ck_a_serdes (
    .clk_200m                           (i_clk_core_200m          ),
    .clk_400m                           (i_clk_ca_wck_400m        ),
    .rst_n                              (i_serdes_reset_n          ),
    .ck_run_en                          (ck_a_run_en              ),
    .out_q                              (ck_a                     )
);

// wck_a differential output buffers
OBUFDS OBUFDS_wck_a_0 (
    .O                                  (wck_t_a[0]                ),
    .OB                                 (wck_c_a[0]                ),
    .I                                  (wck_a[0]                  )
);

OBUFDS OBUFDS_wck_a_1 (
    .O                                  (wck_t_a[1]                ),
    .OB                                 (wck_c_a[1]                ),
    .I                                  (wck_a[1]                  )
);

generate
    for (i = 0; i < 2; i = i + 1) begin : GEN_WCK_SERDES
        lpddr5_serdes_wck_1bit U_wck_a_serdes (
    .clk_200m                           (i_clk_core_200m          ),
    .clk_400m                           (i_clk_ca_wck_400m        ),
    .rst_n                              (i_serdes_reset_n          ),
    .run_en                             (wck_a_run_en[i]          ),
    .phase                              (wck_a_phase[i]           ),
    .out_q                              (wck_a[i]                 )
        );
    end
endgenerate

// DQ TX and RX keep independent fixed 400M clock trees.
lpddr5_dqs_serdes_phy U_lpddr5_dqs_serdes_phy (
    .i_clk_core_200m                    (i_clk_core_200m           ),
    .i_clk_dq_tx_400m                   (i_clk_dq_tx_400m          ),
    .i_clk_dq_rx_400m                   (i_clk_dq_rx_400m          ),
    .i_serdes_reset_n                   (i_serdes_reset_n          ),
    .dq_a                               (dq_a                      ),
    .rdqs_t_a                           (rdqs_t_a                  ),
    .rdqs_c_a                           (rdqs_c_a                  ),
    .dmi_a                              (dmi_a                     ),
    .dq_a_tx_word                       (dq_a_tx_word              ),
    .dmi_a_tx_word                      (dmi_a_tx_word              ),
    .rdqs_t_a_in_dh                     (rdqs_t_a_in_dh            ),
    .rdqs_t_a_in_dl                     (rdqs_t_a_in_dl            ),
    .dq_a_tx_oe                         (dq_a_tx_oe                 ),
    .cha_group_0_strobe_out_en          (cha_group_0_strobe_out_en ),
    .delay_value_dq_a                   (delay_value_dq_a           ),
    .idelay_en_vtc                      (idelay_en_vtc             ),
    .idelay_load                        (idelay_load               ),
    .rx_dq_capture_en                   (rx_dq_capture_en           ),
    .rx_burst_beat_offset               (rx_burst_beat_offset       ),
    .dq_a_word_flat                     (dq_a_word_flat            ),
    .dq_a_word_valid                    (dq_a_word_valid           ),
    .dq_a_burst_flat                    (dq_a_burst_flat           ),
    .dq_a_burst_valid                   (dq_a_burst_valid          ),
    .dbg_dq_word_raw                    (dbg_dq_word_raw            )
);

lpddr5_serdes_ddr_1bit U_reset_n_a_serdes (
    .clk_200m                           (i_clk_core_200m           ),
    .clk_400m                           (i_clk_ca_wck_400m         ),
    .rst_n                              (i_serdes_reset_n          ),
    .data_rise                          (reset_n_a_level           ),
    .data_fall                          (reset_n_a_level           ),
    .out_q                              (reset_n_a                 )
);

lpddr5_serdes_ddr_1bit U_cs0_a_serdes (
    .clk_200m                           (i_clk_core_200m           ),
    .clk_400m                           (i_clk_ca_wck_400m         ),
    .rst_n                              (i_serdes_reset_n          ),
    .data_rise                          (cs_a_0_rise               ),
    .data_fall                          (cs_a_0_fall               ),
    .out_q                              (cs0_a                     )
);

generate
    for (b = 0; b < 7; b = b + 1) begin : GEN_CA_SERDES
    lpddr5_serdes_ddr_1bit U_ca_a_serdes (
    .clk_200m                           (i_clk_core_200m           ),
    .clk_400m                           (i_clk_ca_wck_400m         ),
    .rst_n                              (i_serdes_reset_n          ),
    .data_rise                          (ca_a_rise[b]              ),
    .data_fall                          (ca_a_fall[b]              ),
    .out_q                              (ca_a[b]                   )
        );
    end
endgenerate

endmodule

module lpddr5_serdes_ck_1bit (
    input                               clk_200m                   ,
    input                               clk_400m                   ,
    input                               rst_n                      ,
    input                               ck_run_en                  ,
    output                              out_q
);

wire [7:0] ck_pattern;

// CK run enable selects the fixed 200 MHz pattern or a static-low output.
assign ck_pattern = (ck_run_en == 1'b1) ? 8'b0000_0110 : 8'b0000_0000;

// CK is restored to 200 MHz for WCK:CK=2:1.  This wrapper is intentionally
// clocked by the WCK-shifted 400M clock so CK/CA stay in the same WCK2CK phase
// family while DQ TX remains on the unshifted 400M data clock.
// D0 is launched first. CA/CS/RESET launch as rise,rise,fall,fall, so 0,1,1,0
// places each CK edge in the middle of its two-UI command/address hold window.
OSERDESE3 #(
    .DATA_WIDTH                         (4                         ),
    .INIT                               (1'b0                      ),
    .IS_CLKDIV_INVERTED                 (1'b0                      ),
    .IS_CLK_INVERTED                    (1'b0                      ),
    .IS_RST_INVERTED                    (1'b0                      ),
    .SIM_DEVICE                         ("ULTRASCALE"              )
) U_oserdes (
    .OQ                                 (out_q                     ),
    .T_OUT                              (                          ),
    .CLK                                (clk_400m                  ),
    .CLKDIV                             (clk_200m                  ),
    .D                                  (ck_pattern                ),
    .RST                                (~rst_n                    ),
    .T                                  (1'b0                      )
);

endmodule

module lpddr5_serdes_ddr_1bit (
    input                               clk_200m                   ,
    input                               clk_400m                   ,
    input                               rst_n                      ,
    input                               data_rise                  ,
    input                               data_fall                  ,
    output                              out_q
);

// CA/CS/RESET are held for two 800 MT/s UI around each CK edge.  D0 launches
// first, so the lower four D bits emit rise,rise,fall,fall in one 200M cycle.
// The serializer uses the same shifted 400M clock as CK to preserve phase.
OSERDESE3 #(
    .DATA_WIDTH                         (4                         ),
    .INIT                               (1'b0                      ),
    .IS_CLKDIV_INVERTED                 (1'b0                      ),
    .IS_CLK_INVERTED                    (1'b0                      ),
    .IS_RST_INVERTED                    (1'b0                      ),
    .SIM_DEVICE                         ("ULTRASCALE"              )
) U_oserdes (
    .OQ                                 (out_q                     ),
    .T_OUT                              (                          ),
    .CLK                                (clk_400m                  ),
    .CLKDIV                             (clk_200m                  ),
    .D                                  ({4'b0000, data_fall, data_fall, data_rise, data_rise}),
    .RST                                (~rst_n                    ),
    .T                                  (1'b0                      )
);

endmodule

module lpddr5_serdes_wck_1bit (
    input                               clk_200m                   ,
    input                               clk_400m                   ,
    input                               rst_n                      ,
    input                               run_en                     ,
    input                               phase                      ,
    output                              out_q
);

wire [7:0] wck_pattern;

// phase=0 emits 1,0,1,0; phase=1 emits 0,1,0,1. D0 launches first.
assign wck_pattern =
    (run_en == 1'b0) ? 8'b0000_0000 :
    (phase  == 1'b0) ? 8'b0000_0101 :
                       8'b0000_1010;

// WCK is launched as a 400 MHz forwarded strobe from explicit run and phase
// controls rather than exposing the serializer's raw four-bit pattern.
OSERDESE3 #(
    .DATA_WIDTH                         (4                         ),
    .INIT                               (1'b0                      ),
    .IS_CLKDIV_INVERTED                 (1'b0                      ),
    .IS_CLK_INVERTED                    (1'b0                      ),
    .IS_RST_INVERTED                    (1'b0                      ),
    .SIM_DEVICE                         ("ULTRASCALE"              )
) U_wck_oddr (
    .OQ                                 (out_q                     ),
    .T_OUT                              (                          ),
    .CLK                                (clk_400m                  ),
    .CLKDIV                             (clk_200m                  ),
    .D                                  (wck_pattern               ),
    .RST                                (~rst_n                    ),
    .T                                  (1'b0                      )
);

endmodule
