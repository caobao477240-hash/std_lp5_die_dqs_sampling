vlib work
vmap work work
vlog -sv +define+SIM ../../src/lpddr5/BLOCK64.v ../../src/lpddr5/lpddr5_gf_top.v ../../src/lpddr5/lpddr5_gf_refresh_ctrl.v ../../src/lpddr5/lpddr5_gf_stream_timer.v ../../src/lpddr5/lpddr5_gf_engine.v tb_gf_cmd_truth.v
vsim -c -voptargs=+acc work.tb_gf_cmd_truth -do "run -all; quit -f"
