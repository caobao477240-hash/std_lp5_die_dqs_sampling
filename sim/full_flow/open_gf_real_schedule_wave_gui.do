# Real full-flow GF front scheduling waveform.
# This is not the engine-only testbench. It uses the existing full-flow TB:
#   tb_init_gf_pinout -> lpddr5_dut1 -> lpddr5_gf/lpddr5_test_scheduler
#                    -> lpddr5_gf_engine -> lpddr5_channel/PHY/pins
#
# Launch:
#   E:/modelism/win64/vsim.exe -do E:/project/std_lp5_die_clk800M/sim/full_flow/open_gf_real_schedule_wave_gui.do

transcript on

set PROJ_ROOT     "E:/project/std_lp5_die_clk800M"
set RTL_ROOT      "$PROJ_ROOT/src"
set SIM_ROOT      "$PROJ_ROOT/sim/full_flow"
set XILINX_SIMLIB "E:/xilinx_simlib"
set VIVADO_ROOT   "E:/AMD/Vivado/2022.2"
set GUI_LIB       "$SIM_ROOT/work_gf_real_schedule_wave"

cd $SIM_ROOT
transcript file "$SIM_ROOT/transcript_gf_real_schedule_wave.log"

if {[file exists $GUI_LIB]} {
    vdel -lib $GUI_LIB -all
}

vmap -c
vlib $GUI_LIB
vmap work_gf_real_schedule_wave $GUI_LIB
vmap unisims_ver "$XILINX_SIMLIB/unisims_ver"
vmap unisim      "$XILINX_SIMLIB/unisim"
vmap xpm         "$XILINX_SIMLIB/xpm"
vmap secureip    "$XILINX_SIMLIB/secureip"

vlog -work work_gf_real_schedule_wave -sv \
    +define+LP5_SIM_FAST \
    +define+LP5_SIM_ONE_ROW_GF \
    +incdir+$RTL_ROOT/def \
    "$PROJ_ROOT/ip/clk/sys_clk/clk_wiz_0/clk_wiz_0.v" \
    "$PROJ_ROOT/ip/clk/sys_clk/clk_wiz_0/clk_wiz_0_clk_wiz.v" \
    "$RTL_ROOT/lpddr5/BLOCK64.v" \
    "$RTL_ROOT/lpddr5/lpddr5_init.v" \
    "$RTL_ROOT/lpddr5/lpddr5_idd.v" \
    "$RTL_ROOT/lpddr5/rdc_train.v" \
    "$RTL_ROOT/lpddr5/lpddr5_gf_top.v" \
    "$RTL_ROOT/lpddr5/lpddr5_gf_refresh_ctrl.v" \
    "$RTL_ROOT/lpddr5/lpddr5_gf_stream_timer.v" \
    "$RTL_ROOT/lpddr5/lpddr5_gf_engine.v" \
    "$RTL_ROOT/lpddr5/lpddr5_test_scheduler.v" \
    "$RTL_ROOT/lpddr5/lpddr5_dqs_serdes_phy.v" \
    "$RTL_ROOT/lpddr5/lpddr5_ch_a_phy_io.v" \
    "$RTL_ROOT/lpddr5/lpddr5_channel.v" \
    "$RTL_ROOT/lpddr5/lpddr5_dut1.v" \
    "$PROJ_ROOT/ip/ila/ila_0/sim/ila_0.v" \
    "$SIM_ROOT/tb_init_gf_pinout.v" \
    "$VIVADO_ROOT/data/verilog/src/glbl.v"

vsim -t ps -voptargs=+acc -wlf "$SIM_ROOT/gf_real_schedule_wave.wlf" \
    -L work_gf_real_schedule_wave -L unisims_ver -L unisim -L xpm -L secureip \
    work_gf_real_schedule_wave.tb_init_gf_pinout work_gf_real_schedule_wave.glbl

onfinish stop

proc add_sig {group_name signal_name {radix_name ""}} {
    if {$radix_name == ""} {
        if {[catch {quietly add wave -noupdate -group $group_name $signal_name} msg]} {
            puts "WAVE SKIP: $signal_name"
        }
    } else {
        if {[catch {quietly add wave -noupdate -group $group_name -radix $radix_name $signal_name} msg]} {
            puts "WAVE SKIP: $signal_name"
        }
    }
}

set TB    "sim:/tb_init_gf_pinout"
set DUT   "$TB/u_dut"
set GF    "$DUT/U_lpddr5_gf"
set SCH   "$DUT/U_lpddr5_test_scheduler"
set ENG   "$SCH/U_lpddr5_gf_engine"
set CH    "$DUT/U_lpddr5_channel"
set PHY   "$CH/U_lpddr5_ch_a_phy_io/U_lpddr5_dqs_serdes_phy"

if {[batch_mode] == 0} {
    view wave
    delete wave *
    configure wave -namecolwidth 340
    configure wave -valuecolwidth 180
    configure wave -timelineunits ns
}

add_sig "00_tb_top_control" $TB/sys_clk_p
add_sig "00_tb_top_control" $TB/pll_locked
add_sig "00_tb_top_control" $TB/clk_200m
add_sig "00_tb_top_control" $TB/clk_400m
add_sig "00_tb_top_control" $TB/clk_400m_wck90
add_sig "00_tb_top_control" $TB/clk_400m_rx
add_sig "00_tb_top_control" $TB/init_en
add_sig "00_tb_top_control" $TB/init_done
add_sig "00_tb_top_control" $TB/gf_total_en
add_sig "00_tb_top_control" $TB/gf_total_done
add_sig "00_tb_top_control" $TB/gf_result_data hexadecimal
add_sig "00_tb_top_control" $TB/gf_fail_aux_result hexadecimal
add_sig "00_tb_top_control" $TB/gf_wait unsigned

add_sig "01_external_lpddr5_pins" $TB/reset_n_a
add_sig "01_external_lpddr5_pins" $TB/ck_t_a
add_sig "01_external_lpddr5_pins" $TB/ck_c_a
add_sig "01_external_lpddr5_pins" $TB/cs0_a
add_sig "01_external_lpddr5_pins" $TB/ca_a hexadecimal
add_sig "01_external_lpddr5_pins" $TB/wck_t_a binary
add_sig "01_external_lpddr5_pins" $TB/wck_c_a binary
add_sig "01_external_lpddr5_pins" $TB/dq_a hexadecimal
add_sig "01_external_lpddr5_pins" $TB/dmi_a hexadecimal
add_sig "01_external_lpddr5_pins" $TB/rdqs_t_a binary
add_sig "01_external_lpddr5_pins" $TB/rdqs_c_a binary

add_sig "02_gf_top_real_range" $GF/GF_total_en
add_sig "02_gf_top_real_range" $GF/GF_total_done
add_sig "02_gf_top_real_range" $GF/cha_inner_done_cnt unsigned
add_sig "02_gf_top_real_range" $GF/gf_op_mode unsigned
add_sig "02_gf_top_real_range" $GF/gf_read_data_sel
add_sig "02_gf_top_real_range" $GF/gf_write_data_sel
add_sig "02_gf_top_real_range" $GF/march_y_sequence
add_sig "02_gf_top_real_range" $GF/cha_GF_inner_en
add_sig "02_gf_top_real_range" $GF/cha_GF_inner_done
add_sig "02_gf_top_real_range" $GF/cha_GF_start_col unsigned
add_sig "02_gf_top_real_range" $GF/cha_GF_end_col unsigned
add_sig "02_gf_top_real_range" $GF/cha_GF_start_row unsigned
add_sig "02_gf_top_real_range" $GF/cha_GF_end_row unsigned
add_sig "02_gf_top_real_range" $GF/cha_GF_start_bg unsigned
add_sig "02_gf_top_real_range" $GF/cha_GF_end_bg unsigned
add_sig "02_gf_top_real_range" $GF/cha_GF_start_ba unsigned
add_sig "02_gf_top_real_range" $GF/cha_GF_end_ba unsigned

add_sig "03_scheduler_path" $SCH/chn_state binary
add_sig "03_scheduler_path" $SCH/dbg_ascii_stc ascii
add_sig "03_scheduler_path" $SCH/gf_total_start
add_sig "03_scheduler_path" $SCH/gf_inner_start
add_sig "03_scheduler_path" $SCH/gf_inner_done
add_sig "03_scheduler_path" $SCH/gf_op_mode unsigned
add_sig "03_scheduler_path" $SCH/gf_read_data_sel
add_sig "03_scheduler_path" $SCH/gf_write_data_sel
add_sig "03_scheduler_path" $SCH/gf_march_y_mode
add_sig "03_scheduler_path" $SCH/gf_start_col unsigned
add_sig "03_scheduler_path" $SCH/gf_end_col unsigned
add_sig "03_scheduler_path" $SCH/gf_start_row unsigned
add_sig "03_scheduler_path" $SCH/gf_end_row unsigned
add_sig "03_scheduler_path" $SCH/gf_start_bg unsigned
add_sig "03_scheduler_path" $SCH/gf_end_bg unsigned
add_sig "03_scheduler_path" $SCH/gf_start_ba unsigned
add_sig "03_scheduler_path" $SCH/gf_end_ba unsigned

add_sig "04_engine_state_addr" $ENG/ascii_state ascii
add_sig "04_engine_state_addr" $ENG/state_c hexadecimal
add_sig "04_engine_state_addr" $ENG/state_n hexadecimal
add_sig "04_engine_state_addr" $ENG/gf_en_read
add_sig "04_engine_state_addr" $ENG/gf_en_write
add_sig "04_engine_state_addr" $ENG/gf_pass_start
add_sig "04_engine_state_addr" $ENG/gf_pass_start_d
add_sig "04_engine_state_addr" $ENG/cnt_act unsigned
add_sig "04_engine_state_addr" $ENG/cnt_read unsigned
add_sig "04_engine_state_addr" $ENG/cnt_write unsigned
add_sig "04_engine_state_addr" $ENG/gf_cnt_col unsigned
add_sig "04_engine_state_addr" $ENG/gf_cnt_row unsigned
add_sig "04_engine_state_addr" $ENG/gf_cnt_bg unsigned
add_sig "04_engine_state_addr" $ENG/gf_cnt_ba unsigned
add_sig "04_engine_state_addr" $ENG/cnt_col_ns unsigned
add_sig "04_engine_state_addr" $ENG/gf_cnt_row_ns unsigned
add_sig "04_engine_state_addr" $ENG/w_access_col unsigned
add_sig "04_engine_state_addr" $ENG/w_access_row unsigned
add_sig "04_engine_state_addr" $ENG/w_bank_count unsigned
add_sig "04_engine_state_addr" $ENG/w_rd_last_gap_cnt unsigned
add_sig "04_engine_state_addr" $ENG/w_wr_last_gap_cnt unsigned
add_sig "04_engine_state_addr" $ENG/w_rd_last_cmd_start_cnt unsigned
add_sig "04_engine_state_addr" $ENG/w_wr_last_cmd_start_cnt unsigned

add_sig "05_real_cmd_slots" $ENG/GF_CMD_START_CNT unsigned
add_sig "05_real_cmd_slots" $ENG/w_act_cmd_gap_cnt unsigned
add_sig "05_real_cmd_slots" $ENG/w_rd_cmd_gap_cnt unsigned
add_sig "05_real_cmd_slots" $ENG/w_wr_cmd_gap_cnt unsigned
add_sig "05_real_cmd_slots" $ENG/w_pre_cmd_gap_cnt unsigned
add_sig "05_real_cmd_slots" $ENG/w_act_cmd_gap_latched unsigned
add_sig "05_real_cmd_slots" $ENG/w_rd_cmd_gap_latched unsigned
add_sig "05_real_cmd_slots" $ENG/w_wr_cmd_gap_latched unsigned
add_sig "05_real_cmd_slots" $ENG/w_pre_cmd_gap_latched unsigned
add_sig "05_real_cmd_slots" $ENG/w_act_cmd_first
add_sig "05_real_cmd_slots" $ENG/w_act_cmd_second
add_sig "05_real_cmd_slots" $ENG/w_act_cmd_slot unsigned
add_sig "05_real_cmd_slots" $ENG/w_act_next_cmd_cnt_dbg unsigned
add_sig "05_real_cmd_slots" $ENG/w_act_cmd_done
add_sig "05_real_cmd_slots" $ENG/w_act_bank_index unsigned
add_sig "05_real_cmd_slots" $ENG/w_act_bg unsigned
add_sig "05_real_cmd_slots" $ENG/w_act_ba unsigned
add_sig "05_real_cmd_slots" $ENG/w_read_cmd_first
add_sig "05_real_cmd_slots" $ENG/w_read_cmd_second
add_sig "05_real_cmd_slots" $ENG/w_read_cmd_slot unsigned
add_sig "05_real_cmd_slots" $ENG/w_read_next_cmd_cnt_dbg unsigned
add_sig "05_real_cmd_slots" $ENG/w_read_cmd_done
add_sig "05_real_cmd_slots" $ENG/w_read_bank_index unsigned
add_sig "05_real_cmd_slots" $ENG/w_read_bg unsigned
add_sig "05_real_cmd_slots" $ENG/w_read_ba unsigned
add_sig "05_real_cmd_slots" $ENG/w_write_cmd_first
add_sig "05_real_cmd_slots" $ENG/w_write_cmd_second
add_sig "05_real_cmd_slots" $ENG/w_write_cmd_slot unsigned
add_sig "05_real_cmd_slots" $ENG/w_write_next_cmd_cnt_dbg unsigned
add_sig "05_real_cmd_slots" $ENG/w_write_cmd_done
add_sig "05_real_cmd_slots" $ENG/w_write_bank_index unsigned
add_sig "05_real_cmd_slots" $ENG/w_write_bg unsigned
add_sig "05_real_cmd_slots" $ENG/w_write_ba unsigned

add_sig "06_write_payload_real" $ENG/GF_WR_PAYLOAD_START_CNT unsigned
add_sig "06_write_payload_real" $ENG/GF_WR_OE_START_CNT unsigned
add_sig "06_write_payload_real" $ENG/w_wr_dq_oe_last_cnt unsigned
add_sig "06_write_payload_real" $ENG/w_wr_dq_oe_active
add_sig "06_write_payload_real" $ENG/w_write_payload_rel unsigned
add_sig "06_write_payload_real" $ENG/w_write_payload_slot unsigned
add_sig "06_write_payload_real" $ENG/w_write_data_slot unsigned
add_sig "06_write_payload_real" $ENG/w_write_payload_fire_slot unsigned
add_sig "06_write_payload_real" $ENG/w_write_next_payload_cnt_dbg unsigned
add_sig "06_write_payload_real" $ENG/w_write_payload_done
add_sig "06_write_payload_real" $ENG/w_write_data_bank_index unsigned
add_sig "06_write_payload_real" $ENG/w_write_data_bg unsigned
add_sig "06_write_payload_real" $ENG/w_write_data_ba unsigned
add_sig "06_write_payload_real" $ENG/w_write_march_word hexadecimal
add_sig "06_write_payload_real" $ENG/wave_dq_oe
add_sig "06_write_payload_real" $ENG/wave_dq_a_tx_word hexadecimal
add_sig "06_write_payload_real" $SCH/gf_wave_dq_oe
add_sig "06_write_payload_real" $SCH/gf_wave_dq_a_tx_word hexadecimal
add_sig "06_write_payload_real" $DUT/channel_dq_oe
add_sig "06_write_payload_real" $DUT/channel_dq_a_tx_word hexadecimal
add_sig "06_write_payload_real" $PHY/dq_t_ser hexadecimal
add_sig "06_write_payload_real" $PHY/dmi_t_ser hexadecimal

add_sig "07_read_capture_fifo_real" $ENG/read_capture_start_cnt unsigned
add_sig "07_read_capture_fifo_real" $ENG/w_read_capture_fire
add_sig "07_read_capture_fifo_real" $ENG/w_read_capture_slot unsigned
add_sig "07_read_capture_fifo_real" $ENG/w_read_next_capture_cnt_dbg unsigned
add_sig "07_read_capture_fifo_real" $ENG/w_read_capture_done
add_sig "07_read_capture_fifo_real" $ENG/w_read_fifo_push
add_sig "07_read_capture_fifo_real" $ENG/w_read_fifo_pop
add_sig "07_read_capture_fifo_real" $ENG/w_read_fifo_empty
add_sig "07_read_capture_fifo_real" $ENG/rd_fifo_level unsigned
add_sig "07_read_capture_fifo_real" $ENG/rd_fifo_wr_ptr unsigned
add_sig "07_read_capture_fifo_real" $ENG/rd_fifo_rd_ptr unsigned
add_sig "07_read_capture_fifo_real" $ENG/w_read_expected_beat hexadecimal
add_sig "07_read_capture_fifo_real" $ENG/w_fifo_expected_beat hexadecimal
add_sig "07_read_capture_fifo_real" $ENG/gf_access_addr hexadecimal
add_sig "07_read_capture_fifo_real" $ENG/gf_read_expected_beat hexadecimal
add_sig "07_read_capture_fifo_real" $ENG/compare_valid_r
add_sig "07_read_capture_fifo_real" $ENG/compare_window_r
add_sig "07_read_capture_fifo_real" $ENG/compare_access_addr_r hexadecimal
add_sig "07_read_capture_fifo_real" $ENG/compare_access_addr_dly_r hexadecimal
add_sig "07_read_capture_fifo_real" $ENG/compare_expected_beat_r hexadecimal
add_sig "07_read_capture_fifo_real" $ENG/compare_expected_dly_r hexadecimal
add_sig "07_read_capture_fifo_real" $ENG/compare_burst_r hexadecimal
add_sig "07_read_capture_fifo_real" $ENG/dq_a_burst_valid
add_sig "07_read_capture_fifo_real" $ENG/dq_a_burst_flat hexadecimal
add_sig "07_read_capture_fifo_real" $ENG/gf_compare_window
add_sig "07_read_capture_fifo_real" $ENG/gf_compare_mismatch_odd
add_sig "07_read_capture_fifo_real" $ENG/gf_compare_mismatch_even
add_sig "07_read_capture_fifo_real" $ENG/err_cnt_GF unsigned

add_sig "08_wck_ca_internal_real" $ENG/w_wck_rd_active
add_sig "08_wck_ca_internal_real" $ENG/w_wck_wr_active
add_sig "08_wck_ca_internal_real" $ENG/wave_ck_a_run_en
add_sig "08_wck_ca_internal_real" $ENG/wave_cs_a_0_fall
add_sig "08_wck_ca_internal_real" $ENG/wave_cs_a_0_rise
add_sig "08_wck_ca_internal_real" $ENG/wave_ca_a_fall hexadecimal
add_sig "08_wck_ca_internal_real" $ENG/wave_ca_a_rise hexadecimal
add_sig "08_wck_ca_internal_real" $ENG/wave_wck_a_run_en binary
add_sig "08_wck_ca_internal_real" $ENG/wave_wck_a_phase binary
add_sig "08_wck_ca_internal_real" $DUT/channel_ca_a_fall hexadecimal
add_sig "08_wck_ca_internal_real" $DUT/channel_ca_a_rise hexadecimal
add_sig "08_wck_ca_internal_real" $DUT/channel_wck_a_run_en binary
add_sig "08_wck_ca_internal_real" $DUT/channel_wck_a_phase binary

add_sig "09_phy_rx_real" $DUT/channel_rx_dq_capture_en
add_sig "09_phy_rx_real" $DUT/dq_a_word_valid
add_sig "09_phy_rx_real" $DUT/dq_a_word_flat hexadecimal
add_sig "09_phy_rx_real" $DUT/dq_a_burst_valid
add_sig "09_phy_rx_real" $DUT/dq_a_burst_flat hexadecimal
add_sig "09_phy_rx_real" $PHY/rx_capture_start
add_sig "09_phy_rx_real" $PHY/rx_capture_req_pipe binary
add_sig "09_phy_rx_real" $PHY/dq_a_word_valid
add_sig "09_phy_rx_real" $PHY/dq_a_word_flat hexadecimal
add_sig "09_phy_rx_real" $PHY/dq_a_burst_valid
add_sig "09_phy_rx_real" $PHY/dq_a_burst_flat hexadecimal

if {[batch_mode] == 0} {
    TreeUpdate [SetDefaultTree]
    update
}

puts ""
puts "Real RTL GF schedule wave is ready."
puts "This wave uses tb_init_gf_pinout and the full lpddr5_dut1 RTL chain."
puts "LP5_SIM_ONE_ROW_GF shortens the real GF range to 1 row, 4 columns, BA0..BA1."
puts "The default zoom shows the first real READ_WRITE section."
puts ""

run 5600 ns

if {[batch_mode] == 0} {
    WaveRestoreZoom {2700 ns} {3150 ns}
    update
}
