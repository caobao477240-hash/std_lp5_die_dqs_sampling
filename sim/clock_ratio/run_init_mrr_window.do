set PROJ_ROOT "E:/project/std_lp5_die_clk800M"
set RTL_ROOT "$PROJ_ROOT/src/lpddr5"
set SIM_ROOT "$PROJ_ROOT/sim/clock_ratio"
set XILINX_SIMLIB "E:/xilinx_simlib"

transcript file "$SIM_ROOT/transcript_init_mrr_window"

if {[file exists work]} {
    vdel -lib work -all
}
vlib work

vmap unisims_ver "$XILINX_SIMLIB/unisims_ver"
vmap secureip "$XILINX_SIMLIB/secureip"

vlog -work work +define+LP5_SIM_FAST "$RTL_ROOT/lpddr5_init.v"
vlog -work work "$SIM_ROOT/tb_init_mrr_window.v"

vsim -voptargs=+acc work.tb_init_mrr_window

quietly WaveActivateNextPane {} 0
add wave -divider {Init State}
add wave -radix ascii /tb_init_mrr_window/ascii_state
add wave -radix unsigned /tb_init_mrr_window/init_state
add wave -radix unsigned /tb_init_mrr_window/init_mr_cnt
add wave -radix hex /tb_init_mrr_window/read_capture_start_cnt
add wave -radix binary /tb_init_mrr_window/rx_dq_capture_en
add wave -radix binary /tb_init_mrr_window/dq_a_word_valid
add wave -radix hex /tb_init_mrr_window/dq_a_word_flat
add wave -radix hex /tb_init_mrr_window/die_message
add wave -radix binary /tb_init_mrr_window/init_done

add wave -divider {Command Boundary}
add wave -radix binary /tb_init_mrr_window/wave_ck_a_run_en
add wave -radix binary /tb_init_mrr_window/wave_cs_a_0_fall
add wave -radix binary /tb_init_mrr_window/wave_cs_a_0_rise
add wave -radix hex /tb_init_mrr_window/wave_ca_a_fall
add wave -radix hex /tb_init_mrr_window/wave_ca_a_rise
add wave -radix binary /tb_init_mrr_window/wave_wck_a_run_en

run -all
wave zoom full
