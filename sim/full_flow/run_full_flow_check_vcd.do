set PROJ_ROOT "E:/project/std_lp5_die_clk800M"
set RTL_ROOT  "$PROJ_ROOT/src"
set SIM_ROOT  "$PROJ_ROOT/sim/full_flow"
set XILINX_SIMLIB "E:/xilinx_simlib"
set VIVADO_ROOT "E:/AMD/Vivado/2022.2"

cd $SIM_ROOT
transcript file "$SIM_ROOT/transcript_full_flow_check.log"

set CHECK_LIB "$SIM_ROOT/work_full_check"
if {[file exists $CHECK_LIB]} {
    vdel -lib $CHECK_LIB -all
}

vmap -c
vlib $CHECK_LIB
vmap work_full_check $CHECK_LIB
vmap unisims_ver "$XILINX_SIMLIB/unisims_ver"
vmap unisim      "$XILINX_SIMLIB/unisim"
vmap xpm         "$XILINX_SIMLIB/xpm"
vmap secureip    "$XILINX_SIMLIB/secureip"

vlog -work work_full_check -sv +define+LP5_SIM_FAST +define+LP5_SIM_ONE_ROW_GF +incdir+$RTL_ROOT/def \
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

vsim -t ps -voptargs=+acc -wlf "$SIM_ROOT/full_flow_check.wlf" \
    -L work_full_check -L unisims_ver -L unisim -L xpm -L secureip \
    work_full_check.tb_init_gf_pinout work_full_check.glbl

vcd file "$SIM_ROOT/full_flow_check_wave.vcd"
vcd add /tb_init_gf_pinout/clk_200m
vcd add /tb_init_gf_pinout/clk_400m
vcd add /tb_init_gf_pinout/clk_400m_div
vcd add /tb_init_gf_pinout/clk_400m_wck90
vcd add /tb_init_gf_pinout/clk_400m_wck90_div
vcd add /tb_init_gf_pinout/clk_400m_rx
vcd add /tb_init_gf_pinout/ck_t_a
vcd add /tb_init_gf_pinout/ck_c_a
vcd add /tb_init_gf_pinout/cs0_a
vcd add /tb_init_gf_pinout/ca_a
vcd add /tb_init_gf_pinout/dq_a
vcd add /tb_init_gf_pinout/wck_t_a
vcd add /tb_init_gf_pinout/gf_en_write
vcd add /tb_init_gf_pinout/gf_en_read
vcd add /tb_init_gf_pinout/gf_dq_oe
vcd add /tb_init_gf_pinout/gf_cnt_write
vcd add /tb_init_gf_pinout/gf_cnt_read
vcd add /tb_init_gf_pinout/gf_tx_word

run -all
vcd flush
quit -f
