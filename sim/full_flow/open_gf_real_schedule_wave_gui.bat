@echo off
set VSIM=E:\modelism\win64\vsim.exe
set DO_FILE=E:\project\std_lp5_die_clk800M\sim\full_flow\open_gf_real_schedule_wave_gui.do

"%VSIM%" -do "%DO_FILE%"
