`timescale 1ns / 1ps

/**
 * watchdog
 * Generates a one-shot "done" pulse of configurable width after a reset signal.
 * - done = 1 while counter <= HIGH_CNT_MAX (10 ms @ 200 MHz)
 * - done = 0 for the remainder of the interval (200 ms @ 200 MHz)
 * - A new reset (rst_signal) restarts the sequence.
 */
module watchdog
#(
    parameter HIGH_CNT_MAX      = 10_000_000/5 - 1,  // High duration: 10 ms / 5 ns
    parameter CNT_MAX_INTERVAL  = 200_000_000/5 - 1   // Total interval: 200 ms / 5 ns
)
(
    input  wire      sys_clk    ,  // System clock (200 MHz)
    input  wire      sys_rst_n  ,  // Active-low system reset
    input  wire      rst_signal ,  // Trigger to restart the sequence
    output reg       done          // One-shot active-high flag
);

    // --------------------------------------------------------
    // Internal counter
    // --------------------------------------------------------
    reg [39:0] cnt;

    // --------------------------------------------------------
    // Counter logic
    // --------------------------------------------------------
    always @(posedge sys_clk) begin
        if (!sys_rst_n) begin
            cnt <= 'b0;
        end
        else if (rst_signal) begin
            cnt <= 'b0;
        end
        else if (cnt < HIGH_CNT_MAX + CNT_MAX_INTERVAL) begin
            cnt <= cnt + 1'b1;
        end
        else begin
            cnt <= 'b0;
        end
    end

    // --------------------------------------------------------
    // Done output generation
    // --------------------------------------------------------
    always @(posedge sys_clk) begin
        if (!sys_rst_n) begin
            done <= 1'b0;
        end
        else if (rst_signal) begin
            done <= 1'b0;
        end
        else if (cnt <= HIGH_CNT_MAX) begin
            done <= 1'b1;
        end
        else begin
            done <= 1'b0;
        end
    end

endmodule