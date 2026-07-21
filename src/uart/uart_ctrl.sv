/**
 * uart_ctrl
 * UART controller with configurable baud rate, parity, loopback,
 * TX FIFO, and RX frame/CRC error detection.
 */
module uart_ctrl
#(
    parameter BPS_SEL        = 32'd600000 ,  // Baud rate select (9600/115200/600000)
    parameter FIFO_PROG_FULL = 17'd131008    // TX FIFO programmable full threshold
)
(
    input  logic                uart_clk_i          ,  // System clock (200MHz)
    input  logic                uart_rstn_i         ,  // Active-low reset
    input  logic                loopback_i          ,  // Loopback enable
    input  logic                parity_en_i         ,  // Parity enable
    input  logic                parity_type_i       ,  // 1 = odd, 0 = even

    // RX interface
    output logic                rx_wren_o           ,  // RX data write enable
    output logic [ 7:0]         rx_data_o           ,  // RX data byte
    input  logic                rx_fifo_full_i      ,  // RX FIFO full flag
    output logic                rx_frame_err_o      ,  // Frame error (stop bit)
    output logic                rx_crc_err_o        ,  // CRC/parity error

    // TX FIFO interface
    input  logic                tx_fifo_wren_i      ,  // TX data write enable
    input  logic [ 7:0]         tx_fifo_data_i      ,  // TX data byte
    output logic                tx_fifo_full_o      ,  // TX FIFO full
    output logic                tx_fifo_alfull_o    ,  // TX FIFO almost full
    output logic                tx_fifo_empty_o     ,  // TX FIFO empty
    output logic                tx_fifo_alempty_o   ,  // TX FIFO almost empty
    output logic                prog_full_o         ,  // TX FIFO programmable full

    // UART physical interface
    input  logic                uart_rx_i           ,  // UART RX input
    output logic                uart_tx_o              // UART TX output
);

    // --------------------------------------------------------
    // Internal signals
    // --------------------------------------------------------
    logic                baud_x16_en        ;  // Baud rate x16 enable pulse
    logic                rx_serin_ms        ;  // RX serial in (metastable)
    logic                rx_serin_sync      ;  // RX serial in (synchronized)
    logic                rx_serin_sel       ;  // RX source selection (loopback)
    logic                tx_serout_internal ;  // TX serial out (internal)

    logic                rx_data_rdy        ;  // RX data ready (from receiver)
    logic                rx_data_rdy_q1     ;  // RX data ready (delayed)
    logic                frm_err            ;  // Frame error (from receiver)
    logic                frm_err_q1         ;  // Frame error (delayed)

    logic [ 7:0]         tx_data            ;  // TX data from FIFO
    logic                tx_fifo_rd         ;  // TX FIFO read enable

    // --------------------------------------------------------
    // Frame error rising-edge detection
    // --------------------------------------------------------
    always_ff @(posedge uart_clk_i or negedge uart_rstn_i) begin
        if (!uart_rstn_i) begin
            rx_data_rdy_q1 <= 1'b0;
            frm_err_q1     <= 1'b0;
            rx_frame_err_o <= 1'b0;
        end
        else begin
            rx_data_rdy_q1 <= rx_data_rdy;
            frm_err_q1     <= frm_err;
            rx_frame_err_o <= ~frm_err_q1 & frm_err;
        end
    end

    // --------------------------------------------------------
    // RX write enable (valid data, no error, FIFO not full)
    // --------------------------------------------------------
    assign rx_wren_o = rx_data_rdy_q1 & ~rx_data_rdy & ~frm_err & ~rx_fifo_full_i;

    // --------------------------------------------------------
    // RX input synchronizer (2-stage)
    // --------------------------------------------------------
    always_ff @(posedge uart_clk_i or negedge uart_rstn_i) begin
        if (!uart_rstn_i) begin
            rx_serin_ms   <= 1'b0;
            rx_serin_sync <= 1'b0;
        end
        else begin
            rx_serin_ms   <= uart_rx_i;
            rx_serin_sync <= rx_serin_ms;
        end
    end

    // --------------------------------------------------------
    // Loopback and output selection
    // --------------------------------------------------------
    always_ff @(posedge uart_clk_i or negedge uart_rstn_i) begin
        if (!uart_rstn_i) begin
            rx_serin_sel <= 1'b0;
            uart_tx_o    <= 1'b0;
        end
        else begin
            rx_serin_sel <= loopback_i ? tx_serout_internal : rx_serin_sync;
            uart_tx_o    <= loopback_i ? rx_serin_sync      : tx_serout_internal;
        end
    end

    // --------------------------------------------------------
    // Baud rate generator instance
    // --------------------------------------------------------
    uart_bps_cfg
    #(
        .BPS_SEL        (BPS_SEL        )   // 9600, 115200, 600000
    )
    eft_uart_bps_cfg_u0 (
        .uart_clk_i     (uart_clk_i     ),  // 200 MHz
        .clk_bps_edg_o  (               ),  // unused
        .clk_bps_pdg_o  (baud_x16_en    ),  // baud rate x16 enable
        .clk_bps_ndg_o  (               )   // unused
    );

    // --------------------------------------------------------
    // UART receiver instance
    // --------------------------------------------------------
    uart_rx
    #(
        .MSB            (0              )   // LSB first
    )
    eft_uart_rx_u0 (
        .uart_clk_i     (uart_clk_i     ),  // 200 MHz
        .rx_rstn_i      (uart_rstn_i    ),
        .baud_x16_en_i  (baud_x16_en    ),
        .parity_en_i    (parity_en_i    ),
        .parity_type_i  (parity_type_i  ),  // 1 = odd, 0 = even
        .rx_data_o      (rx_data_o      ),
        .rx_data_rdy_o  (rx_data_rdy    ),
        .frame_err_o    (frm_err        ),
        .crc_err_o      (rx_crc_err_o   ),
        .uart_rx_i      (rx_serin_sel   )
    );

    // --------------------------------------------------------
    // UART transmitter instance
    // --------------------------------------------------------
    uart_tx
    #(
        .MSB            (0              )   // LSB first
    )
    eft_uart_tx_u0 (
        .uart_clk_i     (uart_clk_i         ),
        .tx_rstn_i      (uart_rstn_i        ),
        .baud_x16_en_i  (baud_x16_en        ),
        .parity_en_i    (parity_en_i        ),
        .parity_type_i  (parity_type_i      ),  // 1 = odd, 0 = even
        .fifo_empty_i   (tx_fifo_empty_o    ),
        .fifo_dout_i    (tx_data            ),
        .fifo_rd_en_o   (tx_fifo_rd         ),
        .uart_tx_o      (tx_serout_internal )
    );

    // --------------------------------------------------------
    // TX FIFO instance (generated by FIFO generator)
    // --------------------------------------------------------
    fifo_generator_uart fifo_generator_uart_tx (
        .rst                (!uart_rstn_i       ),
        .wr_clk             (uart_clk_i         ),
        .rd_clk             (uart_clk_i         ),
        .din                (tx_fifo_data_i     ),
        .wr_en              (tx_fifo_wren_i     ),
        .rd_en              (tx_fifo_rd         ),
        .dout               (tx_data            ),
        .full               (tx_fifo_full_o     ),
        .almost_full        (tx_fifo_alfull_o   ),
        .empty              (tx_fifo_empty_o    ),
        .almost_empty       (tx_fifo_alempty_o  ),
        .wr_rst_busy        (                   ),  // unused
        .rd_rst_busy        (                   ),  // unused
        .prog_full_thresh   (FIFO_PROG_FULL     ),
        .prog_full          (prog_full_o        )
    );

endmodule