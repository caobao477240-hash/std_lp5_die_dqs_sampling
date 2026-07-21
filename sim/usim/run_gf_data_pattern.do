## Data-pattern integrity under refresh — write & read, forward & reverse.
## Run: E:/modelism/win64/vsim.exe -c -do run_gf_data_pattern.do
set PROJ "E:/project/std_lp5_die_clk800M"

if {[file exists work]} { vdel -lib work -all }
vlib work

vlog $PROJ/src/lpddr5/BLOCK64.v \
     $PROJ/src/lpddr5/lpddr5_gf_top.v \
    $PROJ/src/lpddr5/lpddr5_gf_refresh_ctrl.v \
    $PROJ/src/lpddr5/lpddr5_gf_stream_timer.v \
    $PROJ/src/lpddr5/lpddr5_gf_engine.v \
     $PROJ/sim/usim/tb_gf_data_pattern.v

foreach mode {0 1} {
    foreach march {0 1} {
        foreach rw {0 1} {
            vsim -c -onfinish stop \
                -gRW=$rw \
                -gMARCH=$march \
                -gPATTERN_MODE=$mode \
                work.tb_gf_data_pattern
            run -all
            quit -sim
        }
    }
}

quit -f
