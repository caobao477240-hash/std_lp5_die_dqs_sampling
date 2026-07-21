/**
 * uart_tx
 * UART transmitter with configurable parity, MSB/LSB ordering,
 * 16x oversampling, and automatic FIFO flow control.
 */
module uart_tx
#(
    parameter MSB = 0            // 1 = MSB first, 0 = LSB first
)
(
    input  logic       uart_clk_i      ,  // System clock (200 MHz)
    input  logic       tx_rstn_i       ,  // Active-low reset
    input  logic       baud_x16_en_i   ,  // Baud rate x16 enable pulse
    input  logic       parity_en_i     ,  // Parity enable
    input  logic       parity_type_i   ,  // 1 = odd parity, 0 = even parity
    input  logic       fifo_empty_i    ,  // TX FIFO empty flag
    input  logic [7:0] fifo_dout_i     ,  // TX FIFO data output
    output logic       fifo_rd_en_o    ,  // FIFO read enable
    output logic       uart_tx_o          // Serial output
);

    // --------------------------------------------------------
    // Local parameters
    // --------------------------------------------------------
    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    // --------------------------------------------------------
    // Internal signals
    // --------------------------------------------------------
    logic [1:0] state               ;  // Current state
    logic [3:0] over_sample_cnt     ;  // Oversampling counter (0..15)
    logic [3:0] bit_cnt             ;  // Bit counter (0..7/8)
    logic       char_fifo_pop       ;  // Pop next character from FIFO
    logic       crc_bit             ;  // Parity bit value
    logic       over_sample_cnt_done;  // Oversampling done flag
    logic       bit_cnt_done        ;  // All data bits sent flag

    // --------------------------------------------------------
    // Derived control signals
    // --------------------------------------------------------
    assign over_sample_cnt_done = (over_sample_cnt == '0);
    assign bit_cnt_done = parity_en_i ? (bit_cnt == 4'd8) : (bit_cnt == 4'd7);
    assign fifo_rd_en_o = char_fifo_pop && baud_x16_en_i;

    // --------------------------------------------------------
    // State machine
    // --------------------------------------------------------
    always_ff @(posedge uart_clk_i or negedge tx_rstn_i) begin
        if (!tx_rstn_i) begin
            state         <= IDLE;
            char_fifo_pop <= 1'b0;
        end
        else if (baud_x16_en_i) begin
            char_fifo_pop <= 1'b0;
            case (state)
                IDLE: begin
                    if (!fifo_empty_i) begin
                        state <= START;
                    end
                end
                START: begin
                    if (over_sample_cnt_done) begin
                        state <= DATA;
                    end
                end
                DATA: begin
                    if (over_sample_cnt_done && bit_cnt_done) begin
                        char_fifo_pop <= 1'b1;
                        state         <= STOP;
                    end
                end
                STOP: begin
                    if (over_sample_cnt_done) begin
                        if (fifo_empty_i) begin
                            state <= IDLE;
                        end
                        else begin
                            state <= START;
                        end
                    end
                end
            endcase
        end
    end

    // --------------------------------------------------------
    // Oversampling counter
    // --------------------------------------------------------
    always_ff @(posedge uart_clk_i or negedge tx_rstn_i) begin
        if (!tx_rstn_i) begin
            over_sample_cnt <= '0;
        end
        else if (baud_x16_en_i) begin
            if (!over_sample_cnt_done) begin
                over_sample_cnt <= over_sample_cnt - 1'b1;
            end
            else if (((state == IDLE) && !fifo_empty_i) ||
                     (state == START) ||
                     (state == DATA)  ||
                     ((state == STOP) && !fifo_empty_i)) begin
                over_sample_cnt <= 4'd15;
            end
        end
    end

    // --------------------------------------------------------
    // Bit counter
    // --------------------------------------------------------
    always_ff @(posedge uart_clk_i or negedge tx_rstn_i) begin
        if (!tx_rstn_i) begin
            bit_cnt <= '0;
        end
        else if (baud_x16_en_i) begin
            if (over_sample_cnt_done) begin
                if (state == START) begin
                    bit_cnt <= '0;
                end
                else if (state == DATA) begin
                    bit_cnt <= bit_cnt + 1'b1;
                end
            end
        end
    end

    // --------------------------------------------------------
    // Serial output generation
    // --------------------------------------------------------
    always_ff @(posedge uart_clk_i or negedge tx_rstn_i) begin
        if (!tx_rstn_i) begin
            uart_tx_o <= 1'b1;
        end
        else if (baud_x16_en_i) begin
            if ((state == STOP) || (state == IDLE)) begin
                uart_tx_o <= 1'b1;                      // Idle / stop: high
            end
            else if (state == START) begin
                uart_tx_o <= 1'b0;                      // Start bit: low
            end
            else if (bit_cnt == 4'd8) begin
                uart_tx_o <= crc_bit;                    // Parity bit
            end
            else begin
                if (MSB) begin
                    uart_tx_o <= fifo_dout_i[7 - bit_cnt];
                end
                else begin
                    uart_tx_o <= fifo_dout_i[bit_cnt];
                end
            end
        end
    end

    // --------------------------------------------------------
    // Parity generation (calculated during the last data bit)
    // --------------------------------------------------------
    always_ff @(posedge uart_clk_i or negedge tx_rstn_i) begin
        if (!tx_rstn_i) begin
            crc_bit <= 1'b0;
        end
        else if (baud_x16_en_i && over_sample_cnt_done && (bit_cnt == 4'd7)) begin
            if (parity_type_i) begin
                crc_bit <= ~^fifo_dout_i;               // Odd parity
            end
            else begin
                crc_bit <= ^fifo_dout_i;                // Even parity
            end
        end
    end

endmodule