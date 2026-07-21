`timescale 1ns / 1ps

// Behavioral replacement for the UART TX FIFO IP in simulation only.
// It keeps the uart_ctrl/protocol_ctrl path intact without compiling the
// generated FIFO output products.
module fifo_generator_uart (
    input             rst,
    input             wr_clk,
    input             rd_clk,
    input      [7:0]  din,
    input             wr_en,
    input             rd_en,
    output reg [7:0]  dout,
    output            full,
    output            almost_full,
    output            empty,
    output            almost_empty,
    output            wr_rst_busy,
    output            rd_rst_busy,
    input      [16:0] prog_full_thresh,
    output            prog_full
);

    localparam DEPTH = 1024;

    reg [7:0] mem [0:DEPTH-1];
    reg [9:0] wr_ptr;
    reg [9:0] rd_ptr;
    reg [10:0] used_cnt;

    assign full         = (used_cnt == DEPTH);
    assign almost_full  = (used_cnt >= DEPTH - 4);
    assign empty        = (used_cnt == 0);
    assign almost_empty = (used_cnt <= 1);
    assign prog_full    = (used_cnt >= prog_full_thresh[10:0]);
    assign wr_rst_busy  = rst;
    assign rd_rst_busy  = rst;

    always @(posedge wr_clk) begin
        if (rst) begin
            wr_ptr   <= 10'd0;
            rd_ptr   <= 10'd0;
            used_cnt <= 11'd0;
            dout     <= 8'd0;
        end
        else begin
            case ({wr_en && !full, rd_en && !empty})
                2'b10: begin
                    mem[wr_ptr] <= din;
                    wr_ptr      <= wr_ptr + 10'd1;
                    used_cnt    <= used_cnt + 11'd1;
                    if (empty)
                        dout <= din;
                end
                2'b01: begin
                    if (used_cnt > 11'd1)
                        dout <= mem[rd_ptr + 10'd1];
                    rd_ptr   <= rd_ptr + 10'd1;
                    used_cnt <= used_cnt - 11'd1;
                end
                2'b11: begin
                    mem[wr_ptr] <= din;
                    wr_ptr      <= wr_ptr + 10'd1;
                    if (used_cnt > 11'd1)
                        dout <= mem[rd_ptr + 10'd1];
                    else
                        dout <= din;
                    rd_ptr      <= rd_ptr + 10'd1;
                end
                default: begin
                    dout <= dout;
                end
            endcase
        end
    end

endmodule
