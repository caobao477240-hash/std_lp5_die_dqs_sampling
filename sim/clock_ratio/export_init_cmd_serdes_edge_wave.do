set SIM_ROOT "E:/project/std_lp5_die_clk800M/sim/clock_ratio"

do "$SIM_ROOT/run_init_cmd_serdes_edge.do"

write wave "$SIM_ROOT/init_overview_wave.ps" \
    -start 0ns -end 1240ns -landscape -width 16 -height 9

write wave "$SIM_ROOT/init_mrw_ca_ck_wave.ps" \
    -start 540ns -end 700ns -landscape -width 16 -height 9

write wave "$SIM_ROOT/init_mrr_wck_wave.ps" \
    -start 900ns -end 1240ns -landscape -width 16 -height 9

quit -f
