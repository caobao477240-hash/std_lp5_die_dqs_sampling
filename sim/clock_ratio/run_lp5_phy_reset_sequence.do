set PROJ_ROOT "E:/project/std_lp5_die_clk800M"
set SIM_ROOT  "$PROJ_ROOT/sim/clock_ratio"

cd $SIM_ROOT

if {[file exists work]} {
    file delete -force work
}

vlib work

vlog -sv \
    "$PROJ_ROOT/src/clock/clock_manage_top.sv" \
    "$SIM_ROOT/tb_lp5_phy_reset_sequence.v"

vsim -t ps work.tb_lp5_phy_reset_sequence
run -all
quit -f
