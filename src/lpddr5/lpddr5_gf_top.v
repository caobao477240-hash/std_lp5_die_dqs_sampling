`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
// Create Date:     2026/07/02
// Design Name:     LPDDR5 GF
// Module Name:     lpddr5_gf
// Project Name:    std_lp5_die_clk800M
// Target Devices:  Xilinx UltraScale
// Tool Versions:   Vivado 2022.2
// Description:
//   LPDDR5 gross-function scheduler and channel-A GF waveform engine.
//   The outer controller launches a standard March C- sequence.
//   The engine owns GF command timing, WCK timing, DQ transmit word generation,
//   DQ receive comparison, address traversal, and error reporting.
// Dependencies:
//   BLOCK64
// Revision:        v0.1
//////////////////////////////////////////////////////////////////////////////////

/***************module**************/
module lpddr5_gf (
    // Clock / Reset
    input                               cha_core_clk               ,
    input                               cha_phy_rst_n              ,
    input                               clk_200m                   ,
    input                               rst_n                      ,

    // DUT density / sequence control
    input                [   7: 0]      die_message                ,
    output reg           [   1: 0]      gf_op_mode                 ,
    output reg                          gf_read_data_sel           ,
    output reg                          gf_write_data_sel          ,
    output reg                          march_y_sequence           ,

    // GF total control
    input                               GF_total_en                ,
    output reg                          GF_total_done              ,
    output reg           [  95: 0]      GF_result_data             ,

    // Channel A GF step control
    output reg                          cha_GF_inner_en            ,
    input                               cha_GF_inner_done          ,
    input                [  31: 0]      cha_err_cnt_GF             ,
    output reg           [   5: 0]      cha_GF_start_col           ,
    output reg           [   5: 0]      cha_GF_end_col             ,
    output reg           [  17: 0]      cha_GF_start_row           ,
    output reg           [  17: 0]      cha_GF_end_row             ,
    output reg           [   1: 0]      cha_GF_start_bg            ,
    output reg           [   1: 0]      cha_GF_end_bg              ,
    output reg           [   1: 0]      cha_GF_start_ba            ,
    output reg           [   1: 0]      cha_GF_end_ba
);

/***************parameter*************/
// Standard March C- operation order:
// w0; up(r0,w1); up(r1,w0); down(r0,w1); down(r1,w0); r0.
// Logical 0/1 are encoded as address-dependent data:
//   data_sel=0: even address -> addr, odd address -> ~addr
//   data_sel=1: even address -> ~addr, odd address -> addr
    localparam      [   1: 0]      GF_RANGE_DEBUG              = 2'd0                 ;
    localparam      [   1: 0]      GF_RANGE_FULL               = 2'd1                 ;
`ifdef LP5_SIM_ONE_ROW_GF
    localparam      [   1: 0]      GF_RANGE_MODE               = GF_RANGE_DEBUG       ;
`else
    localparam      [   1: 0]      GF_RANGE_MODE               = GF_RANGE_FULL        ;
`endif
    localparam      [   5: 0]      GF_COL_START                = 6'h00                ;
    localparam      [   5: 0]      GF_COL_END_FULL             = 6'h3F                ;
    localparam      [   5: 0]      GF_COL_END_DEBUG            = 6'h03                ;
    localparam      [   5: 0]      GF_COL_END                  = (GF_RANGE_MODE == GF_RANGE_DEBUG) ? GF_COL_END_DEBUG : GF_COL_END_FULL;
    localparam      [  17: 0]      GF_ROW_START                = 18'h0000             ;
    localparam      [  17: 0]      GF_ROW_END_6G_FULL          = 18'h5FFF             ;
    localparam      [  17: 0]      GF_ROW_END_8G_FULL          = 18'h7FFF             ;
    localparam      [  17: 0]      GF_ROW_END_12G_FULL         = 18'hBFFF             ;
    localparam      [  17: 0]      GF_ROW_END_16G_FULL         = 18'hFFFF             ;
    localparam      [  17: 0]      GF_ROW_END_DEBUG            = 18'h0000             ;
    localparam      [  17: 0]      GF_ROW_END_6G               = (GF_RANGE_MODE == GF_RANGE_DEBUG) ? GF_ROW_END_DEBUG : GF_ROW_END_6G_FULL;
    localparam      [  17: 0]      GF_ROW_END_8G               = (GF_RANGE_MODE == GF_RANGE_DEBUG) ? GF_ROW_END_DEBUG : GF_ROW_END_8G_FULL;
    localparam      [  17: 0]      GF_ROW_END_12G              = (GF_RANGE_MODE == GF_RANGE_DEBUG) ? GF_ROW_END_DEBUG : GF_ROW_END_12G_FULL;
    localparam      [  17: 0]      GF_ROW_END_16G              = (GF_RANGE_MODE == GF_RANGE_DEBUG) ? GF_ROW_END_DEBUG : GF_ROW_END_16G_FULL;
    localparam      [   1: 0]      GF_BG_START                 = 2'd0                 ;
    localparam      [   1: 0]      GF_BG_END_FULL              = 2'd3                 ;
    localparam      [   1: 0]      GF_BG_END_DEBUG             = 2'd0                 ;
    localparam      [   1: 0]      GF_BG_END                   = (GF_RANGE_MODE == GF_RANGE_DEBUG) ? GF_BG_END_DEBUG : GF_BG_END_FULL;
    localparam      [   1: 0]      GF_BA_START                 = 2'd0                 ;
    localparam      [   1: 0]      GF_BA_END_FULL              = 2'd3                 ;
    localparam      [   1: 0]      GF_BA_END_DEBUG             = 2'd1                 ;
    localparam      [   1: 0]      GF_BA_END                   = (GF_RANGE_MODE == GF_RANGE_DEBUG) ? GF_BA_END_DEBUG : GF_BA_END_FULL;
    localparam      [   7: 0]      GF_PASS_COUNT               = 8'd6                 ;

    localparam      [   1: 0]      GF_OP_WRITE_ONLY            = 2'd0                 ;
    localparam      [   1: 0]      GF_OP_READ_ONLY             = 2'd1                 ;
    localparam      [   1: 0]      GF_OP_READ_WRITE            = 2'd2                 ;

    parameter TESTING = 8'h00;
    parameter PASS    = 8'hC9;
    parameter FAIL    = 8'h9C;

/***************reg*******************/
    reg                  [  47: 0]      gf_start_col_bus           ;
    reg                  [  47: 0]      gf_end_col_bus             ;
    reg                  [ 143: 0]      gf_start_row_bus           ;
    reg                  [ 143: 0]      gf_end_row_bus             ;

    reg                  [   7: 0]      result                     ;
    reg                                 GF_total_en_r              ;
    reg                  [   7: 0]      cha_inner_done_cnt         ;
    reg                                 err_flag                   ;

/***************wire******************/
    wire                 [   5: 0]      PARAM_0_GF_start_col       ;
    wire                 [   5: 0]      PARAM_0_GF_end_col         ;
    wire                 [  17: 0]      PARAM_0_GF_start_row       ;
    wire                 [  17: 0]      PARAM_0_GF_end_row         ;
    wire                 [   1: 0]      PARAM_0_GF_start_bg        ;
    wire                 [   1: 0]      PARAM_0_GF_end_bg          ;
    wire                 [   1: 0]      PARAM_0_GF_start_ba        ;
    wire                 [   1: 0]      PARAM_0_GF_end_ba          ;
    wire                                gf_total_done_level        ;
    wire                                gf_any_error               ;
    wire                 [   7: 0]      gf_pass_count              ;

/***************assign****************/
    assign gf_pass_count       = GF_PASS_COUNT;
    assign gf_total_done_level = GF_total_en && (cha_inner_done_cnt == gf_pass_count);
    assign gf_any_error        = err_flag || (cha_err_cnt_GF > 32'd0);
    assign PARAM_0_GF_start_col = gf_start_col_bus[5:0];
    assign PARAM_0_GF_end_col   = gf_end_col_bus[5:0];
    assign PARAM_0_GF_start_row = gf_start_row_bus[17:0];
    assign PARAM_0_GF_end_row   = gf_end_row_bus[17:0];
    assign PARAM_0_GF_start_bg  = GF_BG_START;
    assign PARAM_0_GF_end_bg    = GF_BG_END;
    assign PARAM_0_GF_start_ba  = GF_BA_START;
    assign PARAM_0_GF_end_ba    = GF_BA_END;

/***************always****************/
    always @(posedge clk_200m or negedge rst_n) begin
        if(!rst_n) begin
            gf_start_col_bus <= {8{GF_COL_START}};
            gf_end_col_bus   <= {8{GF_COL_END}};
            gf_start_row_bus <= {8{GF_ROW_START}};
            gf_end_row_bus   <= {8{GF_ROW_END_16G}};
        end
        else if(die_message == 8'h14) begin
            gf_start_col_bus <= {8{GF_COL_START}};
            gf_end_col_bus   <= {8{GF_COL_END}};
            gf_start_row_bus <= {8{GF_ROW_START}};
            gf_end_row_bus   <= {8{GF_ROW_END_12G}};
        end
        else if(die_message == 8'h10) begin
            gf_start_col_bus <= {8{GF_COL_START}};
            gf_end_col_bus   <= {8{GF_COL_END}};
            gf_start_row_bus <= {8{GF_ROW_START}};
            gf_end_row_bus   <= {8{GF_ROW_END_8G}};
        end
        else if(die_message == 8'h0C) begin
            gf_start_col_bus <= {8{GF_COL_START}};
            gf_end_col_bus   <= {8{GF_COL_END}};
            gf_start_row_bus <= {8{GF_ROW_START}};
            gf_end_row_bus   <= {8{GF_ROW_END_6G}};
        end
        else if((die_message == 8'h18) || (die_message == 8'h19)) begin
            gf_start_col_bus <= {8{GF_COL_START}};
            gf_end_col_bus   <= {8{GF_COL_END}};
            gf_start_row_bus <= {8{GF_ROW_START}};
            gf_end_row_bus   <= {8{GF_ROW_END_16G}};
        end
        else begin
            gf_start_col_bus <= gf_start_col_bus;
            gf_end_col_bus   <= gf_end_col_bus;
            gf_start_row_bus <= gf_start_row_bus;
            gf_end_row_bus   <= gf_end_row_bus;
        end
    end

    always @(posedge clk_200m or negedge rst_n) begin
        if (!rst_n)
            GF_total_en_r <= 'd0;
        else
            GF_total_en_r <= GF_total_en;
        end

    // --------------------------------------------------------
    // Overall done flag (all planned traversals completed)
    // --------------------------------------------------------
    always @(posedge clk_200m or negedge rst_n) begin
        if (!rst_n)
            GF_total_done <= 1'b0;
        else if (GF_total_en == 1'b0)
            GF_total_done <= 1'b0;
        else if (gf_total_done_level)
            GF_total_done <= 1'b1;
    end

    // --------------------------------------------------------
    // Error flag latch (sticky until next total enable rising edge)
    // --------------------------------------------------------
    always @(posedge clk_200m or negedge rst_n) begin
        if (!rst_n)
            err_flag <= 1'b0;
        else if (GF_total_en && !GF_total_en_r)
            err_flag <= 1'b0;
        else if (cha_err_cnt_GF > 0)
            err_flag <= 1'b1;
        else
            err_flag <= err_flag;
    end

    // --------------------------------------------------------
    // PASS / FAIL result
    // --------------------------------------------------------
    always @(posedge clk_200m or negedge rst_n) begin
        if (!rst_n)
            result <= TESTING;
        else if (GF_total_en && !GF_total_en_r)
            result <= TESTING;
        else if (gf_total_done_level || GF_total_done)
            result <= gf_any_error ? FAIL : PASS;
        else
            result <= result;
    end

    // --------------------------------------------------------
    // Final result data packet (sent to host)
    // --------------------------------------------------------
    always @(posedge clk_200m or negedge rst_n) begin
        if (!rst_n)
            GF_result_data <= 'd0;
        else
            GF_result_data <= {7'd0, GF_total_en, cha_err_cnt_GF, result,
                               7'd0, GF_total_en, cha_err_cnt_GF, result};
    end

    // --------------------------------------------------------
    // Channel A inner done counter
    // --------------------------------------------------------
    always @(posedge cha_core_clk or negedge cha_phy_rst_n) begin
        if (!cha_phy_rst_n)
            cha_inner_done_cnt <= 'd0;
        else if (!GF_total_en)
            cha_inner_done_cnt <= 'd0;
        else if (cha_GF_inner_done && (cha_inner_done_cnt < gf_pass_count))
            cha_inner_done_cnt <= cha_inner_done_cnt + 1'd1;
    end

    // --------------------------------------------------------
    // Channel A inner enable generation
    // --------------------------------------------------------
    always @(posedge cha_core_clk or negedge cha_phy_rst_n) begin
        if (!cha_phy_rst_n)
            cha_GF_inner_en <= 1'b0;
        else if (!GF_total_en)
            cha_GF_inner_en <= 1'b0;
        else if (cha_GF_inner_done)
            cha_GF_inner_en <= 1'b0;
        else if (GF_total_en && (cha_inner_done_cnt < gf_pass_count))
            cha_GF_inner_en <= 1'b1;
        else
            cha_GF_inner_en <= 1'b0;
    end

    // --------------------------------------------------------
    // Pass parameter selection (based on traversal index)
    // --------------------------------------------------------
    always @(posedge cha_core_clk or negedge cha_phy_rst_n) begin
        if (!cha_phy_rst_n) begin
            cha_GF_start_col   <= 6'h0;
            cha_GF_end_col     <= 6'h0;
            cha_GF_start_row   <= 18'd0;
            cha_GF_end_row     <= 18'd0;
            cha_GF_start_bg    <= 2'd0;
            cha_GF_end_bg      <= 2'd0;
            cha_GF_start_ba    <= 2'd0;
            cha_GF_end_ba      <= 2'd0;
        end
        else if (!cha_GF_inner_done) begin
            cha_GF_start_col   <= PARAM_0_GF_start_col;
            cha_GF_end_col     <= PARAM_0_GF_end_col  ;
            cha_GF_start_row   <= PARAM_0_GF_start_row;
            cha_GF_end_row     <= PARAM_0_GF_end_row  ;
            cha_GF_start_bg    <= PARAM_0_GF_start_bg ;
            cha_GF_end_bg      <= PARAM_0_GF_end_bg   ;
            cha_GF_start_ba    <= PARAM_0_GF_start_ba ;
            cha_GF_end_ba      <= PARAM_0_GF_end_ba   ;
        end
        else begin
            cha_GF_start_col   <= cha_GF_start_col;
            cha_GF_end_col     <= cha_GF_end_col;
            cha_GF_start_row   <= cha_GF_start_row;
            cha_GF_end_row     <= cha_GF_end_row;
            cha_GF_start_bg    <= cha_GF_start_bg;
            cha_GF_end_bg      <= cha_GF_end_bg;
            cha_GF_start_ba    <= cha_GF_start_ba;
            cha_GF_end_ba      <= cha_GF_end_ba;
        end
    end

    always @(posedge cha_core_clk or negedge cha_phy_rst_n) begin
        if (!cha_phy_rst_n)
            gf_op_mode <= GF_OP_WRITE_ONLY;
        else if (!GF_total_en)
            gf_op_mode <= GF_OP_WRITE_ONLY;
        else if (cha_inner_done_cnt == 8'd0)
            gf_op_mode <= GF_OP_WRITE_ONLY;
        else if (cha_inner_done_cnt == 8'd5)
            gf_op_mode <= GF_OP_READ_ONLY;
        else if (cha_inner_done_cnt < GF_PASS_COUNT)
            gf_op_mode <= GF_OP_READ_WRITE;
        else
            gf_op_mode <= GF_OP_WRITE_ONLY;
        end

    always @(posedge cha_core_clk or negedge cha_phy_rst_n) begin
        if (!cha_phy_rst_n)
            gf_read_data_sel <= 1'b0;
        else if (!GF_total_en)
            gf_read_data_sel <= 1'b0;
        else if (cha_inner_done_cnt == 8'd2)
            gf_read_data_sel <= 1'b1;
        else if (cha_inner_done_cnt == 8'd4)
            gf_read_data_sel <= 1'b1;
        else
            gf_read_data_sel <= 1'b0;
        end

    always @(posedge cha_core_clk or negedge cha_phy_rst_n) begin
        if (!cha_phy_rst_n)
            gf_write_data_sel <= 1'b0;
        else if (!GF_total_en)
            gf_write_data_sel <= 1'b0;
        else if (cha_inner_done_cnt == 8'd1)
            gf_write_data_sel <= 1'b1;
        else if (cha_inner_done_cnt == 8'd3)
            gf_write_data_sel <= 1'b1;
        else
            gf_write_data_sel <= 1'b0;
        end

    always @(posedge cha_core_clk or negedge cha_phy_rst_n) begin
        if (!cha_phy_rst_n)
            march_y_sequence <= 1'b0;
        else if (!GF_total_en)
            march_y_sequence <= 1'b0;
        else if (cha_inner_done_cnt == 8'd3)
            march_y_sequence <= 1'b1;
        else if (cha_inner_done_cnt == 8'd4)
            march_y_sequence <= 1'b1;
        else
            march_y_sequence <= 1'b0;
        end

endmodule
