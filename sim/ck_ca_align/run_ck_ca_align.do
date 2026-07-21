set PROJ_ROOT "E:/project/std_lp5_die_clk800M"
set RTL_ROOT  "$PROJ_ROOT/src/lpddr5"
set SIM_ROOT  "$PROJ_ROOT/sim/ck_ca_align"
set XILINX_SIMLIB "E:/xilinx_simlib"
set VIVADO_ROOT "E:/AMD/Vivado/2022.2"

cd $SIM_ROOT
transcript file "$SIM_ROOT/ck_ca_align_transcript.log"

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

vlog -work work "$RTL_ROOT/lpddr5_ch_a_phy_io.v"
vlog -work work "$SIM_ROOT/tb_ck_ca_align.v"
vlog -work work "$VIVADO_ROOT/data/verilog/src/glbl.v"

vsim -t ps -L unisims_ver -L unisim -L xpm -L secureip work.tb_ck_ca_align work.glbl
run -all
quit -f
