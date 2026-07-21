@echo off
cd /d E:\project\std_lp5_die\sim\ssim
start "" /wait "E:\modelism\win64\vsim.exe" -do E:\project\std_lp5_die\sim\ssim\run_uart_full_test.do

for /l %%i in (1,1,10) do (
    ping -n 2 127.0.0.1 >nul
    if exist work rmdir /s /q work 2>nul
    if exist modelsim.ini del /f /q modelsim.ini 2>nul
    if exist transcript del /f /q transcript 2>nul
    if exist vsim.wlf del /f /q vsim.wlf 2>nul
    if exist vsim_stacktrace.vstf del /f /q vsim_stacktrace.vstf 2>nul
)
