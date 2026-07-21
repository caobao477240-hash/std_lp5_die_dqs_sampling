`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Company:         GCS
// Engineer:        qige style
// Create Date:     2026/07/10
// Design Name:     LPDDR5 GF
// Module Name:     lpddr5_gf_stream_timer
// Project Name:    std_lp5_die_clk800M
// Target Devices:  Xilinx UltraScale
// Tool Versions:   Vivado 2022.2
// Description:
//   Generates one bank-stream slot at start_cnt + slot*gap_cnt. Two-cycle
//   commands optionally generate a second pulse one clk_200m cycle later.
//////////////////////////////////////////////////////////////////////////////////

module lpddr5_gf_stream_timer #(
    parameter                       P_SECOND_PULSE_EN      = 1'b0,
    parameter       [   9: 0]       P_RESET_GAP_CNT       = 10'd1
) (
    input                           i_clk                         ,
    input                           i_rst_n                       ,
    input                           i_clear                       ,
    input                           i_stream_active               ,
    input                           i_cnt_run                     ,
    input           [   9: 0]       i_cnt                         ,
    input           [   9: 0]       i_start_cnt                   ,
    input           [   9: 0]       i_gap_cnt                     ,
    input           [   4: 0]       i_last_slot                   ,
    output          [   9: 0]       o_gap_cnt                     ,
    output          [   4: 0]       o_slot                        ,
    output          [   9: 0]       o_next_start_cnt              ,
    output          [   9: 0]       o_last_start_cnt              ,
    output                          o_first                       ,
    output                          o_second                      ,
    output                          o_done
);

/***************function**************/
/***************parameter*************/
/***************port******************/
/***************mechine***************/
/***************reg*******************/
    reg             [   9: 0]       r_gap_cnt                     ;
    reg             [   4: 0]       r_slot                        ;
    reg             [   9: 0]       r_next_start_cnt              ;
    reg             [   9: 0]       r_last_start_cnt              ;
    reg                             r_done                        ;

/***************wire******************/
    wire            [   9: 0]       w_second_cnt                  ;
    wire            [  10: 0]       w_next_start_sum_full         ;
    wire            [   9: 0]       w_next_start_sum              ;
    wire                            w_slot_valid                  ;
    wire                            w_slot_complete               ;

/***************component*************/
/***************assign****************/
assign o_gap_cnt            = r_gap_cnt;
assign o_slot               = r_slot;
assign o_next_start_cnt     = r_next_start_cnt;
assign o_last_start_cnt     = r_last_start_cnt;
assign o_done               = r_done;

assign w_second_cnt         = r_next_start_cnt + 10'd1;
assign w_next_start_sum_full = {1'b0, r_next_start_cnt} +
                               {1'b0, r_gap_cnt};
assign w_next_start_sum     = (w_next_start_sum_full > 11'd1023) ?
                              10'h3ff :
                              w_next_start_sum_full[9:0];
assign w_slot_valid         = (r_slot <= i_last_slot);

assign o_first              = i_cnt_run &&
                              (r_done == 1'b0) &&
                              (w_slot_valid == 1'b1) &&
                              (i_cnt == r_next_start_cnt);
assign o_second             = (P_SECOND_PULSE_EN == 1'b1) &&
                              i_cnt_run &&
                              (r_done == 1'b0) &&
                              (w_slot_valid == 1'b1) &&
                              (i_cnt == w_second_cnt);
assign w_slot_complete      = (P_SECOND_PULSE_EN == 1'b1) ?
                              o_second :
                              o_first;

/***************always****************/
always @(posedge i_clk or negedge i_rst_n) begin
    if (i_rst_n == 1'b0) begin
        r_gap_cnt        <= P_RESET_GAP_CNT;
        r_slot           <= 5'd0;
        r_next_start_cnt <= 10'd0;
        r_last_start_cnt <= 10'd0;
        r_done           <= 1'b0;
    end
    else if ((i_clear == 1'b1) || (i_stream_active == 1'b0)) begin
        r_gap_cnt        <= i_gap_cnt;
        r_slot           <= 5'd0;
        r_next_start_cnt <= i_start_cnt;
        r_last_start_cnt <= i_start_cnt;
        r_done           <= 1'b0;
    end
    else if (i_cnt_run == 1'b1) begin
        r_gap_cnt <= r_gap_cnt;

        if (o_first == 1'b1)
            r_last_start_cnt <= r_next_start_cnt;
        else
            r_last_start_cnt <= r_last_start_cnt;

        if ((w_slot_complete == 1'b1) &&
            (r_slot >= i_last_slot)) begin
            r_slot           <= r_slot;
            r_next_start_cnt <= r_next_start_cnt;
            r_done           <= 1'b1;
        end
        else if (w_slot_complete == 1'b1) begin
            r_slot           <= r_slot + 5'd1;
            r_next_start_cnt <= w_next_start_sum;
            r_done           <= r_done;
        end
        else begin
            r_slot           <= r_slot;
            r_next_start_cnt <= r_next_start_cnt;
            r_done           <= r_done;
        end
    end
    else begin
        r_gap_cnt        <= r_gap_cnt;
        r_slot           <= r_slot;
        r_next_start_cnt <= r_next_start_cnt;
        r_last_start_cnt <= r_last_start_cnt;
        r_done           <= r_done;
    end
end

endmodule
