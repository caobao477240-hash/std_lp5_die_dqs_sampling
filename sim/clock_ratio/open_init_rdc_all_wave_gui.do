# Complete LPDDR5 initialization waveform with a short dual-pattern RDC scan.
# The production RTL is unchanged; the testbench limits the scan to taps 0..3.

transcript on

set PROJ_ROOT     "E:/project/std_lp5_die_clk800M"
set RTL_ROOT      "$PROJ_ROOT/src"
set SIM_ROOT      "$PROJ_ROOT/sim/clock_ratio"
set XILINX_SIMLIB "E:/xilinx_simlib"
set VIVADO_ROOT   "E:/AMD/Vivado/2022.2"
set GUI_LIB       "$SIM_ROOT/work_init_rdc_wave"

cd $SIM_ROOT
transcript file "$SIM_ROOT/transcript_init_rdc_wave.log"

if {[file exists $GUI_LIB]} {
    vdel -lib $GUI_LIB -all
}

vmap -c
vlib $GUI_LIB
vmap work_init_rdc_wave $GUI_LIB
vmap unisims_ver "$XILINX_SIMLIB/unisims_ver"
vmap secureip    "$XILINX_SIMLIB/secureip"

vlog -work work_init_rdc_wave -sv \
    +define+LP5_SIM_FAST \
    +incdir+$RTL_ROOT/def \
    "$RTL_ROOT/lpddr5/BLOCK64.v" \
    "$RTL_ROOT/lpddr5/rdc_train.v" \
    "$RTL_ROOT/lpddr5/lpddr5_init.v" \
    "$RTL_ROOT/lpddr5/lpddr5_idd.v" \
    "$RTL_ROOT/lpddr5/lpddr5_gf_refresh_ctrl.v" \
    "$RTL_ROOT/lpddr5/lpddr5_gf_stream_timer.v" \
    "$RTL_ROOT/lpddr5/lpddr5_gf_engine.v" \
    "$RTL_ROOT/lpddr5/lpddr5_test_scheduler.v" \
    "$RTL_ROOT/lpddr5/lpddr5_ch_a_phy_io.v" \
    "$SIM_ROOT/tb_init_rdc_wave.v" \
    "$VIVADO_ROOT/data/verilog/src/glbl.v"

vsim -t ps -voptargs=+acc -wlf "$SIM_ROOT/init_rdc_all_wave.wlf" \
    -L work_init_rdc_wave -L unisims_ver -L secureip \
    work_init_rdc_wave.tb_init_rdc_wave work_init_rdc_wave.glbl

onfinish stop
log -r sim:/tb_init_rdc_wave/*
do "$SIM_ROOT/wave_init_rdc_all.do"

run -all

if {[batch_mode] == 0} {
    wave zoom full
} else {
    quit -f
}
