set PROJ_ROOT "E:/project/std_lp5_die_clk800M"
set SIM_ROOT  "$PROJ_ROOT/sim/pmic_i2c"
set RTL_ROOT  "$PROJ_ROOT/src"

onerror {quit -code 1 -f}

cd $SIM_ROOT
transcript file "$SIM_ROOT/transcript_pmic_i2c_ctrl_latch.log"

if {[file exists work]} {
    file delete -force work
}
if {[file exists modelsim.ini]} {
    file delete -force modelsim.ini
}

vlib work

vlog -sv "$RTL_ROOT/peripheral_ctrl/i2c_dri.v"
vlog -sv "$RTL_ROOT/peripheral_ctrl/i2c_cfg.sv"
vlog -sv "$SIM_ROOT/tb_pmic_i2c_ctrl_latch.sv"

vsim -c -t ps -voptargs=+acc work.tb_pmic_i2c_ctrl_latch
run -all
quit -code 0 -f
