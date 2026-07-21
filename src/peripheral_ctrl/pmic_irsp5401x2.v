/**
 * pmic_irsp5401x2
 * Dual IRSP5401 PMIC I2C controller.
 * Splits 64-bit command values into individual write/read enables,
 * register addresses, and write data for two independent I2C config
 * channels (U67 and U68).
 */
module pmic_irsp5401x2 (
    input  wire                 clk                       ,
    input  wire                 rst_n                     ,
    input  wire                 IRSP_U67_send_byte_ctrl   ,
    input  wire                 IRSP_U67_data_bit_ctrl    ,  // 0 = 8-bit, 1 = 16-bit
    input  wire                 IRSP_U68_send_byte_ctrl   ,
    input  wire                 IRSP_U68_data_bit_ctrl    ,  // 0 = 8-bit, 1 = 16-bit
    input  wire  [ 6:0]         IRSP_IIC_DEVICE_ADDR      ,
    input  wire  [63:0]         IRSP_U67_value            ,  // {rd_en[55:48], rd_addr[47:32], wr_en[31:24], wr_addr[23:8], wr_data[7:0]}
    input  wire  [63:0]         IRSP_U68_value            ,  // same fields as U67

    output wire                 IRSP_U67_scl_o            ,
    inout  wire                 IRSP_U67_sda_io           ,
    output wire  [15:0]         IRSP_U67_data_out_o       ,
    output wire                 IRSP_U67_data_out_valid   ,

    output wire                 IRSP_U68_scl_o            ,
    inout  wire                 IRSP_U68_sda_io           ,
    output wire  [15:0]         IRSP_U68_data_out_o       ,
    output wire                 IRSP_U68_data_out_valid
);

    // --------------------------------------------------------
    // U67 command field extraction
    // --------------------------------------------------------
    wire               IRSP_U67_wr_en_i       ;
    wire               IRSP_U67_rd_en_i       ;
    wire [15:0]        IRSP_U67_wr_reg_addr_i ;
    wire [15:0]        IRSP_U67_rd_reg_addr_i ;
    wire [15:0]        IRSP_U67_data_in_i     ;

    assign IRSP_U67_wr_en_i       = IRSP_U67_value[32];
    assign IRSP_U67_rd_en_i       = IRSP_U67_value[56];
    assign IRSP_U67_wr_reg_addr_i = IRSP_U67_value[31:16];
    assign IRSP_U67_rd_reg_addr_i = IRSP_U67_value[55:40];
    assign IRSP_U67_data_in_i     = IRSP_U67_value[15:0];

    // --------------------------------------------------------
    // U68 command field extraction
    // --------------------------------------------------------
    wire               IRSP_U68_wr_en_i       ;
    wire               IRSP_U68_rd_en_i       ;
    wire [15:0]        IRSP_U68_wr_reg_addr_i ;
    wire [15:0]        IRSP_U68_rd_reg_addr_i ;
    wire [15:0]        IRSP_U68_data_in_i     ;

    assign IRSP_U68_wr_en_i       = IRSP_U68_value[32];
    assign IRSP_U68_rd_en_i       = IRSP_U68_value[56];
    assign IRSP_U68_wr_reg_addr_i = IRSP_U68_value[31:16];
    assign IRSP_U68_rd_reg_addr_i = IRSP_U68_value[55:40];
    assign IRSP_U68_data_in_i     = IRSP_U68_value[15:0];

    // --------------------------------------------------------
    // I2C config instance for U67
    // --------------------------------------------------------
    i2c_cfg u67_IRSP5401 (
        .clk              (clk                       ),
        .rst_n            (rst_n                     ),
        .send_byte_ctrl   (IRSP_U67_send_byte_ctrl   ),
        .data_bit_ctrl    (IRSP_U67_data_bit_ctrl    ),
        .IRSP_IIC_DEVICE_ADDR (IRSP_IIC_DEVICE_ADDR  ),
        .scl_o            (IRSP_U67_scl_o            ),
        .sda_io           (IRSP_U67_sda_io           ),
        .wr_en_i          (IRSP_U67_wr_en_i          ),
        .rd_en_i          (IRSP_U67_rd_en_i          ),
        .wr_reg_addr_i    (IRSP_U67_wr_reg_addr_i    ),
        .rd_reg_addr_i    (IRSP_U67_rd_reg_addr_i    ),
        .data_in_i        (IRSP_U67_data_in_i        ),
        .data_out_o       (IRSP_U67_data_out_o       ),
        .data_out_valid   (IRSP_U67_data_out_valid   )
    );

    // --------------------------------------------------------
    // I2C config instance for U68
    // --------------------------------------------------------
    i2c_cfg u68_IRSP5401 (
        .clk              (clk                       ),
        .rst_n            (rst_n                     ),
        .send_byte_ctrl   (IRSP_U68_send_byte_ctrl   ),
        .data_bit_ctrl    (IRSP_U68_data_bit_ctrl    ),
        .IRSP_IIC_DEVICE_ADDR (IRSP_IIC_DEVICE_ADDR  ),
        .scl_o            (IRSP_U68_scl_o            ),
        .sda_io           (IRSP_U68_sda_io           ),
        .wr_en_i          (IRSP_U68_wr_en_i          ),
        .rd_en_i          (IRSP_U68_rd_en_i          ),
        .wr_reg_addr_i    (IRSP_U68_wr_reg_addr_i    ),
        .rd_reg_addr_i    (IRSP_U68_rd_reg_addr_i    ),
        .data_in_i        (IRSP_U68_data_in_i        ),
        .data_out_o       (IRSP_U68_data_out_o       ),
        .data_out_valid   (IRSP_U68_data_out_valid   )
    );

endmodule
