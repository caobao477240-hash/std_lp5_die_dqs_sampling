module idd_signal_ctrl(
    input               sys_clk,
    input               rst_n,

    input               dut1_idd6_en_i,
    output  reg         dut1_idd6_done_o,

    output  reg [9:0]   dut1_idd_en,
    input               dut1_idd_done
);

    always@(posedge sys_clk or negedge rst_n)begin
        if(!rst_n)begin
            dut1_idd_en <= 10'd0;
        end
        else begin
            dut1_idd_en <= {2'b0, dut1_idd6_en_i, 6'b0, dut1_idd6_en_i};
        end
    end

    always@(posedge sys_clk or negedge rst_n)begin
         if(!rst_n)begin
            dut1_idd6_done_o  <= 0;
         end
         else begin
            if(dut1_idd6_en_i)begin
                dut1_idd6_done_o <= dut1_idd_done;
            end
            else begin
                dut1_idd6_done_o <= 0;
            end
         end
    end

endmodule
