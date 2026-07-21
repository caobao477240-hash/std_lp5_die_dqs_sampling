/**
 * uart_rx
 * UART receiver with configurable parity, MSB/LSB ordering,
 * 16x oversampling, and frame error detection.
 */
module uart_rx
#(
    parameter MSB = 0            // 1 = MSB first, 0 = LSB first
)
(
    input  logic       uart_clk_i      ,  // 200 MHz system clock
    input  logic       rx_rstn_i       ,  // Active-low reset
    input  logic       baud_x16_en_i   ,  // Baud rate x16 enable pulse
    input  logic       parity_en_i     ,  // Parity enable
    input  logic       parity_type_i   ,  // 1 = odd parity, 0 = even parity
    output logic [7:0] rx_data_o       ,  // Received data byte
    output logic       rx_data_rdy_o   ,  // Received data ready flag
    output logic       frame_err_o     ,  // Frame error (invalid stop bit)
    output logic       crc_err_o       ,  // Parity error flag
    input  logic       uart_rx_i          // Serial input
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
    logic       crc_bit             ;  // Running parity accumulator
    logic [8:0] rx_data_d           ;  // Shift register (8 data + parity)
    logic       over_sample_cnt_done;  // Oversampling done flag
    logic       bit_cnt_done        ;  // All data bits sampled flag

    // --------------------------------------------------------
    // Derived control signals
    // --------------------------------------------------------
    assign over_sample_cnt_done = (over_sample_cnt == '0);
    assign bit_cnt_done = parity_en_i ? (bit_cnt == 4'd8) : (bit_cnt == 4'd7);

    // --------------------------------------------------------
    // State machine
    // --------------------------------------------------------
    always_ff @(posedge uart_clk_i or negedge rx_rstn_i) begin
        if (!rx_rstn_i) begin
            state <= IDLE;
        end
        else if (baud_x16_en_i) begin
            case (state)
                IDLE: begin
                    if (!uart_rx_i) begin
                        state <= START;
                    end
                end
                START: begin
                    if (over_sample_cnt_done) begin
                        if (!uart_rx_i) begin
                            state <= DATA;
                        end
                        else begin
                            state <= IDLE;  // False start
                        end
                    end
                end
                DATA: begin
                    if (over_sample_cnt_done && bit_cnt_done) begin
                        state <= STOP;
                    end
                end
                STOP: begin
                    if (over_sample_cnt_done) begin
                        state <= IDLE;
                    end
                end
            endcase
        end
    end

    // --------------------------------------------------------
    // Oversampling counter (16x per bit)
    // --------------------------------------------------------
    always_ff @(posedge uart_clk_i or negedge rx_rstn_i) begin
        if (!rx_rstn_i) begin
            over_sample_cnt <= '0;
        end
        else if (baud_x16_en_i) begin
            if (!over_sample_cnt_done) begin
                over_sample_cnt <= over_sample_cnt - 1'b1;
            end
            else if ((state == IDLE) && (!uart_rx_i)) begin
                over_sample_cnt <= 4'd7;        // half-bit delay for center sampling
            end
            else if (((state == START) && (!uart_rx_i)) || (state == DATA)) begin
                over_sample_cnt <= 4'd15;
            end
        end
    end

    // --------------------------------------------------------
    // Bit counter
    // --------------------------------------------------------
    always_ff @(posedge uart_clk_i or negedge rx_rstn_i) begin
        if (!rx_rstn_i) begin
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
    // Shift register and data ready
    // --------------------------------------------------------
    always_ff @(posedge uart_clk_i or negedge rx_rstn_i) begin
        if (!rx_rstn_i) begin
            rx_data_d     <= '0;
            rx_data_rdy_o <= '0;
        end
        else if (baud_x16_en_i && over_sample_cnt_done) begin
            if (state == DATA) begin
                rx_data_d[bit_cnt] <= uart_rx_i;
                rx_data_rdy_o <= parity_en_i ? (bit_cnt == 4'd8) : (bit_cnt == 4'd7);
            end
            else begin
                rx_data_rdy_o <= '0;
            end
        end
    end

    // --------------------------------------------------------
    // Output data alignment (MSB/LSB)
    // --------------------------------------------------------
    always_ff @(posedge uart_clk_i or negedge rx_rstn_i) begin
        if (!rx_rstn_i) begin
            rx_data_o <= '0;
        end
        else if (state == STOP) begin
            if (MSB) begin
                // Reverse bit order for MSB first
                rx_data_o <= {rx_data_d[0], rx_data_d[1], rx_data_d[2], rx_data_d[3],
                              rx_data_d[4], rx_data_d[5], rx_data_d[6], rx_data_d[7]};
            end
            else begin
                rx_data_o <= rx_data_d[7:0];
            end
        end
    end

    // --------------------------------------------------------
    // Parity accumulation
    // --------------------------------------------------------
    always_ff @(posedge uart_clk_i or negedge rx_rstn_i) begin
        if (parity_en_i) begin
            if (!rx_rstn_i) begin
                if (parity_type_i)
                    crc_bit <= 1'b1;     // odd parity init
                else
                    crc_bit <= 1'b0;     // even parity init
            end
            else if (baud_x16_en_i && over_sample_cnt_done) begin
                if (state == START) begin
                    if (parity_type_i)
                        crc_bit <= 1'b1;
                    else
                        crc_bit <= 1'b0;
                end
                else if ((state == DATA) && (bit_cnt > 4'd0)) begin
                    crc_bit <= rx_data_d[bit_cnt-1] + crc_bit;
                end
            end
        end
        else begin
            crc_bit <= 1'b0;
        end
    end

    // --------------------------------------------------------
    // Parity error detection
    // --------------------------------------------------------
    always_ff @(posedge uart_clk_i or negedge rx_rstn_i) begin
        if (parity_en_i) begin
            if (!rx_rstn_i)
                crc_err_o <= 1'b0;
            else if (baud_x16_en_i) begin
                if (over_sample_cnt_done && (state == STOP) && (crc_bit != rx_data_d[8]))
                    crc_err_o <= 1'b1;
                else
                    crc_err_o <= 1'b0;
            end
        end
        else begin
            crc_err_o <= 1'b0;
        end
    end

    // --------------------------------------------------------
    // Frame error detection (stop bit check)
    // --------------------------------------------------------
    always_ff @(posedge uart_clk_i or negedge rx_rstn_i) begin
        if (!rx_rstn_i) begin
            frame_err_o <= 1'b0;
        end
        else if (baud_x16_en_i) begin
            if ((state == STOP) && over_sample_cnt_done && !uart_rx_i) begin
                frame_err_o <= 1'b1;
            end
            else begin
                frame_err_o <= 1'b0;
            end
        end
    end

endmodule