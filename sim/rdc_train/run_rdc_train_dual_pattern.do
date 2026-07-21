set PROJ_ROOT "E:/project/std_lp5_die_clk800M"
set SIM_ROOT  "$PROJ_ROOT/sim/rdc_train"
set RTL_ROOT  "$PROJ_ROOT/src"

cd $SIM_ROOT
transcript file "$SIM_ROOT/transcript_rdc_train_dual_pattern.log"

if {[file exists work]} {
    file delete -force work
}
if {[file exists modelsim.ini]} {
    file delete -force modelsim.ini
}

vlib work

vlog -sv +incdir+$RTL_ROOT/def "$RTL_ROOT/lpddr5/rdc_train.v"
vlog -sv +incdir+$RTL_ROOT/def "$SIM_ROOT/tb_rdc_train_dual_pattern.v"

vsim -c -t ps -voptargs=+acc work.tb_rdc_train_dual_pattern
run -all
quit -f
