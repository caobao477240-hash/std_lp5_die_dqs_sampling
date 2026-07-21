`timescale 1ns / 1ps

module tb_pmic_i2c_ctrl_latch;

    localparam real    P_CLK_HALF_NS = 2.5;
    localparam integer P_MAX_BYTES   = 8;

    reg                 r_clk;
    reg                 r_rst_n;
    reg                 r_send_byte_ctrl;
    reg                 r_data_bit_ctrl;
    reg                 r_wr_en;
    reg                 r_rd_en;
    reg  [15:0]         r_wr_reg_addr;
    reg  [15:0]         r_rd_reg_addr;
    reg  [15:0]         r_write_data;

    wire                w_i2c_scl;
    wire                w_i2c_sda;
    wire [15:0]         w_read_data;
    wire                w_read_data_valid;

    reg                 r_i2c_active;
    reg                 r_transaction_done;
    reg  [ 7:0]         r_rx_shift;
    reg  [ 7:0]         r_rx_bytes [0:P_MAX_BYTES-1];
    integer             r_rx_bit_cnt;
    integer             r_rx_byte_cnt;
    integer             r_fail_cnt;
    integer             r_clear_index;

    pullup (w_i2c_sda);

    // Pull SDA low only while the master releases it for an ACK cycle.
    assign w_i2c_sda = (i2c_cfg_u0.u_i2c_dri.sda_dir == 1'b0) ? 1'b0 : 1'bz;

    initial begin
        r_clk = 1'b0;
        forever #P_CLK_HALF_NS r_clk = ~r_clk;
    end

    // I2C START detector and byte monitor.
    always @(negedge w_i2c_sda) begin
        if ((w_i2c_scl === 1'b1) && (r_i2c_active == 1'b0)) begin
            r_i2c_active      = 1'b1;
            r_transaction_done = 1'b0;
            r_rx_shift        = 8'h00;
            r_rx_bit_cnt      = 0;
            r_rx_byte_cnt     = 0;
        end
    end

    always @(posedge w_i2c_scl) begin
        if (r_i2c_active == 1'b1) begin
            if (r_rx_bit_cnt < 8) begin
                r_rx_shift = {r_rx_shift[6:0], w_i2c_sda};
                if (r_rx_bit_cnt == 7)
                    r_rx_bytes[r_rx_byte_cnt] = r_rx_shift;
                r_rx_bit_cnt = r_rx_bit_cnt + 1;
            end
            else begin
                r_rx_bit_cnt  = 0;
                r_rx_byte_cnt = r_rx_byte_cnt + 1;
            end
        end
    end

    // I2C STOP detector.
    always @(posedge w_i2c_sda) begin
        if ((w_i2c_scl === 1'b1) && (r_i2c_active == 1'b1)) begin
            r_i2c_active       = 1'b0;
            r_transaction_done = 1'b1;
        end
    end

    task clear_monitor;
        begin
            r_i2c_active       = 1'b0;
            r_transaction_done = 1'b0;
            r_rx_shift         = 8'h00;
            r_rx_bit_cnt       = 0;
            r_rx_byte_cnt      = 0;
            for (r_clear_index = 0; r_clear_index < P_MAX_BYTES; r_clear_index = r_clear_index + 1)
                r_rx_bytes[r_clear_index] = 8'h00;
        end
    endtask

    task wait_i2c_idle;
        begin
            wait (
                (i2c_cfg_u0.i2c_en_i == 1'b0) &&
                (i2c_cfg_u0.u_i2c_dri.cur_state == 16'h0001) &&
                (i2c_cfg_u0.u_i2c_dri.i2c_done == 1'b0)
            );
            repeat (4) @(posedge r_clk);
        end
    endtask

    task pulse_write;
        input [15:0] i_reg_addr;
        input [15:0] i_write_data;
        input        i_send_byte_ctrl;
        input        i_data_bit_ctrl;
        begin
            @(negedge r_clk);
            r_wr_reg_addr    = i_reg_addr;
            r_write_data     = i_write_data;
            r_send_byte_ctrl = i_send_byte_ctrl;
            r_data_bit_ctrl  = i_data_bit_ctrl;
            r_wr_en          = 1'b1;

            @(negedge r_clk);
            r_wr_en          = 1'b0;
            r_send_byte_ctrl = 1'b0;
            r_data_bit_ctrl  = 1'b0;
            r_wr_reg_addr    = 16'h0000;
            r_write_data     = 16'h0000;
        end
    endtask

    task check_byte;
        input integer i_byte_index;
        input [ 7:0]  i_expected;
        begin
            if (r_rx_bytes[i_byte_index] !== i_expected) begin
                $display(
                    "ERROR byte[%0d]: expected=%02X actual=%02X",
                    i_byte_index,
                    i_expected,
                    r_rx_bytes[i_byte_index]
                );
                r_fail_cnt = r_fail_cnt + 1;
            end
        end
    endtask

    i2c_cfg #(
        .IIC_BIT_CTRL (1'b0),
        .CLK_FREQ     (32'd200_000_000)
    ) i2c_cfg_u0 (
        .clk                  (r_clk            ),
        .rst_n                (r_rst_n          ),
        .send_byte_ctrl       (r_send_byte_ctrl ),
        .data_bit_ctrl        (r_data_bit_ctrl  ),
        .IRSP_IIC_DEVICE_ADDR (7'h43            ),
        .scl_o                (w_i2c_scl        ),
        .sda_io               (w_i2c_sda        ),
        .wr_en_i              (r_wr_en          ),
        .rd_en_i              (r_rd_en          ),
        .wr_reg_addr_i        (r_wr_reg_addr    ),
        .rd_reg_addr_i        (r_rd_reg_addr    ),
        .data_in_i            (r_write_data     ),
        .data_out_o           (w_read_data      ),
        .data_out_valid       (w_read_data_valid)
    );

    initial begin
        r_rst_n          = 1'b0;
        r_send_byte_ctrl = 1'b0;
        r_data_bit_ctrl  = 1'b0;
        r_wr_en          = 1'b0;
        r_rd_en          = 1'b0;
        r_wr_reg_addr    = 16'h0000;
        r_rd_reg_addr    = 16'h0000;
        r_write_data     = 16'h0000;
        r_fail_cnt       = 0;
        clear_monitor();

        repeat (10) @(posedge r_clk);
        r_rst_n = 1'b1;
        repeat (10) @(posedge r_clk);

        // PMBus Write Word: address byte, command, low data, high data.
        clear_monitor();
        pulse_write(16'h0021, 16'h00B4, 1'b0, 1'b1);
        wait (r_transaction_done == 1'b1);
        #1;
        $display(
            "WORD bytes=%0d data=%02X %02X %02X %02X",
            r_rx_byte_cnt,
            r_rx_bytes[0],
            r_rx_bytes[1],
            r_rx_bytes[2],
            r_rx_bytes[3]
        );
        if (r_rx_byte_cnt != 4) begin
            $display("ERROR Write Word byte count: expected=4 actual=%0d", r_rx_byte_cnt);
            r_fail_cnt = r_fail_cnt + 1;
        end
        check_byte(0, 8'h86);
        check_byte(1, 8'h21);
        check_byte(2, 8'hB4);
        check_byte(3, 8'h00);

        wait_i2c_idle();

        // PMBus Write Byte: PAGE=3 must remain a three-byte transaction.
        clear_monitor();
        pulse_write(16'h0000, 16'h0003, 1'b0, 1'b0);
        wait (r_transaction_done == 1'b1);
        #1;
        $display(
            "BYTE bytes=%0d data=%02X %02X %02X",
            r_rx_byte_cnt,
            r_rx_bytes[0],
            r_rx_bytes[1],
            r_rx_bytes[2]
        );
        if (r_rx_byte_cnt != 3) begin
            $display("ERROR Write Byte byte count: expected=3 actual=%0d", r_rx_byte_cnt);
            r_fail_cnt = r_fail_cnt + 1;
        end
        check_byte(0, 8'h86);
        check_byte(1, 8'h00);
        check_byte(2, 8'h03);

        wait_i2c_idle();

        // PMBus Send Byte: CLEAR_FAULTS has no following data byte.
        clear_monitor();
        pulse_write(16'h0003, 16'h0000, 1'b1, 1'b0);
        wait (r_transaction_done == 1'b1);
        #1;
        $display(
            "SEND bytes=%0d data=%02X %02X",
            r_rx_byte_cnt,
            r_rx_bytes[0],
            r_rx_bytes[1]
        );
        if (r_rx_byte_cnt != 2) begin
            $display("ERROR Send Byte byte count: expected=2 actual=%0d", r_rx_byte_cnt);
            r_fail_cnt = r_fail_cnt + 1;
        end
        check_byte(0, 8'h86);
        check_byte(1, 8'h03);

        if (r_fail_cnt == 0)
            $display("SIM PASS: PMIC I2C transaction controls remain latched.");
        else begin
            $display("SIM FAIL: fail_count=%0d", r_fail_cnt);
            $fatal(1);
        end

        $finish;
    end

    initial begin
        #2_000_000;
        $display("SIM FAIL: timeout");
        $fatal(1);
    end

endmodule
