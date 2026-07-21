# Real clock-chain LPDDR5 INIT waveform.
# The testbench generates only the 200 MHz board reference clock, external
# reset, INIT request, and an ideal DRAM read response. All internal clocks,
# startup reset sequencing, PHY serialization, and pin timing use production
# RTL plus Xilinx simulation primitives.

transcript on

set PROJ_ROOT     "E:/project/std_lp5_die_clk800M"
set RTL_ROOT      "$PROJ_ROOT/src"
set SIM_ROOT      "$PROJ_ROOT/sim/full_flow"
set IP_ROOT       "$PROJ_ROOT/ip"
set XILINX_SIMLIB "E:/xilinx_simlib"
set VIVADO_ROOT   "E:/AMD/Vivado/2022.2"
set GUI_LIB       "$SIM_ROOT/work_init_pll_phy_wave"

cd $SIM_ROOT
transcript file "$SIM_ROOT/transcript_init_pll_phy_wave.log"

if {[file exists $GUI_LIB]} {
    vdel -lib $GUI_LIB -all
}

vmap -c
vlib $GUI_LIB
vmap work_init_pll_phy_wave $GUI_LIB
vmap unisims_ver "$XILINX_SIMLIB/unisims_ver"
vmap unisim      "$XILINX_SIMLIB/unisim"
vmap xpm         "$XILINX_SIMLIB/xpm"
vmap secureip    "$XILINX_SIMLIB/secureip"

vlog -work work_init_pll_phy_wave -sv \
    +define+LP5_SIM_FAST \
    +define+LP5_SIM_ONE_ROW_GF \
    +incdir+$RTL_ROOT/def \
    "$IP_ROOT/clk/sys_clk/clk_wiz_0/clk_wiz_0.v" \
    "$IP_ROOT/clk/sys_clk/clk_wiz_0/clk_wiz_0_clk_wiz.v" \
    "$RTL_ROOT/clock/clock_manage_top.sv" \
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
    "$IP_ROOT/ila/ila_0/sim/ila_0.v" \
    "$SIM_ROOT/tb_init_pll_phy_wave.v" \
    "$VIVADO_ROOT/data/verilog/src/glbl.v"

vsim -t ps -voptargs=+acc \
    -wlf "$SIM_ROOT/init_pll_phy_wave.wlf" \
    -L work_init_pll_phy_wave \
    -L unisims_ver -L unisim -L xpm -L secureip \
    work_init_pll_phy_wave.tb_init_pll_phy_wave \
    work_init_pll_phy_wave.glbl

onfinish stop

set TB      "sim:/tb_init_pll_phy_wave"
set CLOCK   "$TB/U_CLOCK_MANAGE_TOP"
set DUT     "$TB/U_DUT"
set SCH     "$DUT/U_lpddr5_test_scheduler"
set INIT    "$SCH/U_lpddr5_init"
set RDC     "$INIT/rdc_train_u0"
set CHANNEL "$DUT/U_lpddr5_channel"
set PHYIO   "$CHANNEL/U_lpddr5_ch_a_phy_io"
set DQPHY   "$PHYIO/U_lpddr5_dqs_serdes_phy"

# Log every control signal in the clock/startup, scheduler, INIT, RDC,
# channel, and PHY boundary scopes. Selected serializer internals are logged
# recursively; logging all 16 primitive lanes would make the teaching WLF
# needlessly large while duplicating the same per-bit structure.
log $TB/*
log $CLOCK/*
log $SCH/*
log $INIT/*
log $RDC/*
log $CHANNEL/*
log $PHYIO/*
log $DQPHY/*
log -r $PHYIO/U_ck_a_serdes/*
log -r $PHYIO/U_reset_n_a_serdes/*
log -r $PHYIO/U_cs0_a_serdes/*
log -r $PHYIO/GEN_CA_SERDES[0]/U_ca_a_serdes/*
log -r $PHYIO/GEN_WCK_SERDES[0]/U_wck_a_serdes/*
log -r $DQPHY/GEN_DQ_IO[0]/*

do "$SIM_ROOT/wave_init_pll_phy_all.do"

run -all

if {[batch_mode] == 0} {
    wave zoom full
} else {
    quit -f
}

