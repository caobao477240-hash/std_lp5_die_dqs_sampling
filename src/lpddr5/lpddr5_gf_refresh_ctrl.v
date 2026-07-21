`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
// Create Date:     2026/07/10
// Design Name:     LPDDR5 GF
// Module Name:     lpddr5_gf_refresh_ctrl
// Project Name:    std_lp5_die_clk800M
// Target Devices:
// Tool Versions:   VIVADO2022.2
// Description:     Sequential GF refresh credit and batch controller.
// Dependencies:
// Revision:        v0.1
//////////////////////////////////////////////////////////////////////////////////

module lpddr5_gf_refresh_ctrl #(
    parameter       [28:0]  P_TRFCAB            = 29'd80,
    parameter       [28:0]  P_T_REFI_CYCLES     = 29'd781,
    parameter       [28:0]  P_CMD_START_CNT     = 29'd3,
    parameter       [ 3:0]  P_CREDIT_MAX        = 4'd8
) (
    input                   i_clk                         ,
    input                   i_rst_n                       ,
    input                   i_enable                      ,
    input                   i_refresh_active              ,
    input                   i_ck_active                   ,
    input           [ 2:0]  i_batch_num                   ,

    output          [28:0]  o_refresh_cnt                 ,
    output          [28:0]  o_refi_cnt                    ,
    output                  o_refresh_cnt_flag            ,
    output                  o_refresh_due                 ,
    output                  o_refresh_cmd                 ,
    output                  o_refresh_done                ,
    output          [ 3:0]  o_refresh_credit              ,
    output          [ 3:0]  o_refresh_batch_num           ,
    output          [ 3:0]  o_refresh_batch_left
);

/***************function**************/
/***************parameter*************/
/***************port******************/
/***************mechine***************/
/***************reg*******************/
    reg             [28:0]  r_refresh_cnt                 ;
    reg             [28:0]  r_refi_cnt                    ;
    reg                     r_refresh_cnt_flag            ;
    reg                     r_refresh_due                 ;
    reg                     r_refresh_active_d            ;
    reg             [ 3:0]  r_refresh_credit              ;
    reg             [ 3:0]  r_refresh_batch_num           ;
    reg             [ 3:0]  r_refresh_batch_left          ;

/***************wire******************/
    wire                    w_refresh_cnt_run             ;
    wire                    w_refi_timer_done             ;
    wire                    w_refresh_start               ;
    wire                    w_refab_done                  ;
    wire                    w_refab_last                  ;
    wire                    w_refresh_done                ;
    wire                    w_credit_add                  ;
    wire                    w_credit_sub                  ;
    wire            [ 3:0]  w_batch_num_cfg              ;
    wire            [ 3:0]  w_credit_threshold           ;
    wire            [ 3:0]  w_credit_next                ;

/***************component*************/
/***************assign****************/
assign o_refresh_cnt        = r_refresh_cnt;
assign o_refi_cnt           = r_refi_cnt;
assign o_refresh_cnt_flag   = r_refresh_cnt_flag;
assign o_refresh_due        = r_refresh_due;
assign o_refresh_cmd        = w_refresh_cnt_run &&
                              (r_refresh_cnt == P_CMD_START_CNT);
assign o_refresh_done       = w_refresh_done;
assign o_refresh_credit     = r_refresh_credit;
assign o_refresh_batch_num  = r_refresh_batch_num;
assign o_refresh_batch_left = r_refresh_batch_left;

assign w_refresh_cnt_run   = i_refresh_active && r_refresh_cnt_flag;
assign w_refi_timer_done   = i_enable &&
                             (r_refi_cnt >= (P_T_REFI_CYCLES - 29'd1));
assign w_refresh_start     = i_refresh_active &&
                             (r_refresh_active_d == 1'b0);
assign w_refab_done        = w_refresh_cnt_run &&
                             (r_refresh_cnt >= (P_TRFCAB - 29'd1));
assign w_refab_last        = (r_refresh_batch_left <= 4'd1);
assign w_refresh_done      = w_refab_done && w_refab_last;
assign w_credit_add        = w_refi_timer_done;
assign w_credit_sub        = w_refab_done &&
                             (r_refresh_credit != 4'd0);
assign w_batch_num_cfg     = (i_batch_num == 3'd0) ? 4'd8 :
                             ((i_batch_num == 3'd4) ? 4'd4 : 4'd1);
assign w_credit_threshold  = r_refresh_batch_num;
assign w_credit_next       = (w_credit_add && (w_credit_sub == 1'b0)) ?
                             ((r_refresh_credit < P_CREDIT_MAX) ?
                              (r_refresh_credit + 4'd1) :
                              r_refresh_credit) :
                             ((w_credit_add == 1'b0) && w_credit_sub) ?
                             ((r_refresh_credit > 4'd0) ?
                              (r_refresh_credit - 4'd1) :
                              4'd0) :
                             r_refresh_credit;

/***************always****************/
always @(posedge i_clk or negedge i_rst_n) begin
    if (i_rst_n == 1'b0)
        r_refresh_cnt <= 29'd0;
    else if (i_refresh_active == 1'b0)
        r_refresh_cnt <= 29'd0;
    else if (w_refab_done == 1'b1)
        r_refresh_cnt <= 29'd0;
    else if (w_refresh_cnt_run == 1'b1)
        r_refresh_cnt <= r_refresh_cnt + 29'd1;
    else
        r_refresh_cnt <= r_refresh_cnt;
end

always @(posedge i_clk or negedge i_rst_n) begin
    if (i_rst_n == 1'b0)
        r_refresh_cnt_flag <= 1'b0;
    else if (i_refresh_active == 1'b0)
        r_refresh_cnt_flag <= 1'b0;
    else if (w_refresh_done == 1'b1)
        r_refresh_cnt_flag <= 1'b0;
    else if ((i_ck_active == 1'b1) &&
             (i_refresh_active == 1'b1))
        r_refresh_cnt_flag <= 1'b1;
    else
        r_refresh_cnt_flag <= r_refresh_cnt_flag;
end

always @(posedge i_clk or negedge i_rst_n) begin
    if (i_rst_n == 1'b0)
        r_refi_cnt <= 29'd0;
    else if (i_enable == 1'b0)
        r_refi_cnt <= 29'd0;
    else if (w_refi_timer_done == 1'b1)
        r_refi_cnt <= 29'd0;
    else
        r_refi_cnt <= r_refi_cnt + 29'd1;
end

always @(posedge i_clk or negedge i_rst_n) begin
    if (i_rst_n == 1'b0)
        r_refresh_due <= 1'b0;
    else if (i_enable == 1'b0)
        r_refresh_due <= 1'b0;
    else if (w_credit_next >= w_credit_threshold)
        r_refresh_due <= 1'b1;
    else
        r_refresh_due <= 1'b0;
end

always @(posedge i_clk or negedge i_rst_n) begin
    if (i_rst_n == 1'b0)
        r_refresh_credit <= 4'd0;
    else if (i_enable == 1'b0)
        r_refresh_credit <= 4'd0;
    else
        r_refresh_credit <= w_credit_next;
end

always @(posedge i_clk or negedge i_rst_n) begin
    if (i_rst_n == 1'b0)
        r_refresh_batch_num <= 4'd1;
    else if (i_enable == 1'b0)
        r_refresh_batch_num <= w_batch_num_cfg;
    else
        r_refresh_batch_num <= r_refresh_batch_num;
end

always @(posedge i_clk or negedge i_rst_n) begin
    if (i_rst_n == 1'b0)
        r_refresh_batch_left <= 4'd0;
    else if (i_enable == 1'b0)
        r_refresh_batch_left <= 4'd0;
    else if (w_refresh_start == 1'b1)
        r_refresh_batch_left <= r_refresh_batch_num;
    else if (w_refab_done == 1'b1) begin
        if (r_refresh_batch_left > 4'd1)
            r_refresh_batch_left <= r_refresh_batch_left - 4'd1;
        else
            r_refresh_batch_left <= 4'd0;
    end
    else
        r_refresh_batch_left <= r_refresh_batch_left;
end

always @(posedge i_clk or negedge i_rst_n) begin
    if (i_rst_n == 1'b0)
        r_refresh_active_d <= 1'b0;
    else if (i_enable == 1'b0)
        r_refresh_active_d <= 1'b0;
    else
        r_refresh_active_d <= i_refresh_active;
end

endmodule
