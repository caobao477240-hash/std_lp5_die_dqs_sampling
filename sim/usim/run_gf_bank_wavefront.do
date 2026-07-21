## Bank-wavefront GF stream regression.
## Run: E:/modelism/win64/vsim.exe -c -do run_gf_bank_wavefront.do
set PROJ "E:/project/std_lp5_die_clk800M"

if {[file exists work]} { vdel -lib work -all }
vlib work

vlog $PROJ/src/lpddr5/BLOCK64.v \
     $PROJ/src/lpddr5/lpddr5_gf_refresh_ctrl.v \
     $PROJ/src/lpddr5/lpddr5_gf_stream_timer.v \
     $PROJ/src/lpddr5/lpddr5_gf_engine.v \
     $PROJ/sim/usim/tb_gf_bank_wavefront.v

vsim -c -onfinish stop -voptargs=+acc work.tb_gf_bank_wavefront
run -all
quit -sim

vsim -c -onfinish stop -voptargs=+acc work.tb_gf_bank_wavefront \
     -gACT_GAP_CYCLES=6 \
     -gRD_GAP_CYCLES=7 \
     -gWR_GAP_CYCLES=11 \
     -gPRE_GAP_CYCLES=7
run -all
quit -f
