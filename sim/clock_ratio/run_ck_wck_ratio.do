set PROJ_ROOT "E:/project/std_lp5_die_clk800M"
set RTL_ROOT "$PROJ_ROOT/src/lpddr5"
set SIM_ROOT "$PROJ_ROOT/sim/clock_ratio"
set XILINX_SIMLIB "E:/xilinx_simlib"
set VIVADO_ROOT "E:/AMD/Vivado/2022.2"

transcript file "$SIM_ROOT/transcript"

if {[file exists work]} {
    file delete -force work
}
vlib work

vmap unisims_ver "$XILINX_SIMLIB/unisims_ver"
vmap secureip "$XILINX_SIMLIB/secureip"

vlog -work work -L unisims_ver -L secureip "$RTL_ROOT/lpddr5_ch_a_phy_io.v"
vlog -work work -L unisims_ver -L secureip "$SIM_ROOT/tb_ck_wck_serdes_ratio.v"
vlog -work work "$VIVADO_ROOT/data/verilog/src/glbl.v"

vsim -voptargs=+acc -L unisims_ver -L secureip work.tb_ck_wck_serdes_ratio work.glbl

quietly WaveActivateNextPane {} 0
add wave -divider {Clock Inputs}
add wave -radix binary /tb_ck_wck_serdes_ratio/clk_200m
add wave -radix binary /tb_ck_wck_serdes_ratio/clk_400m
add wave -radix binary /tb_ck_wck_serdes_ratio/rst_n
add wave -radix binary /tb_ck_wck_serdes_ratio/ck_run_en

add wave -divider {LPDDR Outputs}
add wave -radix binary /tb_ck_wck_serdes_ratio/ck_out
add wave -radix binary /tb_ck_wck_serdes_ratio/wck_out
add wave -radix binary /tb_ck_wck_serdes_ratio/ca_out
add wave -radix binary /tb_ck_wck_serdes_ratio/cmd_rise
add wave -radix binary /tb_ck_wck_serdes_ratio/cmd_fall
add wave -radix binary /tb_ck_wck_serdes_ratio/wck_run_en
add wave -radix binary /tb_ck_wck_serdes_ratio/wck_phase

add wave -divider {Counters}
add wave -radix decimal /tb_ck_wck_serdes_ratio/ck_rise_count
add wave -radix decimal /tb_ck_wck_serdes_ratio/wck_rise_count
add wave -radix decimal /tb_ck_wck_serdes_ratio/ck_period_sum
add wave -radix decimal /tb_ck_wck_serdes_ratio/wck_period_sum
add wave -radix decimal /tb_ck_wck_serdes_ratio/error_count

run -all
wave zoom full
