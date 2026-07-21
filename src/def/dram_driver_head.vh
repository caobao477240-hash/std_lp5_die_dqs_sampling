`ifndef DRAM_DRIVER_HEAD_VH
`define DRAM_DRIVER_HEAD_VH

`unconnected_drive pull0

// FPGA build information
`define FPGA_VERSION                  64'h20260710_A09A5002
`define FPGA_CS                       8'd1
`define DUT1_ALG_NUM                  6

// BAR page addresses
`define bar_PAGE_SYSTEM               8'h00
`define bar_PAGE_PERIPHERAL           8'h03
`define bar_PAGE_TEST_CTRL            8'h04
`define bar_PAGE_GF                   8'h05
`define bar_PAGE_DUT_CFG              8'h06
`define bar_PAGE_OS                   8'h07

// BAR00: system information
`define bar00_SYSTEM_INFO             8'h00

// BAR03: peripheral control
`define bar03_IRSP_U68_CTRL           8'h00
`define bar03_IIC_DEVICE_ADDR         8'h02
`define bar03_IRSP_U68_DATA           8'h04
`define bar03_AD5272_CTRL             8'h08
`define bar03_AD5272_DATA             8'h0c
`define bar03_EEPROM_CTRL             8'h10
`define bar03_EEPROM_DATA             8'h14
`define bar03_RELAY_CTRL              8'h18
`define bar03_RESET_CTRL              8'h1c
`define bar03_IRSP_U67_CTRL           8'h20

// BAR04: initialization and IDD6 control
`define bar04_INIT_CTRL               8'h04
`define bar04_INIT_RESULT             8'h08
`define bar04_IDD6_CTRL               8'h0c
`define bar04_IDD6_RESULT             8'h10

// BAR05: gross-function test
`define bar05_GF_CTRL                 8'h00
`define bar05_GF_RESULT               8'h04
`define bar05_GF_AUX_RESULT           8'h08
`define bar05_CLK_SEL                 8'h10
`define bar05_ALG_ADDR_START          8'h12
`define bar05_ALG_ADDR_END            8'h13

// BAR06: DUT timing and calibration
`define bar06_MRW                     8'h08
`define bar06_DQ_DELAY_L              8'h18
`define bar06_RDC_STATUS              8'h20
`define bar06_DQ_DELAY_H              8'h24
`define bar06_RDC_TRAIN_CTRL          8'h28
`define bar06_RDC_TRAIN_STATUS        8'h2c
`define bar06_RDC_TRAIN_BEST_L        8'h30
`define bar06_RDC_TRAIN_BEST_H        8'h34
`define bar06_RDC_TRAIN_LEFT_L        8'h38
`define bar06_RDC_TRAIN_LEFT_H        8'h3c
`define bar06_RDC_TRAIN_RIGHT_L       8'h40
`define bar06_RDC_TRAIN_RIGHT_H       8'h44
`define bar06_CAPTURE_CFG             8'h48
`define bar06_GF_STREAM_CFG           8'h4c
`define bar06_GF_PATTERN_CFG          8'h50
`define bar06_RDC_TRAIN_SCAN          8'h54

// BAR07: OS test
`define bar07_OS_CTRL                 8'h00
`define bar07_VDD_THRESHOLD           8'h04
`define bar07_ADC_THRESHOLD           8'h08
`define bar07_OS_RESULT               8'h0c

`endif
