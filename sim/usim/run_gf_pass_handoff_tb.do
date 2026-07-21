## Focused GF WRITE-to-READ pass-handoff regression.
## Run: E:/modelism/win64/vsim.exe -c -do run_gf_pass_handoff_tb.do
set PROJ "E:/project/std_lp5_die_clk800M"

if {[file exists work]} { vdel -lib work -all }
vlib work

vlog \
    $PROJ/src/lpddr5/BLOCK64.v \
    $PROJ/src/lpddr5/lpddr5_gf_top.v \
    $PROJ/src/lpddr5/lpddr5_gf_refresh_ctrl.v \
    $PROJ/src/lpddr5/lpddr5_gf_stream_timer.v \
    $PROJ/src/lpddr5/lpddr5_gf_engine.v \
    $PROJ/sim/usim/tb_lpddr5_gf_pass_handoff.v

vsim -c -onfinish stop work.tb_lpddr5_gf_pass_handoff
run -all
quit -sim

vsim -c -onfinish stop -gEND_COL_TEST=63 -gEND_ROW_TEST=0 -gPASS_COUNT=6 -gT_REFI_TEST=781 work.tb_lpddr5_gf_pass_handoff
run -all
quit -f
