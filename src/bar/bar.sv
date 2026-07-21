/**
 * bar
 * Top-level register / control aggregator.
 * Routes an SIR-like parallel bus to multiple functional sub-modules:
 *   - bar00 : System identification / scratch
 *   - bar03 : Peripheral control (AD5272, IRSP, EEPROM, power switches)
 *   - bar04 : DUT initialization and IDD6
 *   - bar05 : GF test control and result collection
 *   - bar06 : DUT timing / calibration parameters
 *   - bar07 : Oscilloscope / voltage threshold control
 */
module bar (
    // Clock and reset
    input  wire                 clk                         ,
    input  wire                 rst_n                       ,

    // SIR bus (host interface)
    input  wire                 sir_sel                     ,
    input  wire [15:0]          sir_addr                    ,
    input  wire                 sir_read                    ,
    input  wire [95:0]          sir_wdat                    ,
    output wire [95:0]          sir_rdat                    ,
    output wire                 sir_dack                    ,

    // AD5272 digital rheostat
    output wire                 ad5272_2_entry              ,
    output wire [ 1:0]          ad5272_2_read_addr          ,
    input  wire [ 9:0]          ad5272_2_read_data          ,
    output wire [ 1:0]          ad5272_2_write_addr         ,
    output wire [ 3:0]          ad5272_2_write_cmd          ,
    output wire [ 9:0]          ad5272_2_write_data         ,

    // IRSP / IIC configuration interfaces
    output wire [63:0]          irsp_u67_value              ,
    output wire                 irsp_u67_send_byte_ctrl     ,
    output wire                 irsp_u67_data_bit_ctrl      ,
    input  wire [15:0]          irsp_u67_data_out           ,
    output wire [63:0]          irsp_u68_value              ,
    output wire                 irsp_u68_send_byte_ctrl     ,
    output wire                 irsp_u68_data_bit_ctrl      ,
    input  wire [15:0]          irsp_u68_data_out           ,
    output wire [ 6:0]          irsp_iic_device_addr        ,

    // EEPROM interface
    output wire [63:0]          eeprom_value                ,
    output wire                 eeprom_send_byte_ctrl       ,
    output wire                 eeprom_data_bit_ctrl        ,
    input  wire [15:0]          eeprom_data_out             ,

    // DUT initialization / IDD6 / GF test
    output wire                 dut_init_start              ,
    input  wire                 dut_init_done               ,
    input  wire                 dut_init_fail               ,
    input  wire [ 7:0]          dut_mr8_density             ,
    output wire                 dut_idd6_start              ,
    input  wire                 dut_idd6_done               ,
    input  wire [63:0]          dut_idd6_result             ,
    output wire                 gf_start                    ,
    input  wire                 gf_done                     ,
    input  wire [95:0]          gf_result                   ,
    input  wire [95:0]          gf_aux_result               ,
    input  wire [95:0]          gf_bad_block_info           ,
    input  wire [ 7:0]          gf_bad_block_count          ,

    // DUT algorithm / timing / calibration
    output wire [15:0]          gf_clk_sel                  ,
    output wire [55:0]          gf_addr_start               ,
    output wire [55:0]          gf_addr_end                 ,
    input  wire [143:0]         dut_dq_delay_flat           ,
    output wire [23:0]          mrw_r                       ,
    output wire [ 7:0]          read_capture_start_cnt      ,
    output wire [ 7:0]          gf_capture_start_cnt        ,
    output wire [ 3:0]          init_beat_offset            ,
    output wire [ 3:0]          gf_beat_offset              ,
    output wire [ 9:0]          gf_rd_wck_start_cnt         ,
    output wire [ 9:0]          gf_rd_wck_last_cnt          ,
    output wire [ 9:0]          gf_wr_wck_start_cnt         ,
    output wire [ 9:0]          gf_wr_wck_last_cnt          ,
    output wire [ 9:0]          gf_read_done_cnt            ,
    output wire [ 9:0]          gf_write_done_cnt           ,
    output wire [ 9:0]          gf_act_cmd_gap_cnt          ,
    output wire [ 9:0]          gf_rd_cmd_gap_cnt           ,
    output wire [ 9:0]          gf_wr_cmd_gap_cnt           ,
    output wire [ 9:0]          gf_pre_cmd_gap_cnt          ,
    output wire [ 2:0]          gf_refresh_batch_num        ,
    output wire [ 1:0]          gf_pattern_mode_cfg         ,
    input  wire [15:0]          rdc_err_bitmap              ,
    input  wire                 rdc_check_valid             ,
    input  wire                 rdc_check_pass              ,
    output wire                 rdc_train_init_en           ,
    output wire                 rdc_train_apply_best_cfg    ,
    output wire                 rdc_train_dual_pattern_cfg  ,
    output wire [ 3:0]          rdc_train_dq_start_cfg      ,
    output wire [ 3:0]          rdc_train_dq_end_cfg        ,
    output wire [ 8:0]          rdc_train_tap_start_cfg     ,
    output wire [ 8:0]          rdc_train_tap_stop_cfg      ,
    output wire [ 8:0]          rdc_train_tap_step_cfg      ,
    output wire                 rdc_train_dq_delay_l_we     ,
    output wire                 rdc_train_dq_delay_h_we     ,
    output wire [95:0]          rdc_train_dq_delay_wdat     ,
    output wire [8:0]           rdc_train_scan_tap_sel      ,
    input  wire [ 3:0]          rdc_train_state             ,
    input  wire                 rdc_train_busy              ,
    input  wire                 rdc_train_done              ,
    input  wire                 rdc_train_apply_best        ,
    input  wire [ 3:0]          rdc_train_dq_start          ,
    input  wire [ 8:0]          rdc_train_tap               ,
    input  wire [ 9:0]          rdc_train_status_best_len   ,
    input  wire [15:0]          rdc_train_pass_mask         ,
    input  wire [15:0]          rdc_train_fail_mask         ,
    input  wire [15:0]          rdc_train_last_err_bitmap   ,
    input  wire                 rdc_train_init_ready        ,
    input  wire                 rdc_train_pass_all          ,
    input  wire [143:0]         rdc_train_best_flat         ,
    input  wire [143:0]         rdc_train_left_flat         ,
    input  wire [143:0]         rdc_train_right_flat        ,
    input  wire [15:0]          rdc_train_scan_pass_bitmap  ,

    // Oscilloscope / voltage thresholds
    output wire                 os_start                    ,
    input  wire                 os_done                     ,
    input  wire [31:0]          os_result                   ,
    output wire [15:0]          vdd2l_uth                   ,
    output wire [15:0]          vddq_uth                    ,
    output wire [15:0]          vdd2h_uth                   ,
    output wire [15:0]          vdd1_uth                    ,
    output wire [15:0]          adc_ch5_uth                 ,
    output wire [15:0]          adc_ch6_uth                 ,
    output wire [15:0]          adc_ch7_uth                 ,
    output wire [15:0]          adc_ch8_uth                 ,

    // Power / signal relay control
    output wire                 g3vm_k1                     ,
    output wire                 g3vm_k3                     ,
    output wire                 g3vm_k5                     ,
    output wire                 g3vm_k7                     ,
    output wire                 g3vm_k15                    ,
    output wire                 g3vm_k16                    ,
    output wire                 adc_mi_pm1_sa_sla0          ,
    output wire                 adc_mi_pm1_sc_sla0          ,
    output wire                 adc_mi_pm2_sc_sla0          ,
    output wire                 adc_mi_pm2_sc_sla1          ,
    output wire                 adc_mp2c_fh2_sla2           ,
    output wire                 adc_mi_fh1_sla0             ,
    output wire                 adc_mi_fh1_sla1             ,
    output wire                 fh1_h_key                   ,
    output wire                 fh1_l_key                   ,
    output wire                 fh2_h_key                   ,
    output wire                 fh2_l_key                   ,
    output wire                 adc_mh_sla2                 ,
    output wire                 adc_mh_sla1                 ,
    output wire                 adc_mh_sla0                 ,
    output wire                 en_vpp_dut                  ,
    output wire                 rst_signal                  ,
    output wire                 rst_12v_signal
);

    // --------------------------------------------------------
    // SIR fanout signals
    // --------------------------------------------------------
    wire [ 7:0]         sir_addrx       ;
    wire [95:0]         sir_wdatx       ;

    wire                 sir_sel00      ;
    wire                 sir_read00     ;
    wire                 sir_dack00     ;
    wire [95:0]          sir_rdat00     ;

    wire                 sir_sel03      ;
    wire                 sir_read03     ;
    wire                 sir_dack03     ;
    wire [95:0]          sir_rdat03     ;

    wire                 sir_sel04      ;
    wire                 sir_read04     ;
    wire                 sir_dack04     ;
    wire [95:0]          sir_rdat04     ;

    wire                 sir_sel05      ;
    wire                 sir_read05     ;
    wire                 sir_dack05     ;
    wire [95:0]          sir_rdat05     ;

    wire                 sir_sel06      ;
    wire                 sir_read06     ;
    wire                 sir_dack06     ;
    wire [95:0]          sir_rdat06     ;

    wire                 sir_sel07      ;
    wire                 sir_read07     ;
    wire                 sir_dack07     ;
    wire [95:0]          sir_rdat07     ;

    // --------------------------------------------------------
    // SIR hub (address decode and fanout)
    // --------------------------------------------------------
    bar_hub u_bar_hub (
        .clk         (clk         ),
        .rst_n       (rst_n       ),
        .sir_sel     (sir_sel     ),
        .sir_addr    (sir_addr    ),
        .sir_read    (sir_read    ),
        .sir_wdat    (sir_wdat    ),
        .sir_rdat    (sir_rdat    ),
        .sir_dack    (sir_dack    ),
        .sir_addrx   (sir_addrx   ),
        .sir_wdatx   (sir_wdatx   ),
        .sir_sel00   (sir_sel00   ),
        .sir_read00  (sir_read00  ),
        .sir_dack00  (sir_dack00  ),
        .sir_rdat00  (sir_rdat00  ),
        .sir_sel03   (sir_sel03   ),
        .sir_read03  (sir_read03  ),
        .sir_dack03  (sir_dack03  ),
        .sir_rdat03  (sir_rdat03  ),
        .sir_sel04   (sir_sel04   ),
        .sir_read04  (sir_read04  ),
        .sir_dack04  (sir_dack04  ),
        .sir_rdat04  (sir_rdat04  ),
        .sir_sel05   (sir_sel05   ),
        .sir_read05  (sir_read05  ),
        .sir_dack05  (sir_dack05  ),
        .sir_rdat05  (sir_rdat05  ),
        .sir_sel06   (sir_sel06   ),
        .sir_read06  (sir_read06  ),
        .sir_dack06  (sir_dack06  ),
        .sir_rdat06  (sir_rdat06  ),
        .sir_sel07   (sir_sel07   ),
        .sir_read07  (sir_read07  ),
        .sir_dack07  (sir_dack07  ),
        .sir_rdat07  (sir_rdat07  )
    );

    // --------------------------------------------------------
    // bar00 - Scratch / ID register
    // --------------------------------------------------------
    bar00 u_bar00 (
        .clk      (clk      ),
        .rst_n    (rst_n    ),
        .sir_addr (sir_addrx),
        .sir_read (sir_read00),
        .sir_wdat (sir_wdatx),
        .sir_sel  (sir_sel00),
        .sir_dack (sir_dack00),
        .sir_rdat (sir_rdat00)
    );

    // --------------------------------------------------------
    // bar03 - Peripheral interfaces
    // --------------------------------------------------------
    bar03 u_bar03 (
        .clk                       (clk                       ),
        .rst_n                     (rst_n                     ),
        .sir_addr                  (sir_addrx                 ),
        .sir_read                  (sir_read03                ),
        .sir_wdat                  (sir_wdatx                 ),
        .sir_sel                   (sir_sel03                 ),
        .sir_dack                  (sir_dack03                ),
        .sir_rdat                  (sir_rdat03                ),
        .ad5272_2_entry            (ad5272_2_entry            ),
        .ad5272_2_read_addr        (ad5272_2_read_addr        ),
        .ad5272_2_read_data        (ad5272_2_read_data        ),
        .ad5272_2_write_addr       (ad5272_2_write_addr       ),
        .ad5272_2_write_cmd        (ad5272_2_write_cmd        ),
        .ad5272_2_write_data       (ad5272_2_write_data       ),
        .irsp_u67_value            (irsp_u67_value            ),
        .irsp_u67_send_byte_ctrl   (irsp_u67_send_byte_ctrl   ),
        .irsp_u67_data_bit_ctrl    (irsp_u67_data_bit_ctrl    ),
        .irsp_u67_data_out         (irsp_u67_data_out         ),
        .irsp_u68_value            (irsp_u68_value            ),
        .irsp_u68_send_byte_ctrl   (irsp_u68_send_byte_ctrl   ),
        .irsp_u68_data_bit_ctrl    (irsp_u68_data_bit_ctrl    ),
        .irsp_u68_data_out         (irsp_u68_data_out         ),
        .irsp_iic_device_addr      (irsp_iic_device_addr      ),
        .eeprom_value              (eeprom_value              ),
        .eeprom_send_byte_ctrl     (eeprom_send_byte_ctrl     ),
        .eeprom_data_bit_ctrl      (eeprom_data_bit_ctrl      ),
        .eeprom_data_out           (eeprom_data_out           ),
        .g3vm_k1                   (g3vm_k1                   ),
        .g3vm_k3                   (g3vm_k3                   ),
        .g3vm_k5                   (g3vm_k5                   ),
        .g3vm_k7                   (g3vm_k7                   ),
        .g3vm_k15                  (g3vm_k15                  ),
        .g3vm_k16                  (g3vm_k16                  ),
        .adc_mi_pm1_sa_sla0        (adc_mi_pm1_sa_sla0        ),
        .adc_mi_pm1_sc_sla0        (adc_mi_pm1_sc_sla0        ),
        .adc_mi_pm2_sc_sla0        (adc_mi_pm2_sc_sla0        ),
        .adc_mi_pm2_sc_sla1        (adc_mi_pm2_sc_sla1        ),
        .adc_mp2c_fh2_sla2         (adc_mp2c_fh2_sla2         ),
        .adc_mi_fh1_sla0           (adc_mi_fh1_sla0           ),
        .adc_mi_fh1_sla1           (adc_mi_fh1_sla1           ),
        .fh1_h_key                 (fh1_h_key                 ),
        .fh1_l_key                 (fh1_l_key                 ),
        .fh2_h_key                 (fh2_h_key                 ),
        .fh2_l_key                 (fh2_l_key                 ),
        .adc_mh_sla2               (adc_mh_sla2               ),
        .adc_mh_sla1               (adc_mh_sla1               ),
        .adc_mh_sla0               (adc_mh_sla0               ),
        .en_vpp_dut                (en_vpp_dut                ),
        .rst_signal                (rst_signal                ),
        .rst_12v_signal            (rst_12v_signal            )
    );

    // --------------------------------------------------------
    // bar04 - DUT initialization / IDD6
    // --------------------------------------------------------
    bar04 u_bar04 (
        .clk             (clk             ),
        .rst_n           (rst_n           ),
        .sir_addr        (sir_addrx       ),
        .sir_read        (sir_read04      ),
        .sir_wdat        (sir_wdatx       ),
        .sir_sel         (sir_sel04       ),
        .sir_dack        (sir_dack04      ),
        .sir_rdat        (sir_rdat04      ),
        .init_start      (dut_init_start  ),
        .init_done       (dut_init_done   ),
        .init_fail       (dut_init_fail   ),
        .mr8_density     (dut_mr8_density ),
        .idd6_start      (dut_idd6_start  ),
        .idd6_done       (dut_idd6_done   ),
        .idd6_result     (dut_idd6_result )
    );

    // --------------------------------------------------------
    // bar05 - GF test control
    // --------------------------------------------------------
    bar05 u_bar05 (
        .clk                     (clk                    ),
        .rst_n                   (rst_n                  ),
        .sir_addr                (sir_addrx              ),
        .sir_read                (sir_read05             ),
        .sir_wdat                (sir_wdatx              ),
        .sir_sel                 (sir_sel05              ),
        .sir_dack                (sir_dack05             ),
        .sir_rdat                (sir_rdat05             ),
        .gf_start                (gf_start               ),
        .gf_done                 (gf_done                ),
        .gf_result               (gf_result              ),
        .gf_aux_result           (gf_aux_result          ),
        .gf_bad_block_info       (gf_bad_block_info      ),
        .gf_bad_block_count      (gf_bad_block_count     ),
        .gf_clk_sel              (gf_clk_sel             ),
        .gf_addr_start           (gf_addr_start          ),
        .gf_addr_end             (gf_addr_end            )
    );

    // --------------------------------------------------------
    // bar06 - Timing / calibration parameters
    // --------------------------------------------------------
    bar06 u_bar06 (
        .clk                       (clk                       ),
        .rst_n                     (rst_n                     ),
        .sir_addr                  (sir_addrx                 ),
        .sir_read                  (sir_read06                ),
        .sir_wdat                  (sir_wdatx                 ),
        .sir_sel                   (sir_sel06                 ),
        .sir_dack                  (sir_dack06                ),
        .sir_rdat                  (sir_rdat06                ),
        .dq_delay_flat             (dut_dq_delay_flat         ),
        .mrw_r                     (mrw_r                     ),
        .read_capture_start_cnt    (read_capture_start_cnt    ),
        .gf_capture_start_cnt      (gf_capture_start_cnt      ),
        .init_beat_offset          (init_beat_offset          ),
        .gf_beat_offset            (gf_beat_offset            ),
        .gf_rd_wck_start_cnt       (gf_rd_wck_start_cnt       ),
        .gf_rd_wck_last_cnt        (gf_rd_wck_last_cnt        ),
        .gf_wr_wck_start_cnt       (gf_wr_wck_start_cnt       ),
        .gf_wr_wck_last_cnt        (gf_wr_wck_last_cnt        ),
        .gf_read_done_cnt          (gf_read_done_cnt          ),
        .gf_write_done_cnt         (gf_write_done_cnt         ),
        .gf_act_cmd_gap_cnt        (gf_act_cmd_gap_cnt        ),
        .gf_rd_cmd_gap_cnt         (gf_rd_cmd_gap_cnt         ),
        .gf_wr_cmd_gap_cnt         (gf_wr_cmd_gap_cnt         ),
        .gf_pre_cmd_gap_cnt        (gf_pre_cmd_gap_cnt        ),
        .gf_refresh_batch_num      (gf_refresh_batch_num      ),
        .gf_pattern_mode_cfg       (gf_pattern_mode_cfg       ),
        .rdc_err_bitmap            (rdc_err_bitmap            ),
        .rdc_check_valid           (rdc_check_valid           ),
        .rdc_check_pass            (rdc_check_pass            ),
        .rdc_train_init_en         (rdc_train_init_en         ),
        .rdc_train_apply_best_cfg  (rdc_train_apply_best_cfg  ),
        .rdc_train_dual_pattern_cfg(rdc_train_dual_pattern_cfg),
        .rdc_train_dq_start_cfg    (rdc_train_dq_start_cfg    ),
        .rdc_train_dq_end_cfg      (rdc_train_dq_end_cfg      ),
        .rdc_train_tap_start_cfg   (rdc_train_tap_start_cfg   ),
        .rdc_train_tap_stop_cfg    (rdc_train_tap_stop_cfg    ),
        .rdc_train_tap_step_cfg    (rdc_train_tap_step_cfg    ),
        .rdc_train_dq_delay_l_we   (rdc_train_dq_delay_l_we   ),
        .rdc_train_dq_delay_h_we   (rdc_train_dq_delay_h_we   ),
        .rdc_train_dq_delay_wdat   (rdc_train_dq_delay_wdat   ),
        .rdc_train_scan_tap_sel    (rdc_train_scan_tap_sel    ),
        .rdc_train_state           (rdc_train_state           ),
        .rdc_train_busy            (rdc_train_busy            ),
        .rdc_train_done            (rdc_train_done            ),
        .rdc_train_apply_best      (rdc_train_apply_best      ),
        .rdc_train_dq_start        (rdc_train_dq_start        ),
        .rdc_train_tap             (rdc_train_tap             ),
        .rdc_train_status_best_len (rdc_train_status_best_len ),
        .rdc_train_pass_mask       (rdc_train_pass_mask       ),
        .rdc_train_fail_mask       (rdc_train_fail_mask       ),
        .rdc_train_last_err_bitmap (rdc_train_last_err_bitmap ),
        .rdc_train_init_ready      (rdc_train_init_ready      ),
        .rdc_train_pass_all        (rdc_train_pass_all        ),
        .rdc_train_best_flat       (rdc_train_best_flat       ),
        .rdc_train_left_flat       (rdc_train_left_flat       ),
        .rdc_train_right_flat      (rdc_train_right_flat      ),
        .rdc_train_scan_pass_bitmap(rdc_train_scan_pass_bitmap)
    );

    // --------------------------------------------------------
    // bar07 - Oscilloscope / voltage thresholds
    // --------------------------------------------------------
    bar07 u_bar07 (
        .clk         (clk         ),
        .rst_n       (rst_n       ),
        .sir_addr    (sir_addrx   ),
        .sir_read    (sir_read07  ),
        .sir_wdat    (sir_wdatx   ),
        .sir_sel     (sir_sel07   ),
        .sir_dack    (sir_dack07  ),
        .sir_rdat    (sir_rdat07  ),
        .os_start    (os_start    ),
        .os_done     (os_done     ),
        .os_result   (os_result   ),
        .vdd2l_uth   (vdd2l_uth   ),
        .vddq_uth    (vddq_uth    ),
        .vdd2h_uth   (vdd2h_uth   ),
        .vdd1_uth    (vdd1_uth    ),
        .adc_ch5_uth (adc_ch5_uth ),
        .adc_ch6_uth (adc_ch6_uth ),
        .adc_ch7_uth (adc_ch7_uth ),
        .adc_ch8_uth (adc_ch8_uth )
    );

endmodule

// =========================================================================
//  BAR Hub
// =========================================================================
// Kept in this file to avoid scattering tiny helper modules across the BAR
// directory. Behavior is unchanged from the standalone bar_hub module.

`include "dram_driver_head.vh"

module bar_hub (
    input  wire         clk,
    input  wire         rst_n,

    input  wire         sir_sel,
    input  wire [15:0]  sir_addr,
    input  wire         sir_read,
    input  wire [95:0]  sir_wdat,
    output reg  [95:0]  sir_rdat,
    output reg          sir_dack,

    output reg  [7:0]   sir_addrx,
    output reg  [95:0]  sir_wdatx,

    output reg          sir_sel00,
    output reg          sir_read00,
    input  wire         sir_dack00,
    input  wire [95:0]  sir_rdat00,

    output reg          sir_sel03,
    output reg          sir_read03,
    input  wire         sir_dack03,
    input  wire [95:0]  sir_rdat03,

    output reg          sir_sel04,
    output reg          sir_read04,
    input  wire         sir_dack04,
    input  wire [95:0]  sir_rdat04,

    output reg          sir_sel05,
    output reg          sir_read05,
    input  wire         sir_dack05,
    input  wire [95:0]  sir_rdat05,

    output reg          sir_sel06,
    output reg          sir_read06,
    input  wire         sir_dack06,
    input  wire [95:0]  sir_rdat06,

    output reg          sir_sel07,
    output reg          sir_read07,
    input  wire         sir_dack07,
    input  wire [95:0]  sir_rdat07
);

reg        sir_dack_p1;
reg [95:0] sir_rdat_p1;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        sir_dack_p1 <= 1'b0;
        sir_dack    <= 1'b0;
    end
    else begin
        sir_dack_p1 <= sir_dack00 | sir_dack03 | sir_dack04 |
                       sir_dack05 | sir_dack06 | sir_dack07;
        sir_dack    <= sir_dack_p1;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        sir_rdat_p1 <= 96'h0;
        sir_rdat    <= 96'h0;
    end
    else begin
        sir_rdat_p1 <= sir_rdat00 | sir_rdat03 | sir_rdat04 |
                       sir_rdat05 | sir_rdat06 | sir_rdat07;
        sir_rdat    <= sir_rdat_p1;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        sir_addrx <= 8'h00;
        sir_wdatx <= 96'h0;
    end
    else begin
        sir_addrx <= sir_addr[7:0];
        sir_wdatx <= sir_wdat;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        sir_sel00 <= 1'b0;
        sir_sel03 <= 1'b0;
        sir_sel04 <= 1'b0;
        sir_sel05 <= 1'b0;
        sir_sel06 <= 1'b0;
        sir_sel07 <= 1'b0;
    end
    else begin
        sir_sel00 <= sir_sel & (sir_addr[15:8] == `bar_PAGE_SYSTEM);
        sir_sel03 <= sir_sel & (sir_addr[15:8] == `bar_PAGE_PERIPHERAL);
        sir_sel04 <= sir_sel & (sir_addr[15:8] == `bar_PAGE_TEST_CTRL);
        sir_sel05 <= sir_sel & (sir_addr[15:8] == `bar_PAGE_GF);
        sir_sel06 <= sir_sel & (sir_addr[15:8] == `bar_PAGE_DUT_CFG);
        sir_sel07 <= sir_sel & (sir_addr[15:8] == `bar_PAGE_OS);
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        sir_read00 <= 1'b0;
        sir_read03 <= 1'b0;
        sir_read04 <= 1'b0;
        sir_read05 <= 1'b0;
        sir_read06 <= 1'b0;
        sir_read07 <= 1'b0;
    end
    else begin
        sir_read00 <= sir_read & (sir_addr[15:8] == `bar_PAGE_SYSTEM);
        sir_read03 <= sir_read & (sir_addr[15:8] == `bar_PAGE_PERIPHERAL);
        sir_read04 <= sir_read & (sir_addr[15:8] == `bar_PAGE_TEST_CTRL);
        sir_read05 <= sir_read & (sir_addr[15:8] == `bar_PAGE_GF);
        sir_read06 <= sir_read & (sir_addr[15:8] == `bar_PAGE_DUT_CFG);
        sir_read07 <= sir_read & (sir_addr[15:8] == `bar_PAGE_OS);
    end
end

endmodule

// =========================================================================
//  BAR Response
// =========================================================================
// Common registered response path for all BAR register blocks.
// Preserves the original one-cycle BAR acknowledge and read-data timing.

module bar_response (
    input  wire                 clk            ,
    input  wire                 rst_n          ,
    input  wire                 sir_sel        ,
    input  wire                 sir_read       ,
    input  wire [95:0]          sir_rdat_next  ,
    output reg                  sir_dack       ,
    output reg  [95:0]          sir_rdat
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            sir_dack <= 1'b0;
        else
            sir_dack <= sir_sel;
    end

    always @(posedge clk) begin
        if (sir_sel && sir_read)
            sir_rdat <= sir_rdat_next;
        else
            sir_rdat <= 96'h0;
    end

endmodule
