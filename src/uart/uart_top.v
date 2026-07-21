// UART physical layer and command protocol wrapper.
//
// This module keeps the existing uart_ctrl and protocol_ctrl behavior intact
// while presenting a single SIR bus interface to the register bank.

module uart_top
#(
    parameter BPS_SEL        = 32'd115200,
    parameter FIFO_PROG_FULL = 17'd131008
)
(
    input  wire          clk      ,
    input  wire          rst_n    ,

    input  wire          uart_rx  ,
    output wire          uart_tx  ,

    output wire          sir_sel  ,
    output wire [ 15:0]  sir_addr ,
    output wire          sir_read ,
    output wire [ 95:0]  sir_wdat ,
    input  wire [ 95:0]  sir_rdat ,
    input  wire          sir_dack
);

    wire         rx_wren     ;
    wire [ 7:0]  rx_data     ;
    wire         txfifo_wren ;
    wire [ 7:0]  txfifo_data ;

    uart_ctrl
    #(
        .BPS_SEL        (BPS_SEL        ),
        .FIFO_PROG_FULL (FIFO_PROG_FULL )
    )
    uart_ctrl_u0 (
        .uart_clk_i        (clk          ),
        .uart_rstn_i       (rst_n        ),
        .loopback_i        (1'b0         ),
        .parity_en_i       (1'b0         ),
        .parity_type_i     (1'b0         ),
        .rx_wren_o         (rx_wren      ),
        .rx_data_o         (rx_data      ),
        .rx_fifo_full_i    (1'b0         ),
        .rx_frame_err_o    (             ),
        .rx_crc_err_o      (             ),
        .tx_fifo_wren_i    (txfifo_wren  ),
        .tx_fifo_data_i    (txfifo_data  ),
        .tx_fifo_full_o    (             ),
        .tx_fifo_alfull_o  (             ),
        .tx_fifo_empty_o   (             ),
        .tx_fifo_alempty_o (             ),
        .prog_full_o       (             ),
        .uart_rx_i         (uart_rx      ),
        .uart_tx_o         (uart_tx      )
    );

    protocol_ctrl protocol_ctrl_u0 (
        .sys_clk_i     (clk          ),
        .sys_rstn_i    (rst_n        ),
        .rx_data_i     (rx_data      ),
        .rx_wren_i     (rx_wren      ),
        .txfifo_wren_o (txfifo_wren  ),
        .txfifo_data_o (txfifo_data  ),
        .rsu_bus_wenb  (             ),
        .rsu_bus_wdat  (             ),
        .sir_sel       (sir_sel      ),
        .sir_addr      (sir_addr     ),
        .sir_read      (sir_read     ),
        .sir_wdat      (sir_wdat     ),
        .sir_rdat      (sir_rdat     ),
        .sir_dack      (sir_dack     )
    );

endmodule
