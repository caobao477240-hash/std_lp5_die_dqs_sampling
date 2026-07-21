set PROJ_ROOT "E:/project/std_lp5_die_clk800M"
set RTL_ROOT  "$PROJ_ROOT/src"
set SIM_ROOT  "$PROJ_ROOT/sim/full_flow"
set XILINX_SIMLIB "E:/xilinx_simlib"
set VIVADO_ROOT "E:/AMD/Vivado/2022.2"

cd $SIM_ROOT
transcript file "$SIM_ROOT/transcript_full_flow_cs_fix_gui.log"

set GUI_LIB "$SIM_ROOT/work_full_gui_cs_fix"
if {[file exists $GUI_LIB]} {
    vdel -lib $GUI_LIB -all
}

vmap -c
vlib $GUI_LIB
vmap work_full_gui_cs_fix $GUI_LIB
vmap unisims_ver "$XILINX_SIMLIB/unisims_ver"
vmap unisim      "$XILINX_SIMLIB/unisim"
vmap xpm         "$XILINX_SIMLIB/xpm"
vmap secureip    "$XILINX_SIMLIB/secureip"

vlog -work work_full_gui_cs_fix -sv +define+LP5_SIM_FAST +define+LP5_SIM_ONE_ROW_GF +incdir+$RTL_ROOT/def \
    "$PROJ_ROOT/ip/clk/sys_clk/clk_wiz_0/clk_wiz_0.v" \
    "$PROJ_ROOT/ip/clk/sys_clk/clk_wiz_0/clk_wiz_0_clk_wiz.v" \
    "$RTL_ROOT/lpddr5/BLOCK64.v" \
    "$RTL_ROOT/lpddr5/lpddr5_init.v" \
    "$RTL_ROOT/lpddr5/rdc_train.v" \
    "$RTL_ROOT/lpddr5/lpddr5_idd.v" \
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

vsim -t ps -voptargs=+acc -wlf "$SIM_ROOT/full_flow_cs_fix_gui.wlf" \
    -L work_full_gui_cs_fix -L unisims_ver -L unisim -L xpm -L secureip \
    work_full_gui_cs_fix.tb_init_gf_pinout work_full_gui_cs_fix.glbl

onfinish stop

add wave -divider "IP Clocks"
add wave -radix binary /tb_init_gf_pinout/sys_clk_p
add wave -radix binary /tb_init_gf_pinout/pll_locked
add wave -radix binary /tb_init_gf_pinout/clk_200m
add wave -radix binary /tb_init_gf_pinout/clk_400m
add wave -radix binary /tb_init_gf_pinout/clk_400m_wck90
add wave -radix binary /tb_init_gf_pinout/clk_400m_rx

add wave -divider "GF Control"
add wave -radix binary /tb_init_gf_pinout/gf_total_en
add wave -radix binary /tb_init_gf_pinout/gf_total_done
add wave -radix binary /tb_init_gf_pinout/gf_en_write
add wave -radix binary /tb_init_gf_pinout/gf_en_read
add wave -radix binary /tb_init_gf_pinout/gf_dq_oe
add wave -radix unsigned /tb_init_gf_pinout/gf_cnt_write
add wave -radix unsigned /tb_init_gf_pinout/gf_cnt_read
add wave -radix hexadecimal /tb_init_gf_pinout/gf_tx_word

add wave -divider "External LPDDR5 Pins"
add wave -radix binary /tb_init_gf_pinout/ck_t_a
add wave -radix binary /tb_init_gf_pinout/ck_c_a
add wave -radix binary /tb_init_gf_pinout/cs0_a
add wave -radix hexadecimal /tb_init_gf_pinout/ca_a
add wave -radix binary /tb_init_gf_pinout/wck_t_a
add wave -radix binary /tb_init_gf_pinout/wck_c_a
add wave -radix hexadecimal /tb_init_gf_pinout/dq_a
add wave -radix hexadecimal /tb_init_gf_pinout/dmi_a
add wave -radix binary /tb_init_gf_pinout/rdqs_t_a
add wave -radix binary /tb_init_gf_pinout/rdqs_c_a

add wave -divider "Scheduler / GF Engine"
add wave -radix unsigned /tb_init_gf_pinout/u_dut/U_lpddr5_test_scheduler/gf_engine_state
add wave -radix unsigned /tb_init_gf_pinout/u_dut/U_lpddr5_test_scheduler/U_lpddr5_gf_engine/data_state
add wave -radix binary /tb_init_gf_pinout/u_dut/U_lpddr5_test_scheduler/gf_wave_wck_a_run_en
add wave -radix binary /tb_init_gf_pinout/u_dut/U_lpddr5_test_scheduler/gf_wave_wck_a_phase
add wave -radix hexadecimal /tb_init_gf_pinout/u_dut/U_lpddr5_test_scheduler/gf_wave_dq_a_tx_word
add wave -radix hexadecimal /tb_init_gf_pinout/u_dut/U_lpddr5_test_scheduler/gf_wave_dq_a_in_dh
add wave -radix hexadecimal /tb_init_gf_pinout/u_dut/U_lpddr5_test_scheduler/gf_wave_dq_a_in_dl

add wave -divider "Channel Drive"
add wave -radix hexadecimal /tb_init_gf_pinout/u_dut/channel_ca_a_rise
add wave -radix hexadecimal /tb_init_gf_pinout/u_dut/channel_ca_a_fall
add wave -radix hexadecimal /tb_init_gf_pinout/u_dut/channel_dq_a_tx_word
add wave -radix binary /tb_init_gf_pinout/u_dut/channel_dq_oe
add wave -radix binary /tb_init_gf_pinout/u_dut/channel_wck_a_phase
add wave -radix binary /tb_init_gf_pinout/u_dut/channel_wck_a_run_en

run -all

WaveRestoreZoom {1940 ns} {2025 ns}
