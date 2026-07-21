# Complete INIT + limited RDC waveform layout.

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

set TB   "sim:/tb_init_rdc_wave"
set SCH  "$TB/U_SCHEDULER"
set INIT "$SCH/U_lpddr5_init"
set RDC  "$INIT/rdc_train_u0"

if {[batch_mode] == 0} {
    view wave
    delete wave *
    configure wave -namecolwidth 390
    configure wave -valuecolwidth 220
    configure wave -timelineunits ns
}

add_sig "00_quick_init_control" $TB/clk_200m
add_sig "00_quick_init_control" $TB/clk_400m
add_sig "00_quick_init_control" $TB/rst_n
add_sig "00_quick_init_control" $TB/init_en
add_sig "00_quick_init_control" $TB/dbg_init_busy
add_sig "00_quick_init_control" $TB/init_done
add_sig "00_quick_init_control" $TB/init_fail
add_sig "00_quick_init_control" $INIT/ascii_state ascii
add_sig "00_quick_init_control" $INIT/r_init_state unsigned
add_sig "00_quick_init_control" $INIT/r_init_state_next unsigned
add_sig "00_quick_init_control" $INIT/r_init_run
add_sig "00_quick_init_control" $INIT/r_init_base_done
add_sig "00_quick_init_control" $INIT/r_init_rdc_train_en
add_sig "00_quick_init_control" $TB/die_message hexadecimal

add_sig "01_init_counters_and_phase" $INIT/w_init_start
add_sig "01_init_counters_and_phase" $INIT/r_power_on_cnt_en
add_sig "01_init_counters_and_phase" $INIT/r_cnt_init unsigned
add_sig "01_init_counters_and_phase" $INIT/r_mr_init_w_cnt_en
add_sig "01_init_counters_and_phase" $INIT/r_cnt_mr_init_w unsigned
add_sig "01_init_counters_and_phase" $INIT/r_mr_slot unsigned
add_sig "01_init_counters_and_phase" $INIT/r_mr_phase unsigned
add_sig "01_init_counters_and_phase" $INIT/r_zqcal_cnt_en
add_sig "01_init_counters_and_phase" $INIT/r_cnt_zqcal unsigned
add_sig "01_init_counters_and_phase" $INIT/r_mr_init_r_cnt_en
add_sig "01_init_counters_and_phase" $INIT/r_cnt_mr_init_r unsigned
add_sig "01_init_counters_and_phase" $INIT/w_init_base_done_now

add_sig "02_scheduler_runtime_request" $SCH/chn_state binary
add_sig "02_scheduler_runtime_request" $SCH/init_enb_lock
add_sig "02_scheduler_runtime_request" $SCH/mr_enb_lock
add_sig "02_scheduler_runtime_request" $SCH/runtime_mrw_req_allowed
add_sig "02_scheduler_runtime_request" $SCH/runtime_rdc_req_allowed
add_sig "02_scheduler_runtime_request" $SCH/init_rdc_train_mrw_r hexadecimal
add_sig "02_scheduler_runtime_request" $SCH/mrw_r_1 hexadecimal
add_sig "02_scheduler_runtime_request" $SCH/mrw_r_2 hexadecimal
add_sig "02_scheduler_runtime_request" $SCH/mrw_edge_detect
add_sig "02_scheduler_runtime_request" $SCH/mrw_start_pulse
add_sig "02_scheduler_runtime_request" $SCH/schedule_mrw_req
add_sig "02_scheduler_runtime_request" $SCH/init_rdc_train_mrr_r hexadecimal
add_sig "02_scheduler_runtime_request" $SCH/mrr_r_1 hexadecimal
add_sig "02_scheduler_runtime_request" $SCH/mrr_r_2 hexadecimal
add_sig "02_scheduler_runtime_request" $SCH/rdc_edge_detect
add_sig "02_scheduler_runtime_request" $SCH/rdc_start_pulse
add_sig "02_scheduler_runtime_request" $SCH/schedule_rdc_req
add_sig "02_scheduler_runtime_request" $INIT/r_rt_mr_state unsigned
add_sig "02_scheduler_runtime_request" $INIT/r_cnt_rt_mrw unsigned
add_sig "02_scheduler_runtime_request" $INIT/r_cnt_rt_rdc unsigned

add_sig "03_ca_ck_wck_fabric" $TB/channel_ck_a_run_en
add_sig "03_ca_ck_wck_fabric" $TB/channel_reset_n_a
add_sig "03_ca_ck_wck_fabric" $TB/channel_cs_a_0_fall
add_sig "03_ca_ck_wck_fabric" $TB/channel_cs_a_0_rise
add_sig "03_ca_ck_wck_fabric" $TB/channel_ca_a_fall hexadecimal
add_sig "03_ca_ck_wck_fabric" $TB/channel_ca_a_rise hexadecimal
add_sig "03_ca_ck_wck_fabric" $TB/channel_wck_a_run_en binary
add_sig "03_ca_ck_wck_fabric" $TB/channel_wck_a_phase binary
add_sig "03_ca_ck_wck_fabric" $INIT/w_wck_open_window
add_sig "03_ca_ck_wck_fabric" $INIT/w_wck_close_window

add_sig "04_external_serdes_pins" $TB/reset_n_a_out
add_sig "04_external_serdes_pins" $TB/ck_a_out
add_sig "04_external_serdes_pins" $TB/cs_a_out
add_sig "04_external_serdes_pins" $TB/ca_a_out hexadecimal
add_sig "04_external_serdes_pins" $TB/wck_a_out binary

add_sig "05_read_capture_and_compare" $TB/channel_rx_dq_capture_en
add_sig "05_read_capture_and_compare" $SCH/init_rdc_sample_en
add_sig "05_read_capture_and_compare" $TB/r_init_word_pending
add_sig "05_read_capture_and_compare" $TB/dq_a_word_valid
add_sig "05_read_capture_and_compare" $TB/dq_a_word_flat hexadecimal
add_sig "05_read_capture_and_compare" $TB/r_rdc_burst_pending
add_sig "05_read_capture_and_compare" $TB/dq_a_burst_valid
add_sig "05_read_capture_and_compare" $TB/dq_a_burst_flat hexadecimal
add_sig "05_read_capture_and_compare" $SCH/rdc_capture_seen
add_sig "05_read_capture_and_compare" $SCH/rdc_expect_burst hexadecimal
add_sig "05_read_capture_and_compare" $SCH/rdc_burst_done
add_sig "05_read_capture_and_compare" $TB/rdc_err_bitmap hexadecimal
add_sig "05_read_capture_and_compare" $TB/rdc_check_valid
add_sig "05_read_capture_and_compare" $TB/rdc_check_pass

add_sig "06_rdc_training_summary" $TB/rdc_train_state unsigned
add_sig "06_rdc_training_summary" $TB/rdc_train_busy
add_sig "06_rdc_training_summary" $TB/rdc_train_done
add_sig "06_rdc_training_summary" $TB/rdc_train_init_ready
add_sig "06_rdc_training_summary" $TB/rdc_train_tap unsigned
add_sig "06_rdc_training_summary" $SCH/init_rdc_train_pattern_sel
add_sig "06_rdc_training_summary" $TB/rdc_train_status_best_len unsigned
add_sig "06_rdc_training_summary" $TB/rdc_train_pass_mask hexadecimal
add_sig "06_rdc_training_summary" $TB/rdc_train_fail_mask hexadecimal
add_sig "06_rdc_training_summary" $TB/rdc_train_last_err_bitmap hexadecimal
add_sig "06_rdc_training_summary" $TB/rdc_train_pass_all
add_sig "06_rdc_training_summary" $TB/rdc_dq_delay_flat hexadecimal
add_sig "06_rdc_training_summary" $TB/rdc_train_best_flat hexadecimal
add_sig "06_rdc_training_summary" $TB/rdc_train_left_flat hexadecimal
add_sig "06_rdc_training_summary" $TB/rdc_train_right_flat hexadecimal

add_sig "07_rdc_scan_retry_verify" $RDC/r_rdc_train_scan_clear_active
add_sig "07_rdc_scan_retry_verify" $RDC/r_rdc_train_scan_clear_addr unsigned
add_sig "07_rdc_scan_retry_verify" $RDC/r_rdc_train_start_pending
add_sig "07_rdc_scan_retry_verify" $RDC/rdc_train_wait_cnt unsigned
add_sig "07_rdc_scan_retry_verify" $RDC/rdc_train_timeout_cnt unsigned
add_sig "07_rdc_scan_retry_verify" $RDC/rdc_train_fire_cnt unsigned
add_sig "07_rdc_scan_retry_verify" $RDC/rdc_train_pattern_idx
add_sig "07_rdc_scan_retry_verify" $RDC/rdc_train_pattern_mr_loaded
add_sig "07_rdc_scan_retry_verify" $RDC/rdc_train_pattern_active hexadecimal
add_sig "07_rdc_scan_retry_verify" $RDC/rdc_train_retry_cnt unsigned
add_sig "07_rdc_scan_retry_verify" $RDC/rdc_train_retry_err0 hexadecimal
add_sig "07_rdc_scan_retry_verify" $RDC/rdc_train_retry_err1 hexadecimal
add_sig "07_rdc_scan_retry_verify" $RDC/rdc_train_verify_mode
add_sig "07_rdc_scan_retry_verify" $RDC/rdc_train_verify_round unsigned
add_sig "07_rdc_scan_retry_verify" $RDC/rdc_train_verify_err_bitmap hexadecimal
add_sig "07_rdc_scan_retry_verify" $RDC/rdc_train_win_active hexadecimal
add_sig "07_rdc_scan_retry_verify" $RDC/rdc_train_win_len_flat hexadecimal
add_sig "07_rdc_scan_retry_verify" $RDC/rdc_train_best_len_flat hexadecimal
add_sig "07_rdc_scan_retry_verify" $RDC/w_rdc_train_retry_needed
add_sig "07_rdc_scan_retry_verify" $RDC/w_rdc_train_last_tap
add_sig "07_rdc_scan_retry_verify" $RDC/w_rdc_train_window_fail_mask hexadecimal

# These groups expose every visible signal in the initialization path. The
# focused groups above stay at the top so the large all-signal groups can be
# collapsed when only the main sequence is being inspected.
add_scope "90_scheduler_all_signals" $SCH 0
add_scope "91_init_all_signals" $INIT 0
add_scope "92_rdc_all_signals_and_memory" $RDC 1
add_scope "93_external_serdes_all_signals" $TB/U_RESET_SERDES 1
add_scope "93_external_serdes_all_signals" $TB/U_CK_SERDES 1
add_scope "93_external_serdes_all_signals" $TB/U_CS_SERDES 1
for {set ca_idx 0} {$ca_idx < 7} {incr ca_idx} {
    set ca_scope [format {%s/GEN_CA_SERDES[%d]/U_CA_SERDES} $TB $ca_idx]
    add_scope "93_external_serdes_all_signals" $ca_scope 1
}
for {set wck_idx 0} {$wck_idx < 2} {incr wck_idx} {
    set wck_scope [format {%s/GEN_WCK_SERDES[%d]/U_WCK_SERDES} $TB $wck_idx]
    add_scope "93_external_serdes_all_signals" $wck_scope 1
}

TreeUpdate [SetDefaultTree]
WaveRestoreZoom {0 ns} {20 us}
