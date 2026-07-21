set PROJ_ROOT "E:/project/std_lp5_die_clk800M"
set SIM_ROOT  "$PROJ_ROOT/sim/wck_dq_align_oddr"
set XILINX_SIMLIB "E:/xilinx_simlib"
set WCK_PHASE_PS 625

if {[info exists ::env(WCK_PHASE_PS)] && ($::env(WCK_PHASE_PS) ne "")} {
    set WCK_PHASE_PS $::env(WCK_PHASE_PS)
}

cd $SIM_ROOT
transcript file "$SIM_ROOT/wck_dq_align_oddr_transcript.log"

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

vlog -work work "$PROJ_ROOT/src/lpddr5/lpddr5_ch_a_phy_io.v"
vlog -sv -work work "$SIM_ROOT/tb_wck_dq_align_oddr.v"
vlog -work work "E:/AMD/Vivado/2022.2/data/verilog/src/glbl.v"
vsim -t ps -voptargs="+acc" -L unisims_ver -L unisim -L xpm -L secureip work.tb_wck_dq_align_oddr work.glbl +WCK_PHASE_PS=$WCK_PHASE_PS
run -all
quit -f
