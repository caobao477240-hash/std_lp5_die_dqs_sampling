set MODELSIM_EXE E:/modelism/win64/vsim.exe
set XILINX_SIMLIB E:/xilinx_simlib
set VIVADO_ROOT E:/AMD/Vivado/2022.2
set PROJ E:/project/std_lp5_die_clk800M
set RTL $PROJ/src
set SIM $PROJ/sim
set SSIM $SIM/ssim
set TB  $SSIM/tsb

cd $SSIM

proc lp5_delete_if_exists {path} {
    if {[file exists $path]} {
        catch {file delete -force $path}
    }
}

proc lp5_clean_sim_files {} {
    global SIM SSIM

    catch {transcript off}

    if {[file exists $SSIM/work]} {
        catch {vdel -lib work -all}
        catch {file delete -force $SSIM/work}
    }

    lp5_delete_if_exists $SSIM/modelsim.ini
    lp5_delete_if_exists $SSIM/transcript
    lp5_delete_if_exists $SSIM/vsim.wlf
    lp5_delete_if_exists $SSIM/vsim_stacktrace.vstf
}

proc lp5_start_exit_cleaner {} {
    global SSIM

    set pid_now [pid]
    set ps_cmd "Wait-Process -Id $pid_now -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 500; Remove-Item -LiteralPath '$SSIM/work','$SSIM/modelsim.ini','$SSIM/transcript','$SSIM/vsim.wlf','$SSIM/vsim_stacktrace.vstf' -Recurse -Force -ErrorAction SilentlyContinue"
    catch {exec powershell.exe -NoProfile -WindowStyle Hidden -Command $ps_cmd &}
}

proc lp5_install_quit_cleanup {} {
    if {![llength [info commands __lp5_real_quit]] && [llength [info commands quit]]} {
        rename quit __lp5_real_quit
        proc quit {args} {
            catch {__lp5_real_quit -sim}
            lp5_clean_sim_files
            lp5_start_exit_cleaner
            uplevel 1 [list __lp5_real_quit {*}$args]
        }
    }
}

lp5_clean_sim_files

transcript on

if {[file exists work]} {
    vdel -lib work -all
}
vlib work

vmap unisims_ver $XILINX_SIMLIB/unisims_ver
vmap unisim      $XILINX_SIMLIB/unisim
vmap xpm         $XILINX_SIMLIB/xpm
vmap secureip    $XILINX_SIMLIB/secureip

vlog -sv +define+LP5_SIM_FAST +incdir+$RTL/def \
    $TB/fifo_generator_uart_sim_stub.v \
    $RTL/uart/uart_bps_cfg.sv \
    $RTL/uart/uart_rx.sv \
    $RTL/uart/uart_tx.sv \
    $RTL/uart/uart_ctrl.sv \
    $RTL/uart/protocol_ctrl.sv \
    $RTL/uart/uart_top.v \
    $RTL/bar/bar00.sv \
    $RTL/bar/bar03.sv \
    $RTL/bar/bar04.sv \
    $RTL/bar/bar05.sv \
    $RTL/bar/bar06.sv \
    $RTL/bar/bar07.sv \
    $RTL/bar/bar.sv \
    $RTL/peripheral_ctrl/idd_signal_ctrl.v \
    $RTL/lpddr5/BLOCK64.v \
    $RTL/lpddr5/lpddr5_init.v \
    $RTL/lpddr5/rdc_train.v \
    $RTL/lpddr5/lpddr5_idd.v \
    $RTL/lpddr5/lpddr5_gf_top.v \
    $RTL/lpddr5/lpddr5_gf_refresh_ctrl.v \
    $RTL/lpddr5/lpddr5_gf_stream_timer.v \
    $RTL/lpddr5/lpddr5_gf_engine.v \
    $RTL/lpddr5/lpddr5_test_scheduler.v \
    $RTL/lpddr5/lpddr5_dqs_serdes_phy.v \
    $RTL/lpddr5/lpddr5_ch_a_phy_io.v \
    $RTL/lpddr5/lpddr5_channel.v \
    $RTL/lpddr5/lpddr5_dut1.v \
    $PROJ/ip/ila/ila_0/sim/ila_0.v \
    $TB/tb_uart_full_test_cmd.v \
    $VIVADO_ROOT/data/verilog/src/glbl.v

vsim -wlfdeleteonquit -voptargs=+acc -L unisims_ver -L unisim -L xpm -L secureip work.tb_uart_full_test_cmd work.glbl
lp5_install_quit_cleanup
onfinish stop
do $SSIM/wave/wave_uart_full_test.do
run -all
quit -f
