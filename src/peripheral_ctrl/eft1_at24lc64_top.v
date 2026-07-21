/**
 * eft1_at24lc64_top
 * EEPROM (AT24LC64) I2C interface wrapper.
 * Splits a 64-bit command value into write/read enables, register
 * addresses, and write data for the I2C config driver.
 */
module eft1_at24lc64_top (
    input  wire                 clk                       ,
    input  wire                 rst_n                     ,
    input  wire                 EEPROM_send_byte_ctrl     ,
    input  wire                 EEPROM_data_bit_ctrl      ,  // 0 = 8-bit, 1 = 16-bit
    input  wire  [63:0]         EEPROM_value              ,  // {rd_en[55:48], rd_addr[47:32], wr_en[31:24], wr_addr[23:8], wr_data[7:0]}

    output wire                 EEPROM_scl_o              ,
    inout  wire                 EEPROM_sda_io             ,
    output wire  [15:0]         EEPROM_data_out_o         ,
    output wire                 EEPROM_data_out_valid
);

    // --------------------------------------------------------
    // Internal command field extraction
    // --------------------------------------------------------
    wire               EEPROM_wr_en_i        ;
    wire               EEPROM_rd_en_i        ;
    wire [15:0]        EEPROM_wr_reg_addr_i  ;
    wire [15:0]        EEPROM_rd_reg_addr_i  ;
    wire [15:0]        EEPROM_data_in_i      ;
    wire [ 6:0]        IRSP_IIC_DEVICE_ADDR  ;

    // EEPROM fixed 7-bit I2C slave address
    assign IRSP_IIC_DEVICE_ADDR = 7'h50;

    // Field extraction from the 64-bit command word
    assign EEPROM_wr_en_i       = EEPROM_value[32];
    assign EEPROM_rd_en_i       = EEPROM_value[56];
    assign EEPROM_wr_reg_addr_i = EEPROM_value[31:16];
    assign EEPROM_rd_reg_addr_i = EEPROM_value[55:40];
    assign EEPROM_data_in_i     = EEPROM_value[15:0];

    // --------------------------------------------------------
    // I2C configuration driver instance
    // --------------------------------------------------------
    i2c_cfg
    #(
        .IIC_BIT_CTRL (1'b1)
    )
    u_at24lc64 (
        .clk              (clk                       ),
        .rst_n            (rst_n                     ),
        .send_byte_ctrl   (EEPROM_send_byte_ctrl     ),
        .data_bit_ctrl    (EEPROM_data_bit_ctrl      ),
        .IRSP_IIC_DEVICE_ADDR (IRSP_IIC_DEVICE_ADDR  ),
        .scl_o            (EEPROM_scl_o              ),
        .sda_io           (EEPROM_sda_io             ),
        .wr_en_i          (EEPROM_wr_en_i            ),
        .rd_en_i          (EEPROM_rd_en_i            ),
        .wr_reg_addr_i    (EEPROM_wr_reg_addr_i      ),
        .rd_reg_addr_i    (EEPROM_rd_reg_addr_i      ),
        .data_in_i        (EEPROM_data_in_i          ),
        .data_out_o       (EEPROM_data_out_o         ),
        .data_out_valid   (EEPROM_data_out_valid     )
    );

endmodule
