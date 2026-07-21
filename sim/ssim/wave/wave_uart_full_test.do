quietly WaveActivateNextPane {} 0
quietly onerror {resume}

if {[catch {delete wave *}]} {}

add wave -divider {TB / UART Command}
add wave -radix binary  -color Cyan   sim:/tb_uart_full_test_cmd/clk
add wave -radix binary  -color Yellow sim:/tb_uart_full_test_cmd/rst_n
add wave -radix ascii   sim:/tb_uart_full_test_cmd/current_cmd_name
add wave -radix unsigned sim:/tb_uart_full_test_cmd/current_cmd_id
add wave -radix binary  -color Orange sim:/tb_uart_full_test_cmd/uart_rx
add wave -radix binary  -color Green  sim:/tb_uart_full_test_cmd/uart_tx
add wave -radix unsigned sim:/tb_uart_full_test_cmd/rx_count

add wave -divider {UART Protocol / SIR}
add wave -radix hex sim:/tb_uart_full_test_cmd/u_uart_top/rx_data
add wave -radix binary sim:/tb_uart_full_test_cmd/u_uart_top/rx_wren
add wave -radix binary sim:/tb_uart_full_test_cmd/u_uart_top/txfifo_wren
add wave -radix hex sim:/tb_uart_full_test_cmd/u_uart_top/txfifo_data
add wave -radix binary -color Yellow sim:/tb_uart_full_test_cmd/u_uart_top/protocol_ctrl_u0/sir_sel
add wave -radix hex    -color Yellow sim:/tb_uart_full_test_cmd/u_uart_top/protocol_ctrl_u0/sir_addr
add wave -radix binary -color Yellow sim:/tb_uart_full_test_cmd/u_uart_top/protocol_ctrl_u0/sir_read
add wave -radix hex sim:/tb_uart_full_test_cmd/u_uart_top/protocol_ctrl_u0/sir_wdat
add wave -radix hex sim:/tb_uart_full_test_cmd/u_uart_top/protocol_ctrl_u0/sir_rdat
add wave -radix binary sim:/tb_uart_full_test_cmd/u_uart_top/protocol_ctrl_u0/sir_dack

add wave -divider {BAR04 Init / IDD}
add wave -radix binary -color Green  sim:/tb_uart_full_test_cmd/u_bar/u_bar04/init_start
add wave -radix binary -color Green  sim:/tb_uart_full_test_cmd/u_bar/u_bar04/init_done
add wave -radix hex    -color Green  sim:/tb_uart_full_test_cmd/u_bar/u_bar04/init_finish
add wave -radix binary -color Yellow sim:/tb_uart_full_test_cmd/u_bar/u_bar04/idd6_start
add wave -radix binary -color Yellow sim:/tb_uart_full_test_cmd/u_bar/u_bar04/idd6_done
add wave -radix hex    -color Yellow sim:/tb_uart_full_test_cmd/u_bar/u_bar04/idd6_finish
add wave -radix hex    sim:/tb_uart_full_test_cmd/u_bar/u_bar04/idd6_info_reg
add wave -radix hex    sim:/tb_uart_full_test_cmd/idd_en
add wave -radix binary sim:/tb_uart_full_test_cmd/idd_done

add wave -divider {BAR05 GF}
add wave -radix binary -color Magenta sim:/tb_uart_full_test_cmd/u_bar/u_bar05/gf_start
add wave -radix binary -color Magenta sim:/tb_uart_full_test_cmd/u_bar/u_bar05/gf_done
add wave -radix hex    -color Magenta sim:/tb_uart_full_test_cmd/u_bar/u_bar05/gf_result_reg
add wave -radix hex    sim:/tb_uart_full_test_cmd/u_bar/u_bar05/bad_block_info_reg
add wave -radix unsigned sim:/tb_uart_full_test_cmd/u_bar/u_bar05/cnt_bad_block_reg
add wave -radix hex    sim:/tb_uart_full_test_cmd/lp5_gf_result
add wave -radix hex    sim:/tb_uart_full_test_cmd/lp5_gf_err_block_msg
add wave -radix unsigned sim:/tb_uart_full_test_cmd/lp5_gf_err_block_cnt

add wave -divider {Scheduler}
add wave -radix binary -color White   sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/runtime_req_allowed
add wave -radix binary -color Green   sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/init_enb_lock
add wave -radix binary -color Yellow  sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/idd_enb_lock
add wave -radix binary -color Magenta sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/gf_enb_lock
add wave -radix binary sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/schedule_idd_req
add wave -radix binary sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/idd_req_pending
add wave -radix binary sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/idd_req_inflight
add wave -radix binary sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/chn_state
add wave -radix ascii  sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/ASCII_STC

add wave -divider {INIT Engine}
add wave -radix ascii  sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/init_ascii_state
add wave -radix binary sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/init_busy
add wave -radix binary sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/init_done
add wave -radix unsigned sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/init_state
add wave -radix binary sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/init_runtime_mr_busy
add wave -radix binary sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/init_rdc_sample_en

add wave -divider {IDD Engine}
add wave -radix ascii  sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/idd_ascii_state
add wave -radix binary sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/idd_busy
add wave -radix binary sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/idd_ref_done
add wave -radix unsigned sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/idd_state
add wave -radix binary sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/idd_ck_stop

add wave -divider {GF Top / Engine}
add wave -radix binary -color Magenta sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_gf/GF_total_en
add wave -radix binary -color Magenta sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_gf/GF_total_done
add wave -radix binary sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_gf/cha_GF_inner_en
add wave -radix binary sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_gf/cha_GF_inner_done
add wave -radix unsigned sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_gf/cha_inner_done_cnt
add wave -radix unsigned sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_gf/gf_op_mode
add wave -radix binary sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_gf/march_y_sequence
add wave -radix hex    sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_gf/GF_result_data
add wave -radix hex    sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_gf/result

add wave -radix ascii  sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/gf_ascii_state
add wave -radix hex    sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/gf_engine_state
add wave -radix binary sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/gf_engine_pass_start_d
add wave -radix binary sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/gf_engine_en_write
add wave -radix binary sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/gf_engine_en_read
add wave -radix unsigned sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/gf_engine_cnt_row
add wave -radix unsigned sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/gf_engine_cnt_col
add wave -radix binary sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/gf_compare_window
add wave -radix binary sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/gf_compare_mismatch_odd
add wave -radix binary sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/gf_compare_mismatch_even
add wave -radix unsigned -color Red sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/gf_error_count

add wave -divider {Selected LPDDR5 Wave Bus}
add wave -radix binary -color Cyan sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/channel_ck_a_run_en
add wave -radix binary sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/channel_cs_a_0_fall
add wave -radix binary sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/channel_cs_a_0_rise
add wave -radix hex    sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/channel_ca_a_fall
add wave -radix hex    sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/channel_ca_a_rise
add wave -radix hex    sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/channel_wck_a_run_en
add wave -radix hex    sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/channel_wck_a_phase
add wave -radix hex    sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/channel_dq_a_tx_word
add wave -radix binary sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/U_lpddr5_test_scheduler/channel_dq_oe
add wave -radix hex    sim:/tb_uart_full_test_cmd/u_lpddr5_dut1/dq_a_burst_flat

add wave -divider {LPDDR5 Pins / No DRAM Model}
add wave -radix binary sim:/tb_uart_full_test_cmd/reset_n_a
add wave -radix binary sim:/tb_uart_full_test_cmd/ck_t_a
add wave -radix binary sim:/tb_uart_full_test_cmd/ck_c_a
add wave -radix binary sim:/tb_uart_full_test_cmd/cs0_a
add wave -radix hex    sim:/tb_uart_full_test_cmd/ca_a
add wave -radix hex    sim:/tb_uart_full_test_cmd/wck_t_a
add wave -radix hex    sim:/tb_uart_full_test_cmd/wck_c_a
add wave -radix hex    sim:/tb_uart_full_test_cmd/dq_a
add wave -radix hex    sim:/tb_uart_full_test_cmd/dmi_a
add wave -radix hex    sim:/tb_uart_full_test_cmd/rdqs_t_a
add wave -radix hex    sim:/tb_uart_full_test_cmd/rdqs_c_a

configure wave -namecolwidth 320
configure wave -valuecolwidth 160
configure wave -timelineunits ns
update
