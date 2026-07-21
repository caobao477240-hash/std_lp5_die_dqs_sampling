`timescale 1ns / 1ps

/**
 * eft3_led_ctrl_top
 * Simple LED controller that toggles an LED at a 0.5 Hz rate
 * (on for 1 second, off for 1 second) based on a 50 MHz input clock.
 */
module eft3_led_ctrl_top (
    input  wire      s_clk_i ,   // 50 MHz system clock
    input  wire      s_rstn_i,   // Active-low reset
    output wire      led         // LED output (toggles every second)
);

    // --------------------------------------------------------
    // Parameters
    //   Clock period = 20 ns (50 MHz)
    //   TIME_uS = 50   -->  1 us  = 50 x 20 ns
    //   TIME_mS = 1000 -->  1 ms  = 1000 x 1 us
    //   TIME_1S = 1000 -->  1 s   = 1000 x 1 ms
    // --------------------------------------------------------
    parameter TIME_uS = 50;      // Counts for 1 microsecond
    parameter TIME_mS = 1000;    // Counts for 1 millisecond
    parameter TIME_1S = 1000;    // Counts for 1 second

    // --------------------------------------------------------
    // Internal counters and LED register
    // --------------------------------------------------------
    reg [15:0] cnt_1us;
    reg [15:0] cnt_1ms;
    reg [15:0] cnt_1s;
    reg        led_r;

    // --------------------------------------------------------
    // Output assignment
    // --------------------------------------------------------
    assign led = led_r;

    // --------------------------------------------------------
    // 1 microsecond counter
    // --------------------------------------------------------
    always @(posedge s_clk_i or negedge s_rstn_i) begin
        if (!s_rstn_i) begin
            cnt_1us <= 16'd0;
        end
        else if (cnt_1us == TIME_uS - 1) begin
            cnt_1us <= 16'd0;
        end
        else begin
            cnt_1us <= cnt_1us + 1'b1;
        end
    end

    // --------------------------------------------------------
    // 1 millisecond counter
    // --------------------------------------------------------
    always @(posedge s_clk_i or negedge s_rstn_i) begin
        if (!s_rstn_i) begin
            cnt_1ms <= 16'd0;
        end
        else if (cnt_1ms == TIME_mS - 1) begin
            cnt_1ms <= 16'd0;
        end
        else if (cnt_1us == TIME_uS - 1) begin
            cnt_1ms <= cnt_1ms + 1'b1;
        end
    end

    // --------------------------------------------------------
    // 1 second counter
    // --------------------------------------------------------
    always @(posedge s_clk_i or negedge s_rstn_i) begin
        if (!s_rstn_i) begin
            cnt_1s <= 16'd0;
        end
        else if (cnt_1s == TIME_1S - 1) begin
            cnt_1s <= 16'd0;
        end
        else if (cnt_1ms == TIME_mS - 1) begin
            cnt_1s <= cnt_1s + 1'b1;
        end
    end

    // --------------------------------------------------------
    // LED toggle every second
    // --------------------------------------------------------
    always @(posedge s_clk_i or negedge s_rstn_i) begin
        if (!s_rstn_i) begin
            led_r <= 1'b0;
        end
        else if (cnt_1s == TIME_1S - 1) begin
            led_r <= ~led_r;
        end
    end

endmodule