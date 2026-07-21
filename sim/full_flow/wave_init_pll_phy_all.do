# Focused and complete LPDDR5 INIT waveform layout.

proc add_sig {group_name signal_name {radix_name ""}} {
    if {$radix_name == ""} {
        if {[catch {quietly add wave -noupdate -group $group_name $signal_name}]} {
            puts "WAVE SKIP: $signal_name"
        }
    } else {
        if {[catch {quietly add wave -noupdate -group $group_name -radix $radix_name $signal_name}]} {
            puts "WAVE SKIP: $signal_name"
        }
    }
}

proc add_scope {group_name scope_name recursive_en} {
    if {$recursive_en == 1} {
        if {[catch {quietly add wave -noupdate -r -group $group_name ${scope_name}/*} msg]} {
            puts "WAVE SCOPE SKIP: $scope_name ($msg)"
        }
    } else {
        if {[catch {quietly add wave -noupdate -group $group_name ${scope_name}/*} msg]} {
            puts "WAVE SCOPE SKIP: $scope_name ($msg)"
        }
    }
}

set TB      "sim:/tb_init_pll_phy_wave"
set CLOCK   "$TB/U_CLOCK_MANAGE_TOP"
set DUT     "$TB/U_DUT"
set SCH     "$DUT/U_lpddr5_test_scheduler"
set INIT    "$SCH/U_lpddr5_init"
set RDC     "$INIT/rdc_train_u0"
set CHANNEL "$DUT/U_lpddr5_channel"
set PHYIO   "$CHANNEL/U_lpddr5_ch_a_phy_io"
set DQPHY   "$PHYIO/U_lpddr5_dqs_serdes_phy"

if {[batch_mode] == 0} {
    view wave
    delete wave *
    configure wave -namecolwidth 410
    configure wave -valuecolwidth 220
    configure wave -timelineunits ns
}

# 00: board clock -> clk_wiz/MMCM -> startup reset sequence.
add_sig "00_clock_and_startup" $TB/r_sys_clk_p
add_sig "00_clock_and_startup" $TB/w_sys_clk_n
add_sig "00_clock_and_startup" $TB/r_sys_reset
add_sig "00_clock_and_startup" $TB/w_mmcm_locked
add_sig "00_clock_and_startup" $TB/w_clk_core_200m
add_sig "00_clock_and_startup" $TB/w_clk_dq_tx_400m
add_sig "00_clock_and_startup" $TB/w_clk_ca_wck_400m
add_sig "00_clock_and_startup" $TB/w_clk_dq_rx_400m
add_sig "00_clock_and_startup" $TB/w_core_reset_n
add_sig "00_clock_and_startup" $CLOCK/r_startup_state unsigned
add_sig "00_clock_and_startup" $CLOCK/r_phy_settle_cnt unsigned
add_sig "00_clock_and_startup" $TB/w_serdes_reset_n
add_sig "00_clock_and_startup" $TB/w_idelayctrl_reset
add_sig "00_clock_and_startup" $TB/w_idelayctrl_ready
add_sig "00_clock_and_startup" $TB/w_phy_ready
add_sig "00_clock_and_startup" $TB/r_init_en

# 01: INIT state transition and completion/failure decision.
add_sig "01_init_state_flow" $INIT/ascii_state ascii
add_sig "01_init_state_flow" $INIT/r_init_state unsigned
add_sig "01_init_state_flow" $INIT/r_init_state_next unsigned
add_sig "01_init_state_flow" $INIT/w_init_start
add_sig "01_init_state_flow" $INIT/r_init_run
add_sig "01_init_state_flow" $INIT/r_init_base_done
add_sig "01_init_state_flow" $INIT/r_init_rdc_train_en
add_sig "01_init_state_flow" $SCH/init_busy
add_sig "01_init_state_flow" $TB/w_init_done
add_sig "01_init_state_flow" $TB/w_init_fail
add_sig "01_init_state_flow" $INIT/w_init_base_done_now
add_sig "01_init_state_flow" $INIT/w_init_finish_no_train
add_sig "01_init_state_flow" $INIT/w_init_finish_train
add_sig "01_init_state_flow" $INIT/w_init_fail_now

# 02: enables and counters that cause each state transition.
add_sig "02_init_enables_and_counters" $INIT/r_power_on_cnt_en
add_sig "02_init_enables_and_counters" $INIT/r_cnt_init unsigned
add_sig "02_init_enables_and_counters" $INIT/r_mr_init_w_cnt_en
add_sig "02_init_enables_and_counters" $INIT/r_cnt_mr_init_w unsigned
add_sig "02_init_enables_and_counters" $INIT/r_mr_slot unsigned
add_sig "02_init_enables_and_counters" $INIT/r_mr_phase unsigned
add_sig "02_init_enables_and_counters" $INIT/w_mr_table_data hexadecimal
add_sig "02_init_enables_and_counters" $INIT/w_mr_addr_value hexadecimal
add_sig "02_init_enables_and_counters" $INIT/w_mr_op_value hexadecimal
add_sig "02_init_enables_and_counters" $INIT/w_mr_data_value hexadecimal
add_sig "02_init_enables_and_counters" $INIT/r_zqcal_cnt_en
add_sig "02_init_enables_and_counters" $INIT/r_cnt_zqcal unsigned
add_sig "02_init_enables_and_counters" $INIT/r_mr_init_r_cnt_en
add_sig "02_init_enables_and_counters" $INIT/r_cnt_mr_init_r unsigned
add_sig "02_init_enables_and_counters" $INIT/r_rt_mr_state unsigned
add_sig "02_init_enables_and_counters" $INIT/r_rt_mrw_cnt_en
add_sig "02_init_enables_and_counters" $INIT/r_cnt_rt_mrw unsigned
add_sig "02_init_enables_and_counters" $INIT/r_rt_rdc_cnt_en
add_sig "02_init_enables_and_counters" $INIT/r_cnt_rt_rdc unsigned

# 03: values produced by INIT before the scheduler/PHY boundary.
add_sig "03_init_waveform_intent" $INIT/wave_reset_n_a
add_sig "03_init_waveform_intent" $INIT/wave_cs_a_0_rise
add_sig "03_init_waveform_intent" $INIT/wave_cs_a_0_fall
add_sig "03_init_waveform_intent" $INIT/wave_ca_a_rise hexadecimal
add_sig "03_init_waveform_intent" $INIT/wave_ca_a_fall hexadecimal
add_sig "03_init_waveform_intent" $INIT/wave_wck_a_run_en binary
add_sig "03_init_waveform_intent" $INIT/w_wck_open_window
add_sig "03_init_waveform_intent" $INIT/w_wck_close_window
add_sig "03_init_waveform_intent" $INIT/w_init_mrr_capture_start
add_sig "03_init_waveform_intent" $INIT/w_rt_rdc_capture_start
add_sig "03_init_waveform_intent" $INIT/rx_dq_capture_en
add_sig "03_init_waveform_intent" $INIT/rdc_sample_en

# 04: scheduler arbitration and the single selected PHY command bus.
add_sig "04_scheduler_to_phy" $SCH/chn_state binary
add_sig "04_scheduler_to_phy" $SCH/init_enb_lock
add_sig "04_scheduler_to_phy" $SCH/init_mr_channel_enb_lock
add_sig "04_scheduler_to_phy" $DUT/channel_ck_a_run_en
add_sig "04_scheduler_to_phy" $DUT/channel_reset_n_a
add_sig "04_scheduler_to_phy" $DUT/channel_cs_a_0_rise
add_sig "04_scheduler_to_phy" $DUT/channel_cs_a_0_fall
add_sig "04_scheduler_to_phy" $DUT/channel_ca_a_rise hexadecimal
add_sig "04_scheduler_to_phy" $DUT/channel_ca_a_fall hexadecimal
add_sig "04_scheduler_to_phy" $DUT/channel_wck_a_run_en binary
add_sig "04_scheduler_to_phy" $DUT/channel_wck_a_phase binary
add_sig "04_scheduler_to_phy" $DUT/channel_dq_a_tx_word hexadecimal
add_sig "04_scheduler_to_phy" $DUT/channel_dq_oe
add_sig "04_scheduler_to_phy" $DUT/channel_rx_dq_capture_en

# 05: serializer input patterns and one representative primitive lane.
add_sig "05_phy_serializer" $PHYIO/U_ck_a_serdes/ck_pattern binary
add_sig "05_phy_serializer" $PHYIO/U_ck_a_serdes/clk_200m
add_sig "05_phy_serializer" $PHYIO/U_ck_a_serdes/clk_400m
add_sig "05_phy_serializer" $PHYIO/U_ck_a_serdes/ck_run_en
add_sig "05_phy_serializer" $PHYIO/U_ck_a_serdes/out_q
add_sig "05_phy_serializer" $PHYIO/U_cs0_a_serdes/data_rise
add_sig "05_phy_serializer" $PHYIO/U_cs0_a_serdes/data_fall
add_sig "05_phy_serializer" $PHYIO/U_cs0_a_serdes/out_q
add_sig "05_phy_serializer" $PHYIO/GEN_CA_SERDES[0]/U_ca_a_serdes/data_rise
add_sig "05_phy_serializer" $PHYIO/GEN_CA_SERDES[0]/U_ca_a_serdes/data_fall
add_sig "05_phy_serializer" $PHYIO/GEN_CA_SERDES[0]/U_ca_a_serdes/out_q
add_sig "05_phy_serializer" $PHYIO/GEN_WCK_SERDES[0]/U_wck_a_serdes/wck_pattern binary
add_sig "05_phy_serializer" $PHYIO/GEN_WCK_SERDES[0]/U_wck_a_serdes/run_en
add_sig "05_phy_serializer" $PHYIO/GEN_WCK_SERDES[0]/U_wck_a_serdes/phase
add_sig "05_phy_serializer" $PHYIO/GEN_WCK_SERDES[0]/U_wck_a_serdes/out_q

# 06: actual LPDDR5 package pins after OSERDES and output buffers.
add_sig "06_external_dram_pins" $TB/w_reset_n_a
add_sig "06_external_dram_pins" $TB/w_ck_t_a
add_sig "06_external_dram_pins" $TB/w_ck_c_a
add_sig "06_external_dram_pins" $TB/w_cs0_a
add_sig "06_external_dram_pins" $TB/w_ca_a hexadecimal
add_sig "06_external_dram_pins" $TB/w_wck_t_a binary
add_sig "06_external_dram_pins" $TB/w_wck_c_a binary
add_sig "06_external_dram_pins" $TB/w_dq_a hexadecimal
add_sig "06_external_dram_pins" $TB/w_rdqs_t_a binary
add_sig "06_external_dram_pins" $TB/w_rdqs_c_a binary
add_sig "06_external_dram_pins" $TB/w_dmi_a binary

# 07: ideal DRAM responder and the real IDELAY/ISERDES receive result.
add_sig "07_readback_and_rx_phy" $TB/w_init_rdc_read_active
add_sig "07_readback_and_rx_phy" $TB/w_init_rdc_pattern_sel
add_sig "07_readback_and_rx_phy" $TB/r_dram_dq_oe
add_sig "07_readback_and_rx_phy" $TB/r_dram_beat_index decimal
add_sig "07_readback_and_rx_phy" $TB/r_dram_dq_word hexadecimal
add_sig "07_readback_and_rx_phy" $DQPHY/dq_in_raw hexadecimal
add_sig "07_readback_and_rx_phy" $DQPHY/dq_in_dly hexadecimal
add_sig "07_readback_and_rx_phy" $DQPHY/dq_q_word_full hexadecimal
add_sig "07_readback_and_rx_phy" $DQPHY/rx_capture_start
add_sig "07_readback_and_rx_phy" $DQPHY/rx_capture_req_pipe binary
add_sig "07_readback_and_rx_phy" $DUT/dq_a_word_flat hexadecimal
add_sig "07_readback_and_rx_phy" $DUT/dq_a_word_valid
add_sig "07_readback_and_rx_phy" $DUT/dq_a_burst_flat hexadecimal
add_sig "07_readback_and_rx_phy" $DUT/dq_a_burst_valid
add_sig "07_readback_and_rx_phy" $SCH/rdc_expect_burst hexadecimal
add_sig "07_readback_and_rx_phy" $TB/w_rdc_err_bitmap hexadecimal
add_sig "07_readback_and_rx_phy" $TB/w_rdc_check_valid
add_sig "07_readback_and_rx_phy" $TB/w_rdc_check_pass
add_sig "07_readback_and_rx_phy" $TB/w_die_message hexadecimal

# 08: limited dual-pattern RDC training flow.
add_sig "08_rdc_training" $TB/w_rdc_train_state unsigned
add_sig "08_rdc_training" $TB/w_rdc_train_busy
add_sig "08_rdc_training" $TB/w_rdc_train_done
add_sig "08_rdc_training" $TB/w_rdc_train_tap unsigned
add_sig "08_rdc_training" $TB/w_init_rdc_pattern_sel
add_sig "08_rdc_training" $TB/w_rdc_train_status_best_len unsigned
add_sig "08_rdc_training" $TB/w_rdc_train_pass_mask hexadecimal
add_sig "08_rdc_training" $TB/w_rdc_train_fail_mask hexadecimal
add_sig "08_rdc_training" $TB/w_rdc_train_last_err_bitmap hexadecimal
add_sig "08_rdc_training" $TB/w_rdc_train_pass_all
add_sig "08_rdc_training" $RDC/r_rdc_train_scan_clear_active
add_sig "08_rdc_training" $RDC/r_rdc_train_scan_clear_addr unsigned
add_sig "08_rdc_training" $RDC/rdc_train_pattern_idx
add_sig "08_rdc_training" $RDC/rdc_train_retry_cnt unsigned
add_sig "08_rdc_training" $RDC/rdc_train_verify_mode
add_sig "08_rdc_training" $RDC/rdc_train_verify_round unsigned

# Complete direct-scope views. Keep these collapsed until a focused signal
# points to the block that needs deeper inspection.
add_scope "90_clock_manager_all" $CLOCK 0
add_scope "91_scheduler_all" $SCH 0
add_scope "92_init_all" $INIT 0
add_scope "93_rdc_all" $RDC 0
add_scope "94_channel_all" $CHANNEL 0
add_scope "95_phy_io_all" $PHYIO 0
add_scope "96_dq_rx_tx_phy_all" $DQPHY 0
add_scope "97_selected_primitive_lane0" $PHYIO/U_ck_a_serdes 1
add_scope "97_selected_primitive_lane0" $PHYIO/U_reset_n_a_serdes 1
add_scope "97_selected_primitive_lane0" $PHYIO/U_cs0_a_serdes 1
add_scope "97_selected_primitive_lane0" $PHYIO/GEN_CA_SERDES[0]/U_ca_a_serdes 1
add_scope "97_selected_primitive_lane0" $PHYIO/GEN_WCK_SERDES[0]/U_wck_a_serdes 1
add_scope "97_selected_primitive_lane0" $DQPHY/GEN_DQ_IO[0] 1

TreeUpdate [SetDefaultTree]
WaveRestoreZoom {0 ns} {80 us}

