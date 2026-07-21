set PROJ_ROOT "E:/project/std_lp5_die_clk800M"
set RTL_ROOT "$PROJ_ROOT/src/lpddr5"
set SIM_ROOT "$PROJ_ROOT/sim/clock_ratio"
set XILINX_SIMLIB "E:/xilinx_simlib"
set VIVADO_ROOT "E:/AMD/Vivado/2022.2"

transcript file "$SIM_ROOT/transcript_init_cmd_serdes_edge"

if {[file exists work]} {
    file delete -force work
}
vlib work

vmap unisims_ver "$XILINX_SIMLIB/unisims_ver"
vmap secureip "$XILINX_SIMLIB/secureip"

vlog -work work +define+LP5_SIM_FAST "$RTL_ROOT/rdc_train.v"
vlog -work work +define+LP5_SIM_FAST "$RTL_ROOT/lpddr5_init.v"
vlog -work work -L unisims_ver -L secureip "$RTL_ROOT/lpddr5_ch_a_phy_io.v"
vlog -work work -L unisims_ver -L secureip "$SIM_ROOT/tb_init_cmd_serdes_edge.v"
vlog -work work "$VIVADO_ROOT/data/verilog/src/glbl.v"

vsim -voptargs=+acc -L unisims_ver -L secureip work.tb_init_cmd_serdes_edge work.glbl
onfinish stop

quietly WaveActivateNextPane {} 0
add wave -divider {Fabric Control}
add wave -radix binary /tb_init_cmd_serdes_edge/clk_200m
add wave -radix binary /tb_init_cmd_serdes_edge/clk_400m
add wave -radix binary /tb_init_cmd_serdes_edge/rst_n
add wave -radix binary /tb_init_cmd_serdes_edge/init_en
add wave -radix binary /tb_init_cmd_serdes_edge/U_INIT/w_init_start
add wave -radix binary /tb_init_cmd_serdes_edge/wave_ck_a_run_en
add wave -radix ascii  /tb_init_cmd_serdes_edge/ascii_state
add wave -radix unsigned /tb_init_cmd_serdes_edge/init_state
add wave -radix binary /tb_init_cmd_serdes_edge/U_INIT/r_mr_init_w_cnt_en
add wave -radix unsigned /tb_init_cmd_serdes_edge/U_INIT/r_mr_slot
add wave -radix unsigned /tb_init_cmd_serdes_edge/U_INIT/r_mr_phase
add wave -radix unsigned /tb_init_cmd_serdes_edge/init_mr_cnt
add wave -radix hex /tb_init_cmd_serdes_edge/wave_ca_a_fall
add wave -radix hex /tb_init_cmd_serdes_edge/wave_ca_a_rise
add wave -radix binary /tb_init_cmd_serdes_edge/wave_cs_a_0_fall
add wave -radix binary /tb_init_cmd_serdes_edge/wave_cs_a_0_rise
add wave -radix binary /tb_init_cmd_serdes_edge/wave_wck_a_run_en

add wave -divider {External SERDES Boundary}
add wave -radix binary /tb_init_cmd_serdes_edge/ck_out
add wave -radix binary /tb_init_cmd_serdes_edge/cs_out
add wave -radix hex /tb_init_cmd_serdes_edge/ca_out
add wave -radix binary /tb_init_cmd_serdes_edge/ca0_out
add wave -radix binary /tb_init_cmd_serdes_edge/ca1_out
add wave -radix binary /tb_init_cmd_serdes_edge/wck0_out

add wave -divider {Read Window}
add wave -radix binary /tb_init_cmd_serdes_edge/rx_dq_capture_en
add wave -radix binary /tb_init_cmd_serdes_edge/dq_a_word_valid
add wave -radix hex /tb_init_cmd_serdes_edge/dq_a_word_flat
add wave -radix hex /tb_init_cmd_serdes_edge/die_message
add wave -radix binary /tb_init_cmd_serdes_edge/init_done

run -all
wave zoom full
