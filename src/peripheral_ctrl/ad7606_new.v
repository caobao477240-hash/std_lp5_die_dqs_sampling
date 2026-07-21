`timescale 1ns / 1ps

/**
 * ad7606_new
 * AD7606 8-channel simultaneous-sampling ADC driver (Verilog-2001).
 * Supports parallel interface, automatic conversion timing,
 * and moving-average filtering for IDD current measurement.
 */
module ad7606_new (
    input            sys_clk         ,  // System clock (200 MHz)
    input            ad_busy         ,  // ADC busy flag
    input            ad_dataA        ,  // Parallel data line A (ch1/2/3/4)
    input            ad_dataB        ,  // Parallel data line B (ch5/6/7/8)
    output wire [2:0]ad_os           ,  // Oversampling mode (fixed to 0)
    output reg       ad_rst          ,  // ADC reset (active high)
    output reg       ad_cvAB         ,  // Conversion start A/B (shared)
    output reg       ad_wr           ,  // Write/read control
    output reg       ad_cs_n         ,  // Chip select (active low)
    output reg       ad_sclk         ,  // Serial clock (parallel mode tied high)
    output reg [15:0] x_ch1          ,  // Averaged IDD readout ch1
    output reg [15:0] x_ch2          ,
    output reg [15:0] x_ch3          ,
    output reg [15:0] x_ch4          ,
    output reg [15:0] x_ch5          ,
    output reg [15:0] x_ch6          ,
    output reg [15:0] x_ch7          ,
    output reg [15:0] x_ch8          ,
    output reg        ad_done        ,  // ADC conversion complete strobe
    output reg [15:0] ad_ch1         ,  // Raw ADC value (last conversion)
    output reg [15:0] ad_ch2         ,
    output reg [15:0] ad_ch3         ,
    output reg [15:0] ad_ch4         ,
    output reg [15:0] ad_ch5         ,
    output reg [15:0] ad_ch6         ,
    output reg [15:0] ad_ch7         ,
    output reg [15:0] ad_ch8
);

    // --------------------------------------------------------
    // Parameters
    // --------------------------------------------------------
    parameter AVG_TIMES      = 512;           // Number of samples for moving average (must be 2^n)
    parameter INNER_CNT_END  = 9'd2;          // Internal reset delay

    // State machine one-hot encoding (16-bit)
    localparam AD_IDLE   = 16'b0000_0000_0000_0001;
    localparam AD_CVAB   = 16'b0000_0000_0000_0010;
    localparam AD_BUSY1  = 16'b0000_0000_0000_0100;
    localparam AD_BUSY2  = 16'b0000_0000_0000_1000;
    localparam AD_CSN    = 16'b0000_0000_0001_0000;
    localparam AD_CH1_5  = 16'b0000_0000_0010_0000;
    localparam AD_CH2_6  = 16'b0000_0000_0100_0000;
    localparam AD_CH3_7  = 16'b0000_0000_1000_0000;
    localparam AD_CH4_8  = 16'b0000_0001_0000_0000;
    localparam AD_STOP   = 16'b0000_0010_0000_0000;
    localparam AD_STOP_2 = 16'b0000_0100_0000_0000;

    // --------------------------------------------------------
    // Internal wires and regs
    // --------------------------------------------------------
    reg         rst_n;
    reg [ 8:0]  rst_inner_cnt;

    reg [15:0]  state;
    reg [15:0]  state_cnt;
    reg [15:0]  init_cnt;
    reg [ 1:0]  cnt_spi_clk;
    reg         cnt_spi_clk_en;
    reg         spi_start;

    reg [15:0]  ad_ch1_r;
    reg [15:0]  ad_ch2_r;
    reg [15:0]  ad_ch3_r;
    reg [15:0]  ad_ch4_r;
    reg [15:0]  ad_ch5_r;
    reg [15:0]  ad_ch6_r;
    reg [15:0]  ad_ch7_r;
    reg [15:0]  ad_ch8_r;

    reg [15:0]  cnt_avg;
    wire        add_avg_cnt;
    wire        end_avg_cnt;

    wire [15:0] x_ch1_all;
    wire [15:0] x_ch2_all;
    wire [15:0] x_ch3_all;
    wire [15:0] x_ch4_all;
    wire [15:0] x_ch5_all;
    wire [15:0] x_ch6_all;
    wire [15:0] x_ch7_all;
    wire [15:0] x_ch8_all;

    // --------------------------------------------------------
    // Static assignments
    // --------------------------------------------------------
    assign ad_os = 3'd0;    // No oversampling

    // --------------------------------------------------------
    // Internal reset generation (release after INNER_CNT_END)
    // --------------------------------------------------------
    always @(posedge sys_clk) begin
        if (rst_inner_cnt < INNER_CNT_END)
            rst_inner_cnt <= rst_inner_cnt + 1'd1;
        else if (rst_inner_cnt == INNER_CNT_END)
            rst_inner_cnt <= rst_inner_cnt;
        else
            rst_inner_cnt <= 0;
    end

    always @(posedge sys_clk) begin
        if (rst_inner_cnt == INNER_CNT_END)
            rst_n <= 1'b1;
        else
            rst_n <= 1'b0;
    end

    // --------------------------------------------------------
    // ADC reset and initialization
    // --------------------------------------------------------
    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            init_cnt <= 16'd0;
            ad_rst   <= 1'b1;
        end
        else if (init_cnt < 16'hFFFF) begin
            init_cnt <= init_cnt + 1'b1;
            ad_rst   <= 1'b1;
        end
        else begin
            ad_rst   <= 1'b0;
        end
    end

    // --------------------------------------------------------
    // SPI clock enable (only during active data phases)
    // --------------------------------------------------------
    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n)
            cnt_spi_clk_en <= 1'b0;
        else if (state == AD_STOP)
            cnt_spi_clk_en <= 1'b0;
        else if (spi_start == 1'b1)
            cnt_spi_clk_en <= 1'b1;
    end

    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n)
            cnt_spi_clk <= 2'd0;
        else if (cnt_spi_clk_en == 1'b1)
            cnt_spi_clk <= cnt_spi_clk + 1'b1;
        else if (cnt_spi_clk_en == 1'b0)
            cnt_spi_clk <= 2'd0;
    end

    // --------------------------------------------------------
    // SCLK generation (combinational, state-based)
    // --------------------------------------------------------
    always @(*) begin
        case (state)
            AD_IDLE, AD_CVAB, AD_BUSY1, AD_BUSY2, AD_STOP:
                ad_sclk = 1'b1;
            AD_CH1_5, AD_CH2_6, AD_CH3_7, AD_CH4_8: begin
                if (cnt_spi_clk == 2'd0 || cnt_spi_clk == 2'd1)
                    ad_sclk = 1'b0;
                else
                    ad_sclk = 1'b1;
            end
            default:
                ad_sclk = 1'b1;
        endcase
    end

    // --------------------------------------------------------
    // Main ADC state machine
    // --------------------------------------------------------
    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= AD_IDLE;
            ad_cvAB   <= 1'b1;
            ad_wr     <= 1'b1;
            ad_cs_n   <= 1'b1;
            spi_start <= 1'b0;
            state_cnt <= 16'd0;
            ad_ch1_r  <= 16'd0;
            ad_ch2_r  <= 16'd0;
            ad_ch3_r  <= 16'd0;
            ad_ch4_r  <= 16'd0;
            ad_ch5_r  <= 16'd0;
            ad_ch6_r  <= 16'd0;
            ad_ch7_r  <= 16'd0;
            ad_ch8_r  <= 16'd0;
            ad_done   <= 1'b0;
        end
        else
            case (state)
                AD_IDLE: begin
                    ad_cvAB <= 1'b1;
                    ad_wr   <= 1'b1;
                    ad_cs_n <= 1'b1;
                    ad_done <= 1'b0;
                    if (state_cnt == 16'd10) begin
                        state_cnt <= 16'd0;
                        state     <= AD_CVAB;
                    end
                    else
                        state_cnt <= state_cnt + 1'b1;
                end

                AD_CVAB: begin
                    if (state_cnt == 16'd2) begin
                        state_cnt <= 16'd0;
                        state     <= AD_BUSY1;
                        ad_cvAB   <= 1'b1;
                        ad_wr     <= 1'b1;
                    end
                    else begin
                        state_cnt <= state_cnt + 1'b1;
                        ad_cvAB   <= 1'b0;
                        ad_wr     <= 1'b0;
                    end
                end

                AD_BUSY1: begin
                    if (state_cnt == 16'd10) begin
                        state_cnt <= 16'd0;
                        state     <= AD_BUSY2;
                    end
                    else
                        state_cnt <= state_cnt + 1'b1;
                end

                AD_BUSY2: begin
                    if (ad_busy == 1'b0)
                        state <= AD_CSN;
                end

                AD_CSN: begin
                    ad_cs_n   <= 1'b0;
                    spi_start <= 1'b1;
                    state     <= AD_CH1_5;
                end

                AD_CH1_5: begin   // Read channels 1 & 5
                    if (cnt_spi_clk == 2'd1) begin
                        ad_ch1_r <= {ad_ch1_r[14:0], ad_dataA};
                        ad_ch5_r <= {ad_ch5_r[14:0], ad_dataB};
                        state_cnt <= state_cnt + 1'b1;
                        if (state_cnt == 16'd15) begin
                            state_cnt <= 16'd0;
                            state     <= AD_CH2_6;
                        end
                    end
                end

                AD_CH2_6: begin   // Read channels 2 & 6
                    if (cnt_spi_clk == 2'd1) begin
                        ad_ch2_r <= {ad_ch2_r[14:0], ad_dataA};
                        ad_ch6_r <= {ad_ch6_r[14:0], ad_dataB};
                        state_cnt <= state_cnt + 1'b1;
                        if (state_cnt == 16'd15) begin
                            state_cnt <= 16'd0;
                            state     <= AD_CH3_7;
                        end
                    end
                end

                AD_CH3_7: begin   // Read channels 3 & 7
                    if (cnt_spi_clk == 2'd1) begin
                        ad_ch3_r <= {ad_ch3_r[14:0], ad_dataA};
                        ad_ch7_r <= {ad_ch7_r[14:0], ad_dataB};
                        state_cnt <= state_cnt + 1'b1;
                        if (state_cnt == 16'd15) begin
                            state_cnt <= 16'd0;
                            state     <= AD_CH4_8;
                        end
                    end
                end

                AD_CH4_8: begin   // Read channels 4 & 8
                    if (cnt_spi_clk == 2'd1) begin
                        ad_ch4_r <= {ad_ch4_r[14:0], ad_dataA};
                        ad_ch8_r <= {ad_ch8_r[14:0], ad_dataB};
                        state_cnt <= state_cnt + 1'b1;
                        if (state_cnt == 16'd15) begin
                            state_cnt <= 16'd0;
                            state     <= AD_STOP_2;
                        end
                    end
                end

                AD_STOP_2: begin
                    ad_cs_n <= 1'b1;
                    // Convert from two's complement to unsigned if negative
                    if (ad_ch4_r[15]) ad_ch4_r <= ~ad_ch4_r;
                    if (ad_ch8_r[15]) ad_ch8_r <= ~ad_ch8_r;
                    if (ad_ch3_r[15]) ad_ch3_r <= ~ad_ch3_r;
                    if (ad_ch7_r[15]) ad_ch7_r <= ~ad_ch7_r;
                    if (ad_ch2_r[15]) ad_ch2_r <= ~ad_ch2_r;
                    if (ad_ch6_r[15]) ad_ch6_r <= ~ad_ch6_r;
                    if (ad_ch1_r[15]) ad_ch1_r <= ~ad_ch1_r;
                    if (ad_ch5_r[15]) ad_ch5_r <= ~ad_ch5_r;
                    state <= AD_STOP;
                end

                AD_STOP: begin
                    ad_done <= 1'b1;
                    state   <= AD_IDLE;
                end

                default: state <= AD_IDLE;
            endcase
    end

    // --------------------------------------------------------
    // Raw ADC output capture (register on ad_done)
    // --------------------------------------------------------
    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            ad_ch1 <= 16'd0;
            ad_ch2 <= 16'd0;
            ad_ch3 <= 16'd0;
            ad_ch4 <= 16'd0;
            ad_ch5 <= 16'd0;
            ad_ch6 <= 16'd0;
            ad_ch7 <= 16'd0;
            ad_ch8 <= 16'd0;
        end
        else if (ad_done) begin
            ad_ch1 <= ad_ch1_r;
            ad_ch2 <= ad_ch2_r;
            ad_ch3 <= ad_ch3_r;
            ad_ch4 <= ad_ch4_r;
            ad_ch5 <= ad_ch5_r;
            ad_ch6 <= ad_ch6_r;
            ad_ch7 <= ad_ch7_r;
            ad_ch8 <= ad_ch8_r;
        end
    end

    // --------------------------------------------------------
    // Averaging counter and averaged output latch
    // --------------------------------------------------------
    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n)
            cnt_avg <= 'd0;
        else if (add_avg_cnt) begin
            if (end_avg_cnt)
                cnt_avg <= 'd0;
            else
                cnt_avg <= cnt_avg + 1'b1;
        end
    end
    assign add_avg_cnt = ad_done;
    assign end_avg_cnt = add_avg_cnt && (cnt_avg >= AVG_TIMES - 1'b1);

    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            x_ch1 <= 16'd0;
            x_ch2 <= 16'd0;
            x_ch3 <= 16'd0;
            x_ch4 <= 16'd0;
            x_ch5 <= 16'd0;
            x_ch6 <= 16'd0;
            x_ch7 <= 16'd0;
            x_ch8 <= 16'd0;
        end
        else if (end_avg_cnt) begin
            x_ch1 <= x_ch1_all;
            x_ch2 <= x_ch2_all;
            x_ch3 <= x_ch3_all;
            x_ch4 <= x_ch4_all;
            x_ch5 <= x_ch5_all;
            x_ch6 <= x_ch6_all;
            x_ch7 <= x_ch7_all;
            x_ch8 <= x_ch8_all;
        end
        else begin
            // hold previous values
        end
    end

    // --------------------------------------------------------
    // Moving average filter instances (8 channels)
    // --------------------------------------------------------
    getMovingAvg
    #(
        .N         (AVG_TIMES),
        .DIN_WIDTH (16)
    )
    getMovingAvg_idd_ch1 (
        .moving_avg (x_ch1_all),
        .din        (ad_ch1_r),
        .din_valid  (ad_done),
        .clk        (sys_clk),
        .rstn       (rst_n)
    );

    getMovingAvg
    #(
        .N         (AVG_TIMES),
        .DIN_WIDTH (16)
    )
    getMovingAvg_idd_ch2 (
        .moving_avg (x_ch2_all),
        .din        (ad_ch2_r),
        .din_valid  (ad_done),
        .clk        (sys_clk),
        .rstn       (rst_n)
    );

    getMovingAvg
    #(
        .N         (AVG_TIMES),
        .DIN_WIDTH (16)
    )
    getMovingAvg_idd_ch3 (
        .moving_avg (x_ch3_all),
        .din        (ad_ch3_r),
        .din_valid  (ad_done),
        .clk        (sys_clk),
        .rstn       (rst_n)
    );

    getMovingAvg
    #(
        .N         (AVG_TIMES),
        .DIN_WIDTH (16)
    )
    getMovingAvg_idd_ch4 (
        .moving_avg (x_ch4_all),
        .din        (ad_ch4_r),
        .din_valid  (ad_done),
        .clk        (sys_clk),
        .rstn       (rst_n)
    );

    getMovingAvg
    #(
        .N         (AVG_TIMES),
        .DIN_WIDTH (16)
    )
    getMovingAvg_idd_ch5 (
        .moving_avg (x_ch5_all),
        .din        (ad_ch5_r),
        .din_valid  (ad_done),
        .clk        (sys_clk),
        .rstn       (rst_n)
    );

    getMovingAvg
    #(
        .N         (AVG_TIMES),
        .DIN_WIDTH (16)
    )
    getMovingAvg_idd_ch6 (
        .moving_avg (x_ch6_all),
        .din        (ad_ch6_r),
        .din_valid  (ad_done),
        .clk        (sys_clk),
        .rstn       (rst_n)
    );

    getMovingAvg
    #(
        .N         (AVG_TIMES),
        .DIN_WIDTH (16)
    )
    getMovingAvg_idd_ch7 (
        .moving_avg (x_ch7_all),
        .din        (ad_ch7_r),
        .din_valid  (ad_done),
        .clk        (sys_clk),
        .rstn       (rst_n)
    );

    getMovingAvg
    #(
        .N         (AVG_TIMES),
        .DIN_WIDTH (16)
    )
    getMovingAvg_idd_ch8 (
        .moving_avg (x_ch8_all),
        .din        (ad_ch8_r),
        .din_valid  (ad_done),
        .clk        (sys_clk),
        .rstn       (rst_n)
    );

    // --------------------------------------------------------
    // Integrated Logic Analyzer (ILA) debug instance (commented out)
    // --------------------------------------------------------
//ila_2 ila_2_adc (
//    .clk    (sys_clk),
//    .probe0 (ad_done),
//    .probe1 (ad_ch1),
//    .probe2 (ad_ch2),
//    .probe3 (ad_ch3),
//    .probe4 (ad_ch4),
//    .probe5 (ad_ch5),
//    .probe6 (ad_ch6),
//    .probe7 (ad_ch7),
//    .probe8 (ad_ch8)
//);

endmodule
