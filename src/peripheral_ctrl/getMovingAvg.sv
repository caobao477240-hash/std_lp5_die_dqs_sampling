`timescale 1ns / 1ps

/**
 * getMovingAvg
 * Compute the moving average of N signed data samples.
 * N must be a power of 2.
 *
 * Algorithm:
 *  1. Maintain a circular buffer of the N most recent input samples.
 *  2. Update the running sum by subtracting the sample being evicted
 *     and adding the new sample, avoiding accumulator overflow.
 *  3. The average is obtained by right-shifting the sum by log2(N).
 */
module getMovingAvg
#(
    parameter N              = 1024,   // Sliding window size (must be 2^n)
    parameter DIN_WIDTH      = 24      // Input data width
)
(
    output logic signed [DIN_WIDTH-1 : 0] moving_avg,  // Moving average output
    input  logic signed [DIN_WIDTH-1 : 0] din,         // Input data sample
    input  logic                          din_valid,    // Input valid flag
    input  logic                          clk,          // Clock
    input  logic                          rstn          // Reset (active low)
);

    // --------------------------------------------------------
    // Synchronization registers (double flop)
    // --------------------------------------------------------
    logic signed [DIN_WIDTH-1 : 0] din_r1;
    logic signed [DIN_WIDTH-1 : 0] din_r2;

    always_ff @(posedge clk) begin
        din_r1 <= din;
        din_r2 <= din_r1;
    end

    logic din_valid_r1;
    logic din_valid_r2;
    logic din_valid_r3;

    always_ff @(posedge clk) begin
        din_valid_r1 <= din_valid;
        din_valid_r2 <= din_valid_r1;
        din_valid_r3 <= din_valid_r2;
    end

    // --------------------------------------------------------
    // Circular buffer write pointer
    // --------------------------------------------------------
    logic [$clog2(N)-1 : 0] din_cnt;

    always_ff @(posedge clk, negedge rstn) begin
        if (~rstn)
            din_cnt <= '0;
        else if (din_valid_r2)
            din_cnt <= din_cnt + 1'b1;
    end

    // --------------------------------------------------------
    // Circular buffer: store the N most recent samples
    // --------------------------------------------------------
    logic signed [DIN_WIDTH-1 : 0] din_array [N];

    always_ff @(posedge clk, negedge rstn) begin
        if (~rstn)
            din_array <= '{default : '0};
        else if (din_valid_r2)
            din_array[din_cnt] <= din_r2;
        else
            din_array <= din_array;
    end

    // --------------------------------------------------------
    // Running sum: subtract evicted sample, add new sample
    // --------------------------------------------------------
    logic signed [$clog2(N)+DIN_WIDTH-1 : 0] sum;

    always_ff @(posedge clk, negedge rstn) begin
        if (~rstn)
            sum <= '0;
        else if (din_valid_r2)
            // No overflow risk due to the order of operations
            sum <= sum - din_array[din_cnt] + din_r2;
        else
            sum <= sum;
    end

    // --------------------------------------------------------
    // Output average (right-shift by log2(N))
    // --------------------------------------------------------
    always_ff @(posedge clk, negedge rstn) begin
        if (~rstn)
            moving_avg <= '0;
        else if (din_valid_r3)
            moving_avg <= sum[$clog2(N)+DIN_WIDTH-1 : $clog2(N)];
        else
            moving_avg <= moving_avg;
    end

endmodule