`timescale 1ns / 1ps

// =========================================================================
//  ADC Clock-Domain-Crossing Synchronizer
// =========================================================================
// Safely transfers AD7606 outputs from the 40 MHz ADC domain to clk_dst.
//
// Strategy:
//   1. ad_done is passed through a 2-FF synchronizer into clk_dst.
//   2. Falling-edge detection on the synchronized ad_done triggers a one-shot
//      latch of all data channels. In ad7606_new, ad_ch1~8 are updated on the
//      source-clock edge that drops ad_done, so this is the aligned data-valid
//      event for the destination clock domain.
//   3. x_ch1~4 (IDD averaged results) are also latched on the same event.
//
// Both clocks originate from the same PLL (integer 5:1 ratio), so the
// 2-FF synchronizer provides ample metastability protection.
// =========================================================================
module adc_cdc_sync (
    // Destination clock domain (clk_uart, 200 MHz)
    input  wire             clk_dst         ,
    input  wire             rst_n           ,

    // AD7606 raw outputs (clk_prph2 / 40 MHz domain)
    input  wire             ad_done_i       ,
    input  wire [15:0]      ad_ch1_i        ,
    input  wire [15:0]      ad_ch2_i        ,
    input  wire [15:0]      ad_ch3_i        ,
    input  wire [15:0]      ad_ch4_i        ,
    input  wire [15:0]      ad_ch5_i        ,
    input  wire [15:0]      ad_ch6_i        ,
    input  wire [15:0]      ad_ch7_i        ,
    input  wire [15:0]      ad_ch8_i        ,
    input  wire [15:0]      x_ch1_i         ,
    input  wire [15:0]      x_ch2_i         ,
    input  wire [15:0]      x_ch3_i         ,
    input  wire [15:0]      x_ch4_i         ,

    // Synchronized outputs (clk_dst domain)
    output reg              ad_done_o       ,
    output reg  [15:0]      ad_ch1_o        ,
    output reg  [15:0]      ad_ch2_o        ,
    output reg  [15:0]      ad_ch3_o        ,
    output reg  [15:0]      ad_ch4_o        ,
    output reg  [15:0]      ad_ch5_o        ,
    output reg  [15:0]      ad_ch6_o        ,
    output reg  [15:0]      ad_ch7_o        ,
    output reg  [15:0]      ad_ch8_o        ,
    output reg  [15:0]      x_ch1_o         ,
    output reg  [15:0]      x_ch2_o         ,
    output reg  [15:0]      x_ch3_o         ,
    output reg  [15:0]      x_ch4_o
);

    // --------------------------------------------------------
    // 2-FF synchronizer for ad_done (40 MHz ADC domain -> clk_dst)
    // --------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg ad_done_sync1;
    (* ASYNC_REG = "TRUE" *) reg ad_done_sync2;
    reg ad_done_sync2_d;

    always @(posedge clk_dst or negedge rst_n) begin
        if (!rst_n) begin
            ad_done_sync1  <= 1'b0;
            ad_done_sync2  <= 1'b0;
            ad_done_sync2_d <= 1'b0;
        end
        else begin
            ad_done_sync1  <= ad_done_i;        // 1st sync stage
            ad_done_sync2  <= ad_done_sync1;    // 2nd sync stage
            ad_done_sync2_d <= ad_done_sync2;   // edge detect delay
        end
    end

    wire ad_data_valid = !ad_done_sync2 && ad_done_sync2_d;

    // --------------------------------------------------------
    // Data latch on synchronized ad_done falling edge
    // --------------------------------------------------------
    // When ad_data_valid fires in clk_dst, the source data has already been
    // updated and held stable by ad7606_new.
    // All bits are settled before the destination latch samples them.
    always @(posedge clk_dst or negedge rst_n) begin
        if (!rst_n) begin
            ad_ch1_o <= 16'd0;
            ad_ch2_o <= 16'd0;
            ad_ch3_o <= 16'd0;
            ad_ch4_o <= 16'd0;
            ad_ch5_o <= 16'd0;
            ad_ch6_o <= 16'd0;
            ad_ch7_o <= 16'd0;
            ad_ch8_o <= 16'd0;
            x_ch1_o  <= 16'd0;
            x_ch2_o  <= 16'd0;
            x_ch3_o  <= 16'd0;
            x_ch4_o  <= 16'd0;
        end
        else if (ad_data_valid) begin
            ad_ch1_o <= ad_ch1_i;
            ad_ch2_o <= ad_ch2_i;
            ad_ch3_o <= ad_ch3_i;
            ad_ch4_o <= ad_ch4_i;
            ad_ch5_o <= ad_ch5_i;
            ad_ch6_o <= ad_ch6_i;
            ad_ch7_o <= ad_ch7_i;
            ad_ch8_o <= ad_ch8_i;
            x_ch1_o  <= x_ch1_i;
            x_ch2_o  <= x_ch2_i;
            x_ch3_o  <= x_ch3_i;
            x_ch4_o  <= x_ch4_i;
        end
    end

    // --------------------------------------------------------
    // Synchronized ADC data-valid output (single-cycle pulse in clk_dst)
    // --------------------------------------------------------
    always @(posedge clk_dst or negedge rst_n) begin
        if (!rst_n)
            ad_done_o <= 1'b0;
        else
            ad_done_o <= ad_data_valid;
    end

endmodule
