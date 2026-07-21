`timescale 1ns / 1ps

module tb_uart_full_test_cmd;

    localparam real    CLK_HALF_NS = 2.5;     // 200 MHz
    localparam real    SERDES_HALF_NS = 1.25; // 400 MHz
    localparam real    UART_BIT_NS = 1666.667;// 600000 baud
    localparam integer FRAME_LEN   = 22;
    localparam integer MAX_RSP     = 256;

    reg         clk;
    reg         clk_serdes;
    reg         clk_serdes_wck;
    reg         rst_n;
    reg         uart_rx;
    wire        uart_tx;

    wire        proto_sir_sel;
    wire [15:0] proto_sir_addr;
    wire        proto_sir_read;
    wire [95:0] proto_sir_wdat;
    wire [95:0] proto_sir_rdat;
    wire        proto_sir_dack;

    wire        lp5_init_start;
    wire        lp5_init_done;
    wire        lp5_gf_start;
    wire        lp5_gf_done;
    wire [95:0] lp5_gf_result;
    wire [63:0] lp5_gf_err_block_msg;
    wire [7:0]  lp5_gf_err_block_cnt;
    wire        lp5_idd6_start;
    wire        lp5_idd6_done;
    wire [9:0]  idd_en;
    wire        idd_done;
    wire [7:0]  lp5_mr8_density;
    wire [143:0] lp5_dq_delay_flat;
    wire [23:0] mrw_r;
    wire [7:0]  read_capture_start_cnt;
    wire [2:0]  gf_refresh_batch_num;
    wire [1:0]  gf_pattern_mode_cfg;

    wire        ad5272_2_entry;
    wire [1:0]  ad5272_2_read_addr;
    wire [1:0]  ad5272_2_write_addr;
    wire [3:0]  ad5272_2_write_cmd;
    wire [9:0]  ad5272_2_write_data;
    wire [63:0] irsp_u67_value;
    wire [63:0] irsp_u68_value;
    wire        irsp_u67_send_byte_ctrl;
    wire        irsp_u67_data_bit_ctrl;
    wire        irsp_u68_send_byte_ctrl;
    wire        irsp_u68_data_bit_ctrl;
    wire [6:0]  irsp_iic_device_addr;
    wire [63:0] eeprom_value;
    wire        eeprom_send_byte_ctrl;
    wire        eeprom_data_bit_ctrl;
    wire        os_start;
    wire [15:0] vdd2l_uth;
    wire [15:0] vddq_uth;
    wire [15:0] vdd2h_uth;
    wire [15:0] vdd1_uth;
    wire [15:0] adc_ch5_uth;
    wire [15:0] adc_ch6_uth;
    wire [15:0] adc_ch7_uth;
    wire [15:0] adc_ch8_uth;

    wire        reset_n_a;
    wire        ck_t_a;
    wire        ck_c_a;
    wire        cs0_a;
    wire [6:0]  ca_a;
    wire [15:0] dq_a;
    wire [1:0]  wck_t_a;
    wire [1:0]  wck_c_a;
    wire [1:0]  rdqs_t_a;
    wire [1:0]  rdqs_c_a;
    wire [1:0]  dmi_a;

    wire        g3vm_k1;
    wire        g3vm_k3;
    wire        g3vm_k5;
    wire        g3vm_k7;
    wire        g3vm_k15;
    wire        g3vm_k16;
    wire        adc_mi_pm1_sa_sla0;
    wire        adc_mi_pm1_sc_sla0;
    wire        adc_mi_pm2_sc_sla0;
    wire        adc_mi_pm2_sc_sla1;
    wire        adc_mp2c_fh2_sla2;
    wire        adc_mi_fh1_sla0;
    wire        adc_mi_fh1_sla1;
    wire        fh1_h_key;
    wire        fh1_l_key;
    wire        fh2_h_key;
    wire        fh2_l_key;
    wire        adc_mh_sla2;
    wire        adc_mh_sla1;
    wire        adc_mh_sla0;
    wire        en_vpp_dut;
    wire        rst_signal;
    wire        rst_12v_signal;

    reg [15:0] x_ch1;
    reg [15:0] x_ch2;
    reg [15:0] x_ch3;
    reg [15:0] x_ch4;

    reg [7:0] tx_frame [0:FRAME_LEN-1];
    reg [7:0] rx_frame [0:MAX_RSP-1];
    reg [7:0] current_cmd_id;
    reg [8*32-1:0] current_cmd_name;
    integer rx_count;

    assign dq_a     = 16'hzzzz;
    assign rdqs_t_a = 2'bzz;
    assign rdqs_c_a = 2'bzz;
    assign dmi_a    = 2'bzz;

    initial begin
        clk = 1'b0;
        forever #CLK_HALF_NS clk = ~clk;
    end

    initial begin
        clk_serdes = 1'b0;
        forever #SERDES_HALF_NS clk_serdes = ~clk_serdes;
    end

    initial begin
        clk_serdes_wck = 1'b0;
        #(SERDES_HALF_NS / 2.0);
        forever #SERDES_HALF_NS clk_serdes_wck = ~clk_serdes_wck;
    end

    uart_top #(
        .BPS_SEL        (32'd600000),
        .FIFO_PROG_FULL (17'd900)
    ) u_uart_top (
        .clk      (clk),
        .rst_n    (rst_n),
        .uart_rx  (uart_rx),
        .uart_tx  (uart_tx),
        .sir_sel  (proto_sir_sel),
        .sir_addr (proto_sir_addr),
        .sir_read (proto_sir_read),
        .sir_wdat (proto_sir_wdat),
        .sir_rdat (proto_sir_rdat),
        .sir_dack (proto_sir_dack)
    );

    bar u_bar (
        .clk                       (clk),
        .rst_n                     (rst_n),
        .sir_sel                   (proto_sir_sel),
        .sir_addr                  (proto_sir_addr),
        .sir_read                  (proto_sir_read),
        .sir_wdat                  (proto_sir_wdat),
        .sir_rdat                  (proto_sir_rdat),
        .sir_dack                  (proto_sir_dack),
        .ad5272_2_entry            (ad5272_2_entry),
        .ad5272_2_read_addr        (ad5272_2_read_addr),
        .ad5272_2_read_data        (10'h000),
        .ad5272_2_write_addr       (ad5272_2_write_addr),
        .ad5272_2_write_cmd        (ad5272_2_write_cmd),
        .ad5272_2_write_data       (ad5272_2_write_data),
        .irsp_u67_value            (irsp_u67_value),
        .irsp_u67_send_byte_ctrl   (irsp_u67_send_byte_ctrl),
        .irsp_u67_data_bit_ctrl    (irsp_u67_data_bit_ctrl),
        .irsp_u67_data_out         (16'h0000),
        .irsp_u68_value            (irsp_u68_value),
        .irsp_u68_send_byte_ctrl   (irsp_u68_send_byte_ctrl),
        .irsp_u68_data_bit_ctrl    (irsp_u68_data_bit_ctrl),
        .irsp_u68_data_out         (16'h0000),
        .irsp_iic_device_addr      (irsp_iic_device_addr),
        .eeprom_value              (eeprom_value),
        .eeprom_send_byte_ctrl     (eeprom_send_byte_ctrl),
        .eeprom_data_bit_ctrl      (eeprom_data_bit_ctrl),
        .eeprom_data_out           (16'h0000),
        .dut_init_start            (lp5_init_start),
        .dut_init_done             (lp5_init_done),
        .dut_mr8_density           (lp5_mr8_density),
        .dut_idd6_start            (lp5_idd6_start),
        .dut_idd6_done             (lp5_idd6_done),
        .dut_idd6_result           ({x_ch4, x_ch3, x_ch2, x_ch1}),
        .gf_start                  (lp5_gf_start),
        .gf_done                   (lp5_gf_done),
        .gf_result                 (lp5_gf_result),
        .gf_bad_block_info         ({32'h0, lp5_gf_err_block_msg}),
        .gf_bad_block_count        (lp5_gf_err_block_cnt),
        .gf_clk_sel                (),
        .gf_addr_start             (),
        .gf_addr_end               (),
        .dut_dq_delay_flat         (lp5_dq_delay_flat),
        .mrw_r                     (mrw_r),
        .read_capture_start_cnt    (read_capture_start_cnt),
        .gf_refresh_batch_num      (gf_refresh_batch_num),
        .gf_pattern_mode_cfg       (gf_pattern_mode_cfg),
        .os_start                  (os_start),
        .os_done                   (1'b0),
        .os_result                 (32'h0),
        .vdd2l_uth                 (vdd2l_uth),
        .vddq_uth                  (vddq_uth),
        .vdd2h_uth                 (vdd2h_uth),
        .vdd1_uth                  (vdd1_uth),
        .adc_ch5_uth               (adc_ch5_uth),
        .adc_ch6_uth               (adc_ch6_uth),
        .adc_ch7_uth               (adc_ch7_uth),
        .adc_ch8_uth               (adc_ch8_uth),
        .g3vm_k1                   (g3vm_k1),
        .g3vm_k3                   (g3vm_k3),
        .g3vm_k5                   (g3vm_k5),
        .g3vm_k7                   (g3vm_k7),
        .g3vm_k15                  (g3vm_k15),
        .g3vm_k16                  (g3vm_k16),
        .adc_mi_pm1_sa_sla0        (adc_mi_pm1_sa_sla0),
        .adc_mi_pm1_sc_sla0        (adc_mi_pm1_sc_sla0),
        .adc_mi_pm2_sc_sla0        (adc_mi_pm2_sc_sla0),
        .adc_mi_pm2_sc_sla1        (adc_mi_pm2_sc_sla1),
        .adc_mp2c_fh2_sla2         (adc_mp2c_fh2_sla2),
        .adc_mi_fh1_sla0           (adc_mi_fh1_sla0),
        .adc_mi_fh1_sla1           (adc_mi_fh1_sla1),
        .fh1_h_key                 (fh1_h_key),
        .fh1_l_key                 (fh1_l_key),
        .fh2_h_key                 (fh2_h_key),
        .fh2_l_key                 (fh2_l_key),
        .adc_mh_sla2               (adc_mh_sla2),
        .adc_mh_sla1               (adc_mh_sla1),
        .adc_mh_sla0               (adc_mh_sla0),
        .en_vpp_dut                (en_vpp_dut),
        .rst_signal                (rst_signal),
        .rst_12v_signal            (rst_12v_signal)
    );

    idd_signal_ctrl u_idd_signal_ctrl (
        .sys_clk          (clk),
        .rst_n            (rst_n),
        .dut1_idd6_en_i   (lp5_idd6_start),
        .dut1_idd6_done_o (lp5_idd6_done),
        .dut1_idd_en      (idd_en),
        .dut1_idd_done    (idd_done)
    );

    lpddr5_dut1 u_lpddr5_dut1 (
        .i_clk_core_200m     (clk),
        .i_clk_dq_tx_400m    (clk_serdes),
        .i_clk_ca_wck_400m   (clk_serdes_wck),
        .i_clk_dq_rx_400m    (clk_serdes),
        .i_serdes_reset_n    (rst_n),
        .rst_n_in            (rst_n),
        .GF_total_en         (lp5_gf_start),
        .GF_total_done       (lp5_gf_done),
        .GF_result_data      (lp5_gf_result),
        .GF_fail_aux_result  (),
        .reset_n_a           (reset_n_a),
        .ck_t_a              (ck_t_a),
        .ck_c_a              (ck_c_a),
        .cs0_a               (cs0_a),
        .ca_a                (ca_a),
        .dq_a                (dq_a),
        .wck_t_a             (wck_t_a),
        .wck_c_a             (wck_c_a),
        .rdqs_t_a            (rdqs_t_a),
        .rdqs_c_a            (rdqs_c_a),
        .dmi_a               (dmi_a),
        .init_en             (lp5_init_start),
        .init_done           (lp5_init_done),
        .mrw_r               (mrw_r),
        .idd_en              (idd_en),
        .idd_done            (idd_done),
        .read_capture_start_cnt (read_capture_start_cnt),
        .gf_act_cmd_gap_cnt  (10'd16),
        .gf_rd_cmd_gap_cnt   (10'd12),
        .gf_wr_cmd_gap_cnt   (10'd10),
        .gf_pre_cmd_gap_cnt  (10'd16),
        .gf_refresh_batch_num (gf_refresh_batch_num),
        .gf_pattern_mode_cfg  (gf_pattern_mode_cfg),
        .die_message         (lp5_mr8_density),
        .err_block_cnt       (lp5_gf_err_block_cnt),
        .err_block_message   (lp5_gf_err_block_msg),
        .RDY                 (1'b1),
        .delay_value_dq_a    (lp5_dq_delay_flat)
    );

    initial begin
        x_ch1 = 16'h01FE;
        x_ch2 = 16'h0264;
        x_ch3 = 16'h0011;
        x_ch4 = 16'h0000;
        forever begin
            @(posedge idd_en[0]);
            #2000;
            x_ch1 = x_ch1 + 16'h0001;
            x_ch2 = x_ch2 + 16'h0002;
            x_ch3 = x_ch3 + 16'h0001;
        end
    end

    initial begin
        rst_n = 1'b0;
        uart_rx = 1'b1;
        current_cmd_id = 8'd0;
        current_cmd_name = "RESET";
        rx_count = 0;

        #200;
        rst_n = 1'b1;
        #2000;

        shorten_gf_range();

        run_full_command_flow();

        #200000;
        $display("[%0t] SIM PASS: UART command flow completed", $time);
        $finish;
    end

    task shorten_gf_range;
        begin
            wait (rst_n);
            #100;
            force u_lpddr5_dut1.U_lpddr5_gf.gf_start_col_bus = {8{6'h00}};
            force u_lpddr5_dut1.U_lpddr5_gf.gf_end_col_bus   = {8{6'h03}};
            force u_lpddr5_dut1.U_lpddr5_gf.gf_start_row_bus = {8{18'h00000}};
            force u_lpddr5_dut1.U_lpddr5_gf.gf_end_row_bus   = {8{18'h00001}};
            $display("[%0t] GF range forced for simulation: rows 0..1, cols 0..3", $time);
        end
    endtask

    task run_full_command_flow;
        begin
            send_named_frame(8'd1,  "read_version",        16'h0000, 8'h66, 12'h000);
            send_named_frame(8'd2,  "ad5272_1",            16'h0308, 8'h77, 96'h000000000000000010001c03);
            send_named_frame(8'd3,  "ad5272_2",            16'h0308, 8'h77, 96'h000000000000000010000566);
            send_named_frame(8'd5,  "open_g3vm_for_init",  16'h0318, 8'h77, 96'h00000000001b028d02480000);

            send_named_frame(8'd6,  "init_start",          16'h0404, 8'h77, 96'h00000000000000000000ffff);
            wait_init_done();
            send_named_frame(8'd7,  "init_read",           16'h0408, 8'h66, 96'h0);

            send_named_frame(8'd8,  "idd6_start",          16'h040c, 8'h77, 96'h00000000000000000000ffff);
            wait_idd6_done();
            send_named_frame(8'd9,  "idd6_read",           16'h0410, 8'h66, 96'h00000000000000000000ffff);

            send_named_frame(8'd10, "gf_start",            16'h0500, 8'h77, 96'h00000000000000000000ffff);
            wait_gf_done();
            send_named_frame(8'd11, "gf_read",             16'h0504, 8'h66, 96'h00000000000000000000ffff);
        end
    endtask

    task send_named_frame;
        input [7:0]       cmd_id;
        input [8*32-1:0]  cmd_name;
        input [15:0]      addr;
        input [7:0]       op;
        input [95:0]      payload;
        integer i;
        reg [7:0] sum;
        begin
            current_cmd_id   = cmd_id;
            current_cmd_name = cmd_name;

            tx_frame[0]  = 8'haa;
            tx_frame[1]  = 8'h55;
            tx_frame[2]  = 8'h01;
            tx_frame[3]  = op;
            tx_frame[4]  = addr[7:0];
            tx_frame[5]  = addr[15:8];
            for (i = 0; i < 12; i = i + 1)
                tx_frame[6 + i] = payload[i * 8 +: 8];

            sum = 8'h00;
            for (i = 2; i < 18; i = i + 1) begin
                sum = sum + tx_frame[i];
            end

            tx_frame[18] = sum;
            tx_frame[19] = 8'h00;
            tx_frame[20] = 8'h55;
            tx_frame[21] = 8'haa;

            $write("[%0t] TX %-20s:", $time, cmd_name);
            for (i = 0; i < FRAME_LEN; i = i + 1)
                $write(" %02x", tx_frame[i]);
            $write("\n");

            fork
                begin
                    capture_uart_response(cmd_name);
                end
                begin
                    send_uart_frame();
                end
            join
            #20000;
        end
    endtask

    task send_uart_frame;
        integer i;
        begin
            for (i = 0; i < FRAME_LEN; i = i + 1)
                send_uart_byte(tx_frame[i]);
            $display("[%0t] TX serial complete, rx_state=%0d sir_sel=%b sir_addr=%04h",
                     $time,
                     u_uart_top.protocol_ctrl_u0.rx_state_c,
                     proto_sir_sel,
                     proto_sir_addr);
        end
    endtask

    task send_uart_byte;
        input [7:0] data;
        integer bit_idx;
        begin
            uart_rx = 1'b0;
            #(UART_BIT_NS);
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                uart_rx = data[bit_idx];
                #(UART_BIT_NS);
            end
            uart_rx = 1'b1;
            #(UART_BIT_NS);
        end
    endtask

    task capture_uart_response;
        input [8*32-1:0] cmd_name;
        integer i;
        reg [7:0] b;
        begin
            rx_count = 0;
            for (i = 0; i < FRAME_LEN; i = i + 1) begin
                recv_uart_byte(b);
                rx_frame[i] = b;
                rx_count = i + 1;
            end
            $write("[%0t] RX %-20s:", $time, cmd_name);
            for (i = 0; i < FRAME_LEN; i = i + 1)
                $write(" %02x", rx_frame[i]);
            $write("\n");
        end
    endtask

    task recv_uart_byte;
        output [7:0] data;
        integer bit_idx;
        integer timeout_cycles;
        begin
            timeout_cycles = 0;
            while ((uart_tx !== 1'b0) && (timeout_cycles < 200000)) begin
                @(posedge clk);
                timeout_cycles = timeout_cycles + 1;
            end
            if (uart_tx !== 1'b0) begin
                $display("[%0t] ERROR: timeout waiting UART TX start, cmd=%s rx_state=%0d tx_state=%0d sir_sel=%b sir_dack=%b sir_addr=%04h",
                         $time,
                         current_cmd_name,
                         u_uart_top.protocol_ctrl_u0.rx_state_c,
                         u_uart_top.protocol_ctrl_u0.tx_state_c,
                         proto_sir_sel,
                         proto_sir_dack,
                         proto_sir_addr);
                $finish;
            end
            #(UART_BIT_NS + (UART_BIT_NS / 2.0));
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                data[bit_idx] = uart_tx;
                #(UART_BIT_NS);
            end
            #(UART_BIT_NS / 2.0);
        end
    endtask

    task wait_init_done;
        integer k;
        begin
            k = 0;
            while ((u_bar.u_bar04.init_finish !== 8'hc9) && (k < 200000)) begin
                @(posedge clk);
                k = k + 1;
            end
            if (u_bar.u_bar04.init_finish !== 8'hc9) begin
                $display("[%0t] ERROR: timeout waiting for BAR04 init_finish=C9, init_start=%b init_done=%b init_state=%0d init_busy=%b",
                         $time,
                         lp5_init_start,
                         lp5_init_done,
                         u_lpddr5_dut1.U_lpddr5_test_scheduler.init_state,
                         u_lpddr5_dut1.U_lpddr5_test_scheduler.init_busy);
                $finish;
            end
            $display("[%0t] BAR04 init_finish=C9 after %0d cycles", $time, k);
        end
    endtask

    task wait_idd6_done;
        integer k;
        begin
            k = 0;
            while ((u_bar.u_bar04.idd6_finish !== 8'hc9) && (k < 200000)) begin
                @(posedge clk);
                k = k + 1;
            end
            if (u_bar.u_bar04.idd6_finish !== 8'hc9) begin
                $display("[%0t] ERROR: timeout waiting for BAR04 idd6_finish=C9, idd6_start=%b idd_done=%b idd_state=%0d idd_busy=%b",
                         $time,
                         lp5_idd6_start,
                         idd_done,
                         u_lpddr5_dut1.U_lpddr5_test_scheduler.idd_state,
                         u_lpddr5_dut1.U_lpddr5_test_scheduler.idd_busy);
                $finish;
            end
            $display("[%0t] BAR04 idd6_finish=C9 after %0d cycles", $time, k);
        end
    endtask

    task wait_gf_done;
        integer k;
        begin
            k = 0;
            while (!((u_bar.u_bar05.gf_result_reg[7:0] == 8'hc9) ||
                     (u_bar.u_bar05.gf_result_reg[7:0] == 8'h9c)) &&
                   (k < 4000000)) begin
                @(posedge clk);
                k = k + 1;
            end
            if (!((u_bar.u_bar05.gf_result_reg[7:0] == 8'hc9) ||
                  (u_bar.u_bar05.gf_result_reg[7:0] == 8'h9c))) begin
                $display("[%0t] ERROR: timeout waiting for BAR05 GF result, gf_start=%b gf_done=%b gf_state=%h gf_row=%0d gf_col=%0d err_cnt=%0d",
                         $time,
                         lp5_gf_start,
                         lp5_gf_done,
                         u_lpddr5_dut1.U_lpddr5_test_scheduler.gf_engine_state,
                         u_lpddr5_dut1.U_lpddr5_test_scheduler.gf_engine_cnt_row,
                         u_lpddr5_dut1.U_lpddr5_test_scheduler.gf_engine_cnt_col,
                         u_lpddr5_dut1.U_lpddr5_test_scheduler.gf_error_count);
                $finish;
            end
            $display("[%0t] BAR05 GF result=%02x after %0d cycles",
                     $time,
                     u_bar.u_bar05.gf_result_reg[7:0],
                     k);
        end
    endtask

endmodule
