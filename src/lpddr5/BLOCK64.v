module BLOCK64
(
    input                               clk                        ,
    input                               rst_n                      ,
    input                               gf_test_en                 ,
    input                [   7: 0]      die_message                ,
    input                [   1: 0]      cnt_bg                     ,
    input                [   1: 0]      cnt_ba                     ,
    input                [  17: 0]      cnt_row                    ,
    input                [  17: 0]      cnt_row_ns                 ,
    input                               march_y_sequence           ,
    input                               err_flag                   ,
    output reg           [   7: 0]      err_block_cnt              ,
    output               [  63: 0]      err_block_message
);

parameter [7:0] lp5_Den_6Gb    = 8'h0C,
                lp5_Den_8Gb    = 8'h10,
                lp5_Den_12Gb   = 8'h14,
                lp5_Den_16Gb   = 8'h18,
                lp5x_Den_6Gb   = 8'h0D,
                lp5x_Den_8Gb   = 8'h11,
                lp5x_Den_12Gb  = 8'h15,
                lp5x_Den_16Gb  = 8'h19;

    reg                  [   1: 0]      gf_test_en_d               ;

    reg                  [   5: 0]      block1_bd                  ;
    reg                  [   5: 0]      block2_bd                  ;
    reg                  [   5: 0]      block3_bd                  ;
    reg                  [   5: 0]      block4_bd                  ;

    reg                  [   3: 0]      bank_errflag[0:15]         ;
    reg                  [   3: 0]      bank_pair_err_cnt[0:7]     ;

    wire                 [   3: 0]      active_bank                ;
    wire                                gf_start_rise              ;
    wire                                density_uses_16gb_blocks   ;
    wire                                density_uses_8gb_blocks    ;
    wire                                density_has_partial_block  ;

assign active_bank   = {cnt_bg, cnt_ba};
assign gf_start_rise = (gf_test_en_d[0] == 1'b1) && (gf_test_en_d[1] == 1'b0);

// 12Gb/16Gb devices use the 16Gb block boundaries. 6Gb/8Gb devices use
// the 8Gb boundaries. The unused fourth block of a 6Gb/12Gb device is
// marked as unavailable in the returned block bitmap.
assign density_uses_16gb_blocks =
       (die_message == lp5_Den_12Gb)
    || (die_message == lp5_Den_16Gb)
    || (die_message == lp5x_Den_12Gb)
    || (die_message == lp5x_Den_16Gb);

assign density_uses_8gb_blocks =
       (die_message == lp5_Den_6Gb)
    || (die_message == lp5_Den_8Gb)
    || (die_message == lp5x_Den_6Gb)
    || (die_message == lp5x_Den_8Gb);

assign density_has_partial_block =
       (die_message == lp5_Den_6Gb)
    || (die_message == lp5_Den_12Gb)
    || (die_message == lp5x_Den_6Gb)
    || (die_message == lp5x_Den_12Gb);

// Register the GF enable history. The original design clears all block
// results one cycle after the enable rising edge; keep that timing.
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        gf_test_en_d <= 2'b00;
    else
        gf_test_en_d <= {gf_test_en_d[0], gf_test_en};
end

// Row[16:11] selects one of four blocks in the active bank.
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        block1_bd <= 6'd8;
        block2_bd <= 6'd16;
        block3_bd <= 6'd24;
        block4_bd <= 6'd32;
    end
    else if (density_uses_16gb_blocks) begin
        block1_bd <= 6'd8;
        block2_bd <= 6'd16;
        block3_bd <= 6'd24;
        block4_bd <= 6'd32;
    end
    else if (density_uses_8gb_blocks) begin
        block1_bd <= 6'd4;
        block2_bd <= 6'd8;
        block3_bd <= 6'd12;
        block4_bd <= 6'd16;
    end
end

genvar bank_index;
generate
    for (bank_index = 0; bank_index < 16; bank_index = bank_index + 1) begin : GEN_BANK_ERROR
        localparam [3:0] BANK_ID = bank_index;

        assign err_block_message[(bank_index * 4) +: 4] =
            bank_errflag[bank_index];

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                bank_errflag[bank_index] <= 4'b0000;
            end
            else if (gf_start_rise) begin
                bank_errflag[bank_index] <= 4'b0000;
            end
            else if (!march_y_sequence) begin
                if (err_flag && (cnt_row[16:11] < block1_bd) && (active_bank == BANK_ID))
                    bank_errflag[bank_index][0] <= 1'b1;
                else if (err_flag && (cnt_row[16:11] < block2_bd) && (active_bank == BANK_ID))
                    bank_errflag[bank_index][1] <= 1'b1;
                else if (err_flag && (cnt_row[16:11] < block3_bd) && (active_bank == BANK_ID))
                    bank_errflag[bank_index][2] <= 1'b1;
                else if (err_flag && (cnt_row[16:11] < block4_bd) && (active_bank == BANK_ID))
                    bank_errflag[bank_index][3] <= 1'b1;
                else if (density_has_partial_block)
                    bank_errflag[bank_index][3] <= 1'b1;
            end
            else if (march_y_sequence) begin
                if (err_flag && (cnt_row_ns[16:11] < block1_bd) && (active_bank == BANK_ID))
                    bank_errflag[bank_index][0] <= 1'b1;
                else if (err_flag && (cnt_row_ns[16:11] < block2_bd) && (active_bank == BANK_ID))
                    bank_errflag[bank_index][1] <= 1'b1;
                else if (err_flag && (cnt_row_ns[16:11] < block3_bd) && (active_bank == BANK_ID))
                    bank_errflag[bank_index][2] <= 1'b1;
                else if (err_flag && (cnt_row_ns[16:11] < block4_bd) && (active_bank == BANK_ID))
                    bank_errflag[bank_index][3] <= 1'b1;
                else if (density_has_partial_block)
                    bank_errflag[bank_index][3] <= 1'b1;
            end
        end
    end
endgenerate

function [3:0] count_two_banks;
    input [3:0] bank_low;
    input [3:0] bank_high;
    begin
        count_two_banks =
              bank_low[0]  + bank_low[1]
            + bank_low[2]  + bank_low[3]
            + bank_high[0] + bank_high[1]
            + bank_high[2] + bank_high[3];
    end
endfunction

// Keep the original two-stage count pipeline:
// bank flags -> pair counts -> total bad-block count.
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        bank_pair_err_cnt[0] <= 4'd0;
        bank_pair_err_cnt[1] <= 4'd0;
        bank_pair_err_cnt[2] <= 4'd0;
        bank_pair_err_cnt[3] <= 4'd0;
        bank_pair_err_cnt[4] <= 4'd0;
        bank_pair_err_cnt[5] <= 4'd0;
        bank_pair_err_cnt[6] <= 4'd0;
        bank_pair_err_cnt[7] <= 4'd0;
        err_block_cnt        <= 8'd0;
    end
    else if (gf_start_rise) begin
        bank_pair_err_cnt[0] <= 4'd0;
        bank_pair_err_cnt[1] <= 4'd0;
        bank_pair_err_cnt[2] <= 4'd0;
        bank_pair_err_cnt[3] <= 4'd0;
        bank_pair_err_cnt[4] <= 4'd0;
        bank_pair_err_cnt[5] <= 4'd0;
        bank_pair_err_cnt[6] <= 4'd0;
        bank_pair_err_cnt[7] <= 4'd0;
        err_block_cnt        <= 8'd0;
    end
    else begin
        bank_pair_err_cnt[0] <= count_two_banks(bank_errflag[0],  bank_errflag[1]);
        bank_pair_err_cnt[1] <= count_two_banks(bank_errflag[2],  bank_errflag[3]);
        bank_pair_err_cnt[2] <= count_two_banks(bank_errflag[4],  bank_errflag[5]);
        bank_pair_err_cnt[3] <= count_two_banks(bank_errflag[6],  bank_errflag[7]);
        bank_pair_err_cnt[4] <= count_two_banks(bank_errflag[8],  bank_errflag[9]);
        bank_pair_err_cnt[5] <= count_two_banks(bank_errflag[10], bank_errflag[11]);
        bank_pair_err_cnt[6] <= count_two_banks(bank_errflag[12], bank_errflag[13]);
        bank_pair_err_cnt[7] <= count_two_banks(bank_errflag[14], bank_errflag[15]);

        err_block_cnt <= bank_pair_err_cnt[0] + bank_pair_err_cnt[1]
                       + bank_pair_err_cnt[2] + bank_pair_err_cnt[3]
                       + bank_pair_err_cnt[4] + bank_pair_err_cnt[5]
                       + bank_pair_err_cnt[6] + bank_pair_err_cnt[7];
    end
end

endmodule
