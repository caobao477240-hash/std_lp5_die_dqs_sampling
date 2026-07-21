## Focused BAR06 GF stream configuration readback regression.
## Run: E:/modelism/win64/vsim.exe -c -do run_bar06_gf_stream_cfg.do
set PROJ "E:/project/std_lp5_die_clk800M"

if {[file exists work]} { vdel -lib work -all }
vlib work

vlog +incdir+$PROJ/src/def \
    $PROJ/src/bar/bar.sv \
    $PROJ/src/bar/bar06.sv \
    $PROJ/sim/usim/tb_bar06_gf_stream_cfg.sv

vsim -c -onfinish stop work.tb_bar06_gf_stream_cfg
run -all
quit -f
