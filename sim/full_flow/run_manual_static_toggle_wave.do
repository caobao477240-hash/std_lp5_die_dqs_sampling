vcd file E:/project/std_lp5_die_clk800M/sim/full_flow/init_gf_pinout_wave.vcd
vcd add /tb_init_gf_pinout/gf_cnt_write
vcd add /tb_init_gf_pinout/gf_cnt_read
vcd add /tb_init_gf_pinout/ca_a
vcd add /tb_init_gf_pinout/dq_a
vcd add /tb_init_gf_pinout/wck_t_a
vcd add /tb_init_gf_pinout/u_dut/U_lpddr5_test_scheduler/gf_wave_wck_a_run_en
vcd add /tb_init_gf_pinout/u_dut/U_lpddr5_test_scheduler/gf_wave_wck_a_phase
run -all
vcd flush
quit -f
