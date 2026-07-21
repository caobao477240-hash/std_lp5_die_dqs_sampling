## Focused GF scheduler refresh insertion regression.
## Run: E:/modelism/win64/vsim.exe -c -do run_gf_refresh_scheduler.do
set PROJ "E:/project/std_lp5_die_clk800M"

if {[file exists work]} { vdel -lib work -all }
vlib work

vlog \
    $PROJ/src/lpddr5/BLOCK64.v \
    $PROJ/src/lpddr5/lpddr5_gf_refresh_ctrl.v \
    $PROJ/src/lpddr5/lpddr5_gf_stream_timer.v \
    $PROJ/src/lpddr5/lpddr5_gf_engine.v \
    $PROJ/sim/usim/tb_gf_refresh_scheduler.v

vsim -c -onfinish stop work.tb_gf_refresh_scheduler
run -all

vsim -c -onfinish stop work.tb_gf_refresh_scheduler -gTRFCAB_TEST=64
run -all

vsim -c -onfinish stop work.tb_gf_refresh_scheduler \
    -gTRFCAB_TEST=64 \
    -gREFRESH_BATCH_TEST=4 \
    -gEND_COL_TEST=15
run -all

vsim -c -onfinish stop work.tb_gf_refresh_scheduler \
    -gTRFCAB_TEST=64 \
    -gREFRESH_BATCH_TEST=8 \
    -gEND_COL_TEST=31
run -all
quit -f
