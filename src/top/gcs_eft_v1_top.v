`timescale 1ns / 1ps
`include "dram_driver_head.vh"

/**
 * gcs_eft_v1_top
 * Top-level module for the GCS EFT v1 test system.
 * Integrates clock management, UART, protocol controller, register bank,
 * LPDDR5 DUT interface, AD5272 rheostat, AD7606 ADC, PMIC and EEPROM
 * interfaces, watchdog timers, and an LED controller.
 */
module gcs_eft_v1_top (
    // LPDDR5 DUT1 interface
    output [ 6:0]  LP5_CA_A           ,
    inout  [ 1:0]  LP5_DMI_A          ,
    inout  [15:0]  LP5_DQ_A           ,
    output         LP5_CS0_A          ,
    output         LP5_RESET          ,
    output         EFT_LP5_CK_P_A     ,
    output         EFT_LP5_CK_N_A     ,
    inout          LP5_DQS0_P_A       ,
    inout          LP5_DQS0_N_A       ,
    inout          LP5_DQS1_P_A       ,
    inout          LP5_DQS1_N_A       ,
    output         LP5_WCK0_P_A       ,
    output         LP5_WCK0_N_A       ,
    output         LP5_WCK1_P_A       ,
    output         LP5_WCK1_N_A       ,

    // Board switch control
    output         G3VM_K1            ,
    output         G3VM_K3            ,
    output         G3VM_K5            ,
    output         G3VM_K7            ,
    output         G3VM_K1_OS         ,
    output         G3VM_K3_OS         ,
    output         G3VM_K5_OS         ,
    output         G3VM_K7_OS         ,
    output         G3VM_K15           ,
    output         G3VM_K16           ,

    // Force/high-side key control
    output         FH1_H_key          ,
    output         FH1_L_key          ,
    output         FH2_H_key          ,
    output         FH2_L_key          ,

    // ADC mux control
    output         ADC_MI_FH1_SLA1    ,
    output         ADC_MI_FH1_SLA0    ,
    output         ADC_MI_PM1_SA_SLA0 ,
    output         ADC_MI_PM1_SC_SLA0 ,
    output         ADC_MI_PM2_SC_SLA0 ,
    output         ADC_MI_PM2_SC_SLA1 ,
    output         ADC_MP2C_FH2_SLA2  ,
    output         ADC_MH_SLA2        ,
    output         ADC_MH_SLA1        ,
    output         ADC_MH_SLA0        ,

    // DUT signal power I2C
    inout          SDA_PW_DUTSIG      ,
    output         SCL_PW_DUTSIG      ,

    // System reset
    input          SYS_RESET_N        ,

    // UART
    output         EFT_UART0_TX       ,
    input          EFT_UART0_RX       ,

    // User LED
    output         LED_USER1          ,

    // AD7606 current ADC
    input          AD7606_DB8_DoutB   ,
    input          AD7606_DB7_DoutA   ,
    input          AD7606_BUSY        ,
    output         AD7606_CS          ,
    output         AD7606_RD_SCLK     ,
    output         AD7606_RESET       ,
    output         AD7606_WR          ,
    output         AD7606_CONVST_A    ,
    output [ 2:0]  AD7606_OS          ,

    output         EN_VPP_DUT         ,

    // Reference clocks
    input          Bank45_44_refclk_P ,
    input          Bank45_44_refclk_N ,

    // PMIC IRSP U67
    output wire    IRSP_U67_scl_o     ,
    inout  wire    IRSP_U67_sda_io    ,
    output         IRSP_U67_A_EN      ,
    output         IRSP_U67_B_EN      ,
    output         IRSP_U67_C_EN      ,
    output         IRSP_U67_D_EN      ,
    output         IRSP_U67_LDO_EN    ,

    // PMIC IRSP U68
    output wire    IRSP_U68_scl_o     ,
    inout  wire    IRSP_U68_sda_io    ,
    output         IRSP_U68_A_EN      ,
    output         IRSP_U68_B_EN      ,
    output         IRSP_U68_C_EN      ,
    output         IRSP_U68_D_EN      ,
    output         IRSP_U68_LDO_EN    ,
    output         IRSP_U68_PWR_EN    ,

    // Board reset outputs
    output         PWR_12V_RESET_DONE ,
    output         RESET_DONE         ,

    // EEPROM I2C
    output         EPROM_SCL          ,
    inout          EPROM_SDA
);

    // --------------------------------------------------------
    // Clock and reset
    // --------------------------------------------------------
    wire            w_clk_periph_40m            ;
    wire            w_clk_core_200m             ;
    wire            w_core_reset_n              ;
    wire            w_clk_lp5_dq_tx_400m        ;
    wire            w_clk_lp5_ca_wck_400m       ;
    wire            w_clk_lp5_dq_rx_400m        ;
    wire            w_lp5_serdes_reset_n        ;
    wire            w_lp5_idelayctrl_reset      ;
    wire            w_lp5_phy_ready             ;
    wire            rst_signal                  ;
    wire            rst_12v_signal              ;

    // --------------------------------------------------------
    // UART SIR bus
    // --------------------------------------------------------
    wire            proto_sir_sel               ;
    wire [ 15:0]    proto_sir_addr              ;
    wire            proto_sir_read              ;
    wire [ 95:0]    proto_sir_wdat              ;
    wire [ 95:0]    proto_sir_rdat              ;
    wire            proto_sir_dack              ;

    // --------------------------------------------------------
    // LPDDR5 test control
    // --------------------------------------------------------
    wire            lp5_init_start              ;
    wire            lp5_init_done               ;
    wire            lp5_init_fail               ;
    wire            lp5_gf_start                ;
    wire            lp5_gf_done                 ;

    // --------------------------------------------------------
    // LPDDR5 GF test status
    // --------------------------------------------------------
    wire [ 95:0]    lp5_gf_result               ;
    wire [ 95:0]    lp5_gf_aux_result           ;
    wire [ 63:0]    lp5_gf_err_block_msg        ;
    wire [  7:0]    lp5_gf_err_block_cnt        ;

    // --------------------------------------------------------
    // LPDDR5 IDD current test
    // --------------------------------------------------------
    wire            lp5_idd6_done               ;
    wire            lp5_idd6_start              ;
    wire [  9:0]    idd_en                      ;
    wire            idd_done                    ;
    wire [ 15:0]    x_ch1                       ;  // synchronized (200M core)
    wire [ 15:0]    x_ch2                       ;
    wire [ 15:0]    x_ch3                       ;
    wire [ 15:0]    x_ch4                       ;
    wire [ 15:0]    x_ch1_raw                   ;  // raw AD7606 output (40M peripheral)
    wire [ 15:0]    x_ch2_raw                   ;
    wire [ 15:0]    x_ch3_raw                   ;
    wire [ 15:0]    x_ch4_raw                   ;
    wire [ 15:0]    x_ch5                       ;
    wire [ 15:0]    x_ch6                       ;
    wire [ 15:0]    x_ch7                       ;
    wire [ 15:0]    x_ch8                       ;

    // --------------------------------------------------------
    // LPDDR5 init and calibration
    // --------------------------------------------------------
    wire [  7:0]    lp5_mr8_density             ;
    wire [143:0]    lp5_dq_delay_flat           ;
    wire [ 23:0]    mrw_r                       ;
    wire [  7:0]    read_capture_start_cnt      ;
    wire [  7:0]    gf_capture_start_cnt        ;
    wire [  3:0]    init_beat_offset            ;
    wire [  3:0]    gf_beat_offset              ;
    wire [  9:0]    gf_rd_wck_start_cnt         ;
    wire [  9:0]    gf_rd_wck_last_cnt          ;
    wire [  9:0]    gf_wr_wck_start_cnt         ;
    wire [  9:0]    gf_wr_wck_last_cnt          ;
    wire [  9:0]    gf_read_done_cnt            ;
    wire [  9:0]    gf_write_done_cnt           ;
    wire [  9:0]    gf_act_cmd_gap_cnt          ;
    wire [  9:0]    gf_rd_cmd_gap_cnt           ;
    wire [  9:0]    gf_wr_cmd_gap_cnt           ;
    wire [  9:0]    gf_pre_cmd_gap_cnt          ;
    wire [  2:0]    gf_refresh_batch_num        ;
    wire [  1:0]    gf_pattern_mode_cfg         ;
    wire [ 15:0]    lp5_rdc_err_bitmap          ;
    wire            lp5_rdc_check_valid         ;
    wire            lp5_rdc_check_pass          ;
    wire            lp5_rdc_train_init_en       ;
    wire            lp5_rdc_train_apply_best_cfg;
    wire            lp5_rdc_train_dual_pattern_cfg;
    wire [  3:0]    lp5_rdc_train_dq_start_cfg  ;
    wire [  3:0]    lp5_rdc_train_dq_end_cfg    ;
    wire [  8:0]    lp5_rdc_train_tap_start_cfg ;
    wire [  8:0]    lp5_rdc_train_tap_stop_cfg  ;
    wire [  8:0]    lp5_rdc_train_tap_step_cfg  ;
    wire            lp5_rdc_train_dq_delay_l_we ;
    wire            lp5_rdc_train_dq_delay_h_we ;
    wire [ 95:0]    lp5_rdc_train_dq_delay_wdat ;
    wire [  3:0]    lp5_rdc_train_state         ;
    wire            lp5_rdc_train_busy          ;
    wire            lp5_rdc_train_done          ;
    wire            lp5_rdc_train_apply_best    ;
    wire [  3:0]    lp5_rdc_train_dq_start      ;
    wire [  8:0]    lp5_rdc_train_tap           ;
    wire [  9:0]    lp5_rdc_train_best_len      ;
    wire [ 15:0]    lp5_rdc_train_pass_mask     ;
    wire [ 15:0]    lp5_rdc_train_fail_mask     ;
    wire [ 15:0]    lp5_rdc_train_last_err      ;
    wire            lp5_rdc_train_init_ready    ;
    wire            lp5_rdc_train_pass_all      ;
    wire [143:0]    lp5_rdc_train_best_flat     ;
    wire [143:0]    lp5_rdc_train_left_flat     ;
    wire [143:0]    lp5_rdc_train_right_flat    ;
    wire [  8:0]    lp5_rdc_train_scan_tap_sel ;
    wire [ 15:0]    lp5_rdc_train_scan_pass_bitmap;

    // --------------------------------------------------------
    // AD5272 control
    // --------------------------------------------------------
    wire            ad5272_2_entry              ;
    wire [  1:0]    ad5272_2_read_addr          ;
    wire [  1:0]    ad5272_2_write_addr         ;
    wire [  3:0]    ad5272_2_write_cmd          ;
    wire [  9:0]    ad5272_2_write_data         ;
    wire            ad5272_done_2               ;

    // --------------------------------------------------------
    // AD7606 current ADC raw outputs (40M peripheral domain)
    // --------------------------------------------------------
    wire [ 15:0]    ad_ch1_raw                  ;
    wire [ 15:0]    ad_ch2_raw                  ;
    wire [ 15:0]    ad_ch3_raw                  ;
    wire [ 15:0]    ad_ch4_raw                  ;
    wire [ 15:0]    ad_ch5_raw                  ;
    wire [ 15:0]    ad_ch6_raw                  ;
    wire [ 15:0]    ad_ch7_raw                  ;
    wire [ 15:0]    ad_ch8_raw                  ;
    wire            idelayctrl_ready            ;
    wire            ad_done_raw                 ;

    // AD7606 synchronized outputs (200M core domain)
    wire [ 15:0]    ad_ch1                      ;
    wire [ 15:0]    ad_ch2                      ;
    wire [ 15:0]    ad_ch3                      ;
    wire [ 15:0]    ad_ch4                      ;
    wire [ 15:0]    ad_ch5                      ;
    wire [ 15:0]    ad_ch6                      ;
    wire [ 15:0]    ad_ch7                      ;
    wire [ 15:0]    ad_ch8                      ;
    wire            ad_done                     ;

    // --------------------------------------------------------
    // PMIC IRSP control
    // --------------------------------------------------------
    wire [ 15:0]    IRSP_U67_data_out_o         ;
    wire [ 15:0]    IRSP_U68_data_out_o         ;
    wire [  6:0]    IRSP_IIC_DEVICE_ADDR        ;
    wire            IRSP_U67_data_bit_ctrl      ;
    wire            IRSP_U67_send_byte_ctrl     ;
    wire            IRSP_U68_data_bit_ctrl      ;
    wire            IRSP_U68_send_byte_ctrl     ;
    wire [ 63:0]    IRSP_U67_value              ;
    wire [ 63:0]    IRSP_U68_value              ;

    // --------------------------------------------------------
    // EEPROM control
    // --------------------------------------------------------
    wire [ 15:0]    EEPROM_data_out_o           ;
    wire            EEPROM_data_bit_ctrl        ;
    wire            EEPROM_send_byte_ctrl       ;
    wire [ 63:0]    EEPROM_value                ;

    // --------------------------------------------------------
    // OS test control
    // --------------------------------------------------------
    wire            os_start                    ;
    wire            os_done                     ;
    wire [ 31:0]    os_result                   ;
    wire [ 15:0]    os_vdd2l_threshold          ;
    wire [ 15:0]    os_vddq_threshold           ;
    wire [ 15:0]    os_vdd2h_threshold          ;
    wire [ 15:0]    os_vdd1_threshold           ;
    wire [ 15:0]    os_adc_ch5_threshold        ;
    wire [ 15:0]    os_adc_ch6_threshold        ;
    wire [ 15:0]    os_adc_ch7_threshold        ;
    wire [ 15:0]    os_adc_ch8_threshold        ;

    // --------------------------------------------------------
    // Static PMIC enable assignments
    // --------------------------------------------------------
    assign IRSP_U67_A_EN   = 1'b1;
    assign IRSP_U67_B_EN   = 1'b1;
    assign IRSP_U67_C_EN   = 1'b1;
    assign IRSP_U67_D_EN   = 1'b1;
    assign IRSP_U67_LDO_EN = 1'b1;
    assign IRSP_U68_A_EN   = 1'b1;
    assign IRSP_U68_B_EN   = 1'b1;
    assign IRSP_U68_C_EN   = 1'b1;
    assign IRSP_U68_D_EN   = 1'b1;
    assign IRSP_U68_LDO_EN = 1'b1;
    assign IRSP_U68_PWR_EN = 1'b1;

    // --------------------------------------------------------
    // Clock management (PLL)
    // --------------------------------------------------------
    clock_manage_top clock_manage_top_u0 (
    .i_sys_clk_p                        (Bank45_44_refclk_P        ),
    .i_sys_clk_n                        (Bank45_44_refclk_N        ),
    .i_reset                            (~SYS_RESET_N              ),
    .i_idelayctrl_ready                 (idelayctrl_ready          ),
    .o_clk_periph_40m                   (w_clk_periph_40m          ),
    .o_clk_core_200m                    (w_clk_core_200m           ),
    .o_core_reset_n                     (w_core_reset_n            ),
    .o_clk_lp5_dq_tx_400m               (w_clk_lp5_dq_tx_400m      ),
    .o_clk_lp5_ca_wck_400m              (w_clk_lp5_ca_wck_400m     ),
    .o_clk_lp5_dq_rx_400m               (w_clk_lp5_dq_rx_400m      ),
    .o_lp5_serdes_reset_n               (w_lp5_serdes_reset_n      ),
    .o_lp5_idelayctrl_reset             (w_lp5_idelayctrl_reset    ),
    .o_lp5_phy_ready                    (w_lp5_phy_ready           ),
    .o_mmcm_locked                      (                          )
    );

    // --------------------------------------------------------
    // UART physical layer and protocol
    // --------------------------------------------------------
    uart_top
    #(
    .BPS_SEL                            (32'd115200                ),
    .FIFO_PROG_FULL                     (17'd131008                )
    )
    uart_top_u0 (
    .clk                                (w_clk_core_200m          ),
    .rst_n                              (w_core_reset_n            ),
    .uart_rx                            (EFT_UART0_RX              ),
    .uart_tx                            (EFT_UART0_TX              ),
    .sir_sel                            (proto_sir_sel             ),
    .sir_addr                           (proto_sir_addr            ),
    .sir_read                           (proto_sir_read            ),
    .sir_wdat                           (proto_sir_wdat            ),
    .sir_rdat                           (proto_sir_rdat            ),
    .sir_dack                           (proto_sir_dack            )
    );

    // --------------------------------------------------------
    // Register bank (SIR bus slave)
    // --------------------------------------------------------
    bar u_bar (
        .clk                       (w_clk_core_200m             ),
        .rst_n                     (w_core_reset_n              ),
        .sir_sel                   (proto_sir_sel               ),
        .sir_addr                  (proto_sir_addr              ),
        .sir_read                  (proto_sir_read              ),
        .sir_wdat                  (proto_sir_wdat              ),
        .sir_rdat                  (proto_sir_rdat              ),
        .sir_dack                  (proto_sir_dack              ),

        .ad5272_2_entry            (ad5272_2_entry              ),
        .ad5272_2_read_addr        (ad5272_2_read_addr          ),
        .ad5272_2_read_data        (10'h0                       ),
        .ad5272_2_write_addr       (ad5272_2_write_addr         ),
        .ad5272_2_write_cmd        (ad5272_2_write_cmd          ),
        .ad5272_2_write_data       (ad5272_2_write_data         ),

        .irsp_u67_value            (IRSP_U67_value              ),
        .irsp_u67_send_byte_ctrl   (IRSP_U67_send_byte_ctrl     ),
        .irsp_u67_data_bit_ctrl    (IRSP_U67_data_bit_ctrl      ),
        .irsp_u67_data_out         (IRSP_U67_data_out_o         ),
        .irsp_u68_value            (IRSP_U68_value              ),
        .irsp_u68_send_byte_ctrl   (IRSP_U68_send_byte_ctrl     ),
        .irsp_u68_data_bit_ctrl    (IRSP_U68_data_bit_ctrl      ),
        .irsp_u68_data_out         (IRSP_U68_data_out_o         ),
        .irsp_iic_device_addr      (IRSP_IIC_DEVICE_ADDR        ),

        .eeprom_value              (EEPROM_value                ),
        .eeprom_send_byte_ctrl     (EEPROM_send_byte_ctrl       ),
        .eeprom_data_bit_ctrl      (EEPROM_data_bit_ctrl        ),
        .eeprom_data_out           (EEPROM_data_out_o           ),

        .dut_init_start            (lp5_init_start              ),
        .dut_init_done             (lp5_init_done               ),
        .dut_init_fail             (lp5_init_fail               ),
        .dut_mr8_density           (lp5_mr8_density             ),
        .dut_idd6_start            (lp5_idd6_start              ),
        .dut_idd6_done             (lp5_idd6_done               ),
        .dut_idd6_result           ({x_ch4, x_ch3, x_ch2, x_ch1}),
        .gf_start                  (lp5_gf_start                ),
        .gf_done                   (lp5_gf_done                 ),
        .gf_result                 (lp5_gf_result               ),
        .gf_aux_result             (lp5_gf_aux_result           ),
        .gf_bad_block_info         ({32'h0, lp5_gf_err_block_msg}),
        .gf_bad_block_count        (lp5_gf_err_block_cnt        ),

        .gf_clk_sel                (                            ),
        .gf_addr_start             (                            ),
        .gf_addr_end               (                            ),
        .dut_dq_delay_flat         (lp5_dq_delay_flat           ),

        .mrw_r                     (mrw_r                       ),
        .read_capture_start_cnt    (read_capture_start_cnt      ),
        .gf_capture_start_cnt      (gf_capture_start_cnt        ),
        .init_beat_offset          (init_beat_offset            ),
        .gf_beat_offset            (gf_beat_offset              ),
        .gf_rd_wck_start_cnt       (gf_rd_wck_start_cnt         ),
        .gf_rd_wck_last_cnt        (gf_rd_wck_last_cnt          ),
        .gf_wr_wck_start_cnt       (gf_wr_wck_start_cnt         ),
        .gf_wr_wck_last_cnt        (gf_wr_wck_last_cnt          ),
        .gf_read_done_cnt          (gf_read_done_cnt            ),
        .gf_write_done_cnt         (gf_write_done_cnt           ),
        .gf_act_cmd_gap_cnt        (gf_act_cmd_gap_cnt          ),
        .gf_rd_cmd_gap_cnt         (gf_rd_cmd_gap_cnt           ),
        .gf_wr_cmd_gap_cnt         (gf_wr_cmd_gap_cnt           ),
        .gf_pre_cmd_gap_cnt        (gf_pre_cmd_gap_cnt          ),
        .gf_refresh_batch_num      (gf_refresh_batch_num        ),
        .gf_pattern_mode_cfg       (gf_pattern_mode_cfg         ),
        .rdc_err_bitmap            (lp5_rdc_err_bitmap          ),
        .rdc_check_valid           (lp5_rdc_check_valid         ),
        .rdc_check_pass            (lp5_rdc_check_pass          ),
        .rdc_train_init_en         (lp5_rdc_train_init_en       ),
        .rdc_train_apply_best_cfg  (lp5_rdc_train_apply_best_cfg),
        .rdc_train_dual_pattern_cfg(lp5_rdc_train_dual_pattern_cfg),
        .rdc_train_dq_start_cfg    (lp5_rdc_train_dq_start_cfg  ),
        .rdc_train_dq_end_cfg      (lp5_rdc_train_dq_end_cfg    ),
        .rdc_train_tap_start_cfg   (lp5_rdc_train_tap_start_cfg ),
        .rdc_train_tap_stop_cfg    (lp5_rdc_train_tap_stop_cfg  ),
        .rdc_train_tap_step_cfg    (lp5_rdc_train_tap_step_cfg  ),
        .rdc_train_dq_delay_l_we   (lp5_rdc_train_dq_delay_l_we ),
        .rdc_train_dq_delay_h_we   (lp5_rdc_train_dq_delay_h_we ),
        .rdc_train_dq_delay_wdat   (lp5_rdc_train_dq_delay_wdat ),
        .rdc_train_scan_tap_sel    (lp5_rdc_train_scan_tap_sel  ),
        .rdc_train_state           (lp5_rdc_train_state         ),
        .rdc_train_busy            (lp5_rdc_train_busy          ),
        .rdc_train_done            (lp5_rdc_train_done          ),
        .rdc_train_apply_best      (lp5_rdc_train_apply_best    ),
        .rdc_train_dq_start        (lp5_rdc_train_dq_start      ),
        .rdc_train_tap             (lp5_rdc_train_tap           ),
        .rdc_train_status_best_len (lp5_rdc_train_best_len      ),
        .rdc_train_pass_mask       (lp5_rdc_train_pass_mask     ),
        .rdc_train_fail_mask       (lp5_rdc_train_fail_mask     ),
        .rdc_train_last_err_bitmap (lp5_rdc_train_last_err      ),
        .rdc_train_init_ready      (lp5_rdc_train_init_ready    ),
        .rdc_train_pass_all        (lp5_rdc_train_pass_all      ),
        .rdc_train_best_flat       (lp5_rdc_train_best_flat     ),
        .rdc_train_left_flat       (lp5_rdc_train_left_flat     ),
        .rdc_train_right_flat      (lp5_rdc_train_right_flat    ),
        .rdc_train_scan_pass_bitmap(lp5_rdc_train_scan_pass_bitmap),

        .os_start                  (os_start                    ),
        .os_done                   (os_done                     ),
        .os_result                 (os_result                   ),
        .vdd2l_uth                 (os_vdd2l_threshold          ),
        .vddq_uth                  (os_vddq_threshold           ),
        .vdd2h_uth                 (os_vdd2h_threshold          ),
        .vdd1_uth                  (os_vdd1_threshold           ),
        .adc_ch5_uth               (os_adc_ch5_threshold        ),
        .adc_ch6_uth               (os_adc_ch6_threshold        ),
        .adc_ch7_uth               (os_adc_ch7_threshold        ),
        .adc_ch8_uth               (os_adc_ch8_threshold        ),

        .g3vm_k1                   (G3VM_K1                     ),
        .g3vm_k3                   (G3VM_K3                     ),
        .g3vm_k5                   (G3VM_K5                     ),
        .g3vm_k7                   (G3VM_K7                     ),
        .g3vm_k15                  (G3VM_K15                    ),
        .g3vm_k16                  (G3VM_K16                    ),
        .adc_mi_pm1_sa_sla0        (ADC_MI_PM1_SA_SLA0          ),
        .adc_mi_pm1_sc_sla0        (ADC_MI_PM1_SC_SLA0          ),
        .adc_mi_pm2_sc_sla0        (ADC_MI_PM2_SC_SLA0          ),
        .adc_mi_pm2_sc_sla1        (ADC_MI_PM2_SC_SLA1          ),
        .adc_mp2c_fh2_sla2         (ADC_MP2C_FH2_SLA2           ),
        .adc_mi_fh1_sla0           (ADC_MI_FH1_SLA0             ),
        .adc_mi_fh1_sla1           (ADC_MI_FH1_SLA1             ),
        .fh1_h_key                 (FH1_H_key                   ),
        .fh1_l_key                 (FH1_L_key                   ),
        .fh2_h_key                 (FH2_H_key                   ),
        .fh2_l_key                 (FH2_L_key                   ),
        .adc_mh_sla2               (ADC_MH_SLA2                 ),
        .adc_mh_sla1               (ADC_MH_SLA1                 ),
        .adc_mh_sla0               (ADC_MH_SLA0                 ),
        .en_vpp_dut                (EN_VPP_DUT                  ),
        .rst_signal                (rst_signal                  ),
        .rst_12v_signal            (rst_12v_signal              )
    );

    // --------------------------------------------------------
    // IDD test signal control
    // --------------------------------------------------------
    idd_signal_ctrl idd_signal_ctrl_inst (
        .sys_clk         (w_clk_core_200m ),
        .rst_n           (w_core_reset_n  ),
        .dut1_idd6_en_i  (lp5_idd6_start  ),
        .dut1_idd6_done_o(lp5_idd6_done   ),
        .dut1_idd_en     (idd_en          ),
        .dut1_idd_done   (idd_done        )
    );

    // --------------------------------------------------------
    // Oscilloscope / voltage monitor controller
    // --------------------------------------------------------
    os_ctrl u_os_ctrl (
        .clk         (w_clk_core_200m),
        .rst_n       (w_core_reset_n ),
        .os_start    (os_start    ),
        .os_done     (os_done     ),
        .os_result   (os_result   ),
        .ad_done     (ad_done     ),
        .ADC_CH8_U   (ad_ch8      ),
        .ADC_CH7_U   (ad_ch7      ),
        .ADC_CH6_U   (ad_ch6      ),
        .ADC_CH5_U   (ad_ch5      ),
        .VDD2L_U     (ad_ch4      ),
        .VDDQ_U      (ad_ch3      ),
        .VDD2H_U     (ad_ch2      ),
        .VDD1_U      (ad_ch1      ),
        .G3VM_K7_OS  (G3VM_K7_OS  ),
        .G3VM_K1_OS  (G3VM_K1_OS  ),
        .G3VM_K3_OS  (G3VM_K3_OS  ),
        .G3VM_K5_OS  (G3VM_K5_OS  ),
        .VDD2L_Uth   (os_vdd2l_threshold   ),
        .VDDQ_Uth    (os_vddq_threshold    ),
        .VDD2H_Uth   (os_vdd2h_threshold   ),
        .VDD1_Uth    (os_vdd1_threshold    ),
        .ADC_CH5_Uth (os_adc_ch5_threshold ),
        .ADC_CH6_Uth (os_adc_ch6_threshold ),
        .ADC_CH7_Uth (os_adc_ch7_threshold ),
        .ADC_CH8_Uth (os_adc_ch8_threshold )
    );

    // --------------------------------------------------------
    // AD5272 digital rheostat (DUT signal power)
    // --------------------------------------------------------
    ad5272_new ad5272_new_2 (
        .sys_clk       (w_clk_core_200m        ),
        .locked        (w_core_reset_n         ),
        .scl           (SCL_PW_DUTSIG          ),
        .sda           (SDA_PW_DUTSIG          ),
        .ad5272_en     (ad5272_2_entry         ),
        .Read_Addr     (ad5272_2_read_addr     ),
        .Read_Data     (10'h0                  ),
        .Write_Addr    (ad5272_2_write_addr    ),
        .Write_Command (ad5272_2_write_cmd     ),
        .Write_Data    (ad5272_2_write_data    ),
        .ad5272_done   (ad5272_done_2          )
    );

    // --------------------------------------------------------
    // AD7606 8-channel current/voltage ADC
    // --------------------------------------------------------
    ad7606_new ad7606_new (
        .sys_clk         (w_clk_periph_40m    ),
        .ad_busy         (AD7606_BUSY         ),
        .ad_dataA        (AD7606_DB7_DoutA    ),
        .ad_dataB        (AD7606_DB8_DoutB    ),
        .ad_os           (AD7606_OS           ),
        .ad_rst          (AD7606_RESET        ),
        .ad_cvAB         (AD7606_CONVST_A     ),
        .ad_wr           (AD7606_WR           ),
        .ad_cs_n         (AD7606_CS           ),
        .ad_sclk         (AD7606_RD_SCLK      ),
        .x_ch1           (x_ch1_raw           ),
        .x_ch2           (x_ch2_raw           ),
        .x_ch3           (x_ch3_raw           ),
        .x_ch4           (x_ch4_raw           ),
        .x_ch5           (x_ch5               ),
        .x_ch6           (x_ch6               ),
        .x_ch7           (x_ch7               ),
        .x_ch8           (x_ch8               ),
        .ad_done         (ad_done_raw         ),
        .ad_ch1          (ad_ch1_raw          ),
        .ad_ch2          (ad_ch2_raw          ),
        .ad_ch3          (ad_ch3_raw          ),
        .ad_ch4          (ad_ch4_raw          ),
        .ad_ch5          (ad_ch5_raw          ),
        .ad_ch6          (ad_ch6_raw          ),
        .ad_ch7          (ad_ch7_raw          ),
        .ad_ch8          (ad_ch8_raw          )
    );

    // --------------------------------------------------------
    // ADC clock-domain-crossing synchronizer (40 MHz -> 200 MHz)
    // --------------------------------------------------------
    adc_cdc_sync u_adc_cdc_sync (
        .clk_dst     (w_clk_core_200m),
        .rst_n       (w_core_reset_n ),
        // Raw inputs (40M peripheral domain)
        .ad_done_i   (ad_done_raw    ),
        .ad_ch1_i    (ad_ch1_raw     ),
        .ad_ch2_i    (ad_ch2_raw     ),
        .ad_ch3_i    (ad_ch3_raw     ),
        .ad_ch4_i    (ad_ch4_raw     ),
        .ad_ch5_i    (ad_ch5_raw     ),
        .ad_ch6_i    (ad_ch6_raw     ),
        .ad_ch7_i    (ad_ch7_raw     ),
        .ad_ch8_i    (ad_ch8_raw     ),
        .x_ch1_i     (x_ch1_raw      ),
        .x_ch2_i     (x_ch2_raw      ),
        .x_ch3_i     (x_ch3_raw      ),
        .x_ch4_i     (x_ch4_raw      ),
        // Synchronized outputs (200M core domain)
        .ad_done_o   (ad_done        ),
        .ad_ch1_o    (ad_ch1         ),
        .ad_ch2_o    (ad_ch2         ),
        .ad_ch3_o    (ad_ch3         ),
        .ad_ch4_o    (ad_ch4         ),
        .ad_ch5_o    (ad_ch5         ),
        .ad_ch6_o    (ad_ch6         ),
        .ad_ch7_o    (ad_ch7         ),
        .ad_ch8_o    (ad_ch8         ),
        .x_ch1_o     (x_ch1          ),
        .x_ch2_o     (x_ch2          ),
        .x_ch3_o     (x_ch3          ),
        .x_ch4_o     (x_ch4          )
    );

    // --------------------------------------------------------
    // LPDDR5 DUT controller (channel A only)
    // --------------------------------------------------------
    lpddr5_dut1 lpddr5_dut1 (
        .i_clk_core_200m        (w_clk_core_200m               ),
        .i_clk_dq_tx_400m       (w_clk_lp5_dq_tx_400m          ),
        .i_clk_ca_wck_400m      (w_clk_lp5_ca_wck_400m         ),
        .i_clk_dq_rx_400m       (w_clk_lp5_dq_rx_400m          ),
        .i_serdes_reset_n       (w_lp5_serdes_reset_n          ),
        .rst_n_in               (w_lp5_phy_ready               ),
        .reset_n_a              (LP5_RESET                     ),
        .GF_total_en            (lp5_gf_start                  ),
        .GF_total_done          (lp5_gf_done                   ),
        .GF_result_data         (lp5_gf_result                 ),
        .GF_fail_aux_result     (lp5_gf_aux_result             ),
        .ck_t_a                 (EFT_LP5_CK_P_A                ),
        .ck_c_a                 (EFT_LP5_CK_N_A                ),
        .cs0_a                  (LP5_CS0_A                     ),
        .ca_a                   (LP5_CA_A                      ),
        .dq_a                   (LP5_DQ_A                      ),
        .wck_t_a                ({LP5_WCK1_P_A, LP5_WCK0_P_A}  ),
        .wck_c_a                ({LP5_WCK1_N_A, LP5_WCK0_N_A}  ),
        .rdqs_t_a               ({LP5_DQS1_P_A, LP5_DQS0_P_A}  ),
        .rdqs_c_a               ({LP5_DQS1_N_A, LP5_DQS0_N_A}  ),
        .dmi_a                  (LP5_DMI_A                     ),
        .init_en                (lp5_init_start                ),
        .init_done              (lp5_init_done                 ),
        .init_fail              (lp5_init_fail                 ),
        .mrw_r                  (mrw_r                         ),
        .idd_en                 (idd_en                        ),
        .idd_done               (idd_done                      ),
        .read_capture_start_cnt (read_capture_start_cnt        ),
        .gf_capture_start_cnt   (gf_capture_start_cnt          ),
        .init_beat_offset       (init_beat_offset              ),
        .gf_beat_offset         (gf_beat_offset                ),
        .gf_rd_wck_start_cnt    (gf_rd_wck_start_cnt           ),
        .gf_rd_wck_last_cnt     (gf_rd_wck_last_cnt            ),
        .gf_wr_wck_start_cnt    (gf_wr_wck_start_cnt           ),
        .gf_wr_wck_last_cnt     (gf_wr_wck_last_cnt            ),
        .gf_read_done_cnt       (gf_read_done_cnt              ),
        .gf_write_done_cnt      (gf_write_done_cnt             ),
        .gf_act_cmd_gap_cnt     (gf_act_cmd_gap_cnt            ),
        .gf_rd_cmd_gap_cnt      (gf_rd_cmd_gap_cnt             ),
        .gf_wr_cmd_gap_cnt      (gf_wr_cmd_gap_cnt             ),
        .gf_pre_cmd_gap_cnt     (gf_pre_cmd_gap_cnt            ),
        .gf_refresh_batch_num   (gf_refresh_batch_num          ),
        .gf_pattern_mode_cfg    (gf_pattern_mode_cfg           ),
        .RDY                    (idelayctrl_ready              ),
        .delay_value_dq_a       (lp5_dq_delay_flat             ),
        .die_message            (lp5_mr8_density               ),
        .err_block_cnt          (lp5_gf_err_block_cnt          ),
        .err_block_message      (lp5_gf_err_block_msg          ),
        .rdc_err_bitmap         (lp5_rdc_err_bitmap            ),
        .rdc_check_valid        (lp5_rdc_check_valid           ),
        .rdc_check_pass         (lp5_rdc_check_pass            ),
        .rdc_train_init_en      (lp5_rdc_train_init_en         ),
        .rdc_train_apply_best_cfg(lp5_rdc_train_apply_best_cfg ),
        .rdc_train_dual_pattern_cfg(lp5_rdc_train_dual_pattern_cfg),
        .rdc_train_dq_start_cfg (lp5_rdc_train_dq_start_cfg    ),
        .rdc_train_dq_end_cfg   (lp5_rdc_train_dq_end_cfg      ),
        .rdc_train_tap_start_cfg(lp5_rdc_train_tap_start_cfg   ),
        .rdc_train_tap_stop_cfg (lp5_rdc_train_tap_stop_cfg    ),
        .rdc_train_tap_step_cfg (lp5_rdc_train_tap_step_cfg    ),
        .rdc_train_dq_delay_l_we(lp5_rdc_train_dq_delay_l_we   ),
        .rdc_train_dq_delay_h_we(lp5_rdc_train_dq_delay_h_we   ),
        .rdc_train_dq_delay_wdat(lp5_rdc_train_dq_delay_wdat   ),
        .rdc_train_scan_tap_sel (lp5_rdc_train_scan_tap_sel    ),
        .rdc_train_state        (lp5_rdc_train_state           ),
        .rdc_train_busy         (lp5_rdc_train_busy            ),
        .rdc_train_done         (lp5_rdc_train_done            ),
        .rdc_train_apply_best   (lp5_rdc_train_apply_best      ),
        .rdc_train_dq_start     (lp5_rdc_train_dq_start        ),
        .rdc_train_tap          (lp5_rdc_train_tap             ),
        .rdc_train_status_best_len(lp5_rdc_train_best_len      ),
        .rdc_train_pass_mask    (lp5_rdc_train_pass_mask       ),
        .rdc_train_fail_mask    (lp5_rdc_train_fail_mask       ),
        .rdc_train_last_err_bitmap(lp5_rdc_train_last_err      ),
        .rdc_train_init_ready   (lp5_rdc_train_init_ready      ),
        .rdc_train_pass_all     (lp5_rdc_train_pass_all        ),
        .rdc_train_best_flat    (lp5_rdc_train_best_flat       ),
        .rdc_train_left_flat    (lp5_rdc_train_left_flat       ),
        .rdc_train_right_flat   (lp5_rdc_train_right_flat      ),
        .rdc_train_scan_pass_bitmap(lp5_rdc_train_scan_pass_bitmap)
    );

    // --------------------------------------------------------
    // IDELAYCTRL for LPDDR5 PHY
    // --------------------------------------------------------
    IDELAYCTRL
    #(
        .SIM_DEVICE ("ULTRASCALE")
    )
    IDELAYCTRL_inst (
        .RDY    (idelayctrl_ready ),
        .REFCLK (w_clk_core_200m),
        .RST    (w_lp5_idelayctrl_reset)
    );

    // --------------------------------------------------------
    // LED controller (heartbeat)
    // --------------------------------------------------------
    eft3_led_ctrl_top
    #(
        .TIME_uS (200)
    )
    led_ctrl_top (
        .s_clk_i  (w_clk_core_200m),
        .s_rstn_i (w_core_reset_n ),
        .led      (LED_USER1)
    );

    // --------------------------------------------------------
    // Watchdog: 12V power rail reset sequence
    // --------------------------------------------------------
    watchdog u_12v_watchdog (
        .sys_clk    (w_clk_core_200m       ),
        .sys_rst_n  (w_core_reset_n        ),
        .rst_signal (rst_12v_signal        ),
        .done       (PWR_12V_RESET_DONE    )
    );

    // --------------------------------------------------------
    // Watchdog: general reset sequence
    // --------------------------------------------------------
    watchdog u2_watchdog (
        .sys_clk    (w_clk_core_200m),
        .sys_rst_n  (w_core_reset_n ),
        .rst_signal (rst_signal     ),
        .done       (RESET_DONE     )
    );

    // --------------------------------------------------------
    // PMIC IRSP5401 x2 (U67 / U68)
    // --------------------------------------------------------
    pmic_irsp5401x2 u_PMIC_IRSP5401x2 (
        .clk                     (w_clk_core_200m            ),
        .rst_n                   (w_core_reset_n             ),
        .IRSP_U67_send_byte_ctrl (IRSP_U67_send_byte_ctrl    ),
        .IRSP_U67_data_bit_ctrl  (IRSP_U67_data_bit_ctrl     ),
        .IRSP_U68_send_byte_ctrl (IRSP_U68_send_byte_ctrl    ),
        .IRSP_U68_data_bit_ctrl  (IRSP_U68_data_bit_ctrl     ),
        .IRSP_IIC_DEVICE_ADDR    (IRSP_IIC_DEVICE_ADDR       ),
        .IRSP_U67_value          (IRSP_U67_value             ),
        .IRSP_U68_value          (IRSP_U68_value             ),
        .IRSP_U67_scl_o          (IRSP_U67_scl_o             ),
        .IRSP_U67_sda_io         (IRSP_U67_sda_io            ),
        .IRSP_U67_data_out_o     (IRSP_U67_data_out_o        ),
        .IRSP_U67_data_out_valid (                           ),
        .IRSP_U68_scl_o          (IRSP_U68_scl_o             ),
        .IRSP_U68_sda_io         (IRSP_U68_sda_io            ),
        .IRSP_U68_data_out_o     (IRSP_U68_data_out_o        ),
        .IRSP_U68_data_out_valid (                           )
    );

    // --------------------------------------------------------
    // EEPROM (AT24LC64) interface
    // --------------------------------------------------------
    eft1_at24lc64_top u_eft1_at24lc64_top (
        .clk                   (w_clk_core_200m          ),
        .rst_n                 (w_core_reset_n           ),
        .EEPROM_send_byte_ctrl (EEPROM_send_byte_ctrl    ),
        .EEPROM_data_bit_ctrl  (EEPROM_data_bit_ctrl     ),
        .EEPROM_value          (EEPROM_value             ),
        .EEPROM_scl_o          (EPROM_SCL                ),
        .EEPROM_sda_io         (EPROM_SDA                ),
        .EEPROM_data_out_o     (EEPROM_data_out_o        ),
        .EEPROM_data_out_valid (                         )
    );

endmodule
