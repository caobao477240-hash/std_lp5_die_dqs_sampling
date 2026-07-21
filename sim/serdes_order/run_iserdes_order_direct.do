set PROJ_ROOT "E:/project/std_lp5_die_clk800M"
set SIM_ROOT  "$PROJ_ROOT/sim/serdes_order"
set XILINX_SIMLIB "E:/xilinx_simlib"

cd $SIM_ROOT
transcript file "$SIM_ROOT/iserdes_order_direct_transcript.log"

if {[file exists work]} {
    vdel -lib work -all
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

vlog -sv -work work "$SIM_ROOT/tb_iserdes_order_direct.v"
vlog -work work "E:/AMD/Vivado/2022.2/data/verilog/src/glbl.v"
vsim -t ps -voptargs=+acc -L unisims_ver -L unisim -L xpm -L secureip work.tb_iserdes_order_direct work.glbl
run -all
quit -f
