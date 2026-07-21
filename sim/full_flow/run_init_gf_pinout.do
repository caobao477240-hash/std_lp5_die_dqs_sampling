set PROJ_ROOT "E:/project/std_lp5_die_clk800M"
set RTL_ROOT  "$PROJ_ROOT/src"
set SIM_ROOT  "$PROJ_ROOT/sim/full_flow"
set IP_MODEL_ROOT "E:/project/std_lp5_die_clk800M"
set XILINX_SIMLIB "E:/xilinx_simlib"
set VIVADO_ROOT "E:/AMD/Vivado/2022.2"

cd $SIM_ROOT
transcript file "$SIM_ROOT/transcript_init_gf_pinout.log"

if {[file exists work]} {
    file delete -force work
}
if {[file exists modelsim.ini]} {
    file delete -force modelsim.ini
}

vmap -c
vlib work
vmap unisims_ver "$XILINX_SIMLIB/unisims_ver"
vmap unisim      "$XILINX_SIMLIB/unisim"
vmap xpm         "$XILINX_SIMLIB/xpm"
vmap secureip    "$XILINX_SIMLIB/secureip"

vlog -sv +define+LP5_SIM_FAST +define+LP5_SIM_ONE_ROW_GF +incdir+$RTL_ROOT/def \
    "$IP_MODEL_ROOT/ip/clk/sys_clk/clk_wiz_0/clk_wiz_0.v" \
    "$IP_MODEL_ROOT/ip/clk/sys_clk/clk_wiz_0/clk_wiz_0_clk_wiz.v" \
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
    "$IP_MODEL_ROOT/ip/ila/ila_0/sim/ila_0.v" \
    "$SIM_ROOT/tb_init_gf_pinout.v" \
    "$VIVADO_ROOT/data/verilog/src/glbl.v"

vsim -t ps -voptargs=+acc -L unisims_ver -L unisim -L xpm -L secureip work.tb_init_gf_pinout work.glbl
run -all
quit -f
