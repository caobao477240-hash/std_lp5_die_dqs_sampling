`include "dram_driver_head.vh"

/**
 * bar03
 * Peripheral control register block.
 * Manages AD5272 digital rheostat, IRSP/U67/U68 IIC interfaces,
 * EEPROM interface, and various relay/power control signals.
 */
module bar03 (
    input  wire                 clk                       ,
    input  wire                 rst_n                     ,
    input  wire [  7:0]         sir_addr                  ,
    input  wire                 sir_read                  ,
    input  wire [ 95:0]         sir_wdat                  ,
    input  wire                 sir_sel                   ,
    output wire                 sir_dack                  ,
    output wire [ 95:0]         sir_rdat                  ,

    // AD5272 digital rheostat
    output reg                  ad5272_2_entry            ,
    output reg  [  1:0]         ad5272_2_read_addr        ,
    input  wire [  9:0]         ad5272_2_read_data        ,
    output reg  [  1:0]         ad5272_2_write_addr       ,
    output reg  [  3:0]         ad5272_2_write_cmd        ,
    output reg  [  9:0]         ad5272_2_write_data       ,

    // IRSP U67 / U68 IIC interfaces
    output reg  [ 63:0]         irsp_u67_value            ,
    output reg                  irsp_u67_send_byte_ctrl   ,
    output reg                  irsp_u67_data_bit_ctrl    ,
    input  wire [ 15:0]         irsp_u67_data_out         ,
    output reg  [ 63:0]         irsp_u68_value            ,
    output reg                  irsp_u68_send_byte_ctrl   ,
    output reg                  irsp_u68_data_bit_ctrl    ,
    input  wire [ 15:0]         irsp_u68_data_out         ,
    output reg  [  6:0]         irsp_iic_device_addr      ,

    // EEPROM interface
    output reg  [ 63:0]         eeprom_value              ,
    output reg                  eeprom_send_byte_ctrl     ,
    output reg                  eeprom_data_bit_ctrl      ,
    input  wire [ 15:0]         eeprom_data_out           ,

    // Relay and power control
    output reg                  g3vm_k1                   ,
    output reg                  g3vm_k3                   ,
    output reg                  g3vm_k5                   ,
    output reg                  g3vm_k7                   ,
    output reg                  g3vm_k15                  ,
    output reg                  g3vm_k16                  ,
    output reg                  adc_mi_pm1_sa_sla0        ,
    output reg                  adc_mi_pm1_sc_sla0        ,
    output reg                  adc_mi_pm2_sc_sla0        ,
    output reg                  adc_mi_pm2_sc_sla1        ,
    output reg                  adc_mp2c_fh2_sla2         ,
    output reg                  adc_mi_fh1_sla0           ,
    output reg                  adc_mi_fh1_sla1           ,
    output reg                  fh1_h_key                 ,
    output reg                  fh1_l_key                 ,
    output reg                  fh2_h_key                 ,
    output reg                  fh2_l_key                 ,
    output reg                  adc_mh_sla2               ,
    output reg                  adc_mh_sla1               ,
    output reg                  adc_mh_sla0               ,
    output reg                  en_vpp_dut                ,
    output reg                  rst_signal                ,
    output reg                  rst_12v_signal
);

    // --------------------------------------------------------
    // BAR03 request decode
    // --------------------------------------------------------
    wire write_cycle;
    wire write_irsp_u68;
    wire write_iic_device_addr;
    wire write_ad5272;
    wire write_eeprom;
    wire write_relay;
    wire write_reset;
    wire write_irsp_u67;

    assign write_cycle           = sir_sel && !sir_read;
    assign write_irsp_u68        = write_cycle && (sir_addr == `bar03_IRSP_U68_CTRL);
    assign write_iic_device_addr = write_cycle && (sir_addr == `bar03_IIC_DEVICE_ADDR);
    assign write_ad5272          = write_cycle && (sir_addr == `bar03_AD5272_CTRL);
    assign write_eeprom          = write_cycle && (sir_addr == `bar03_EEPROM_CTRL);
    assign write_relay           = write_cycle && (sir_addr == `bar03_RELAY_CTRL);
    assign write_reset           = write_cycle && (sir_addr == `bar03_RESET_CTRL);
    assign write_irsp_u67        = write_cycle && (sir_addr == `bar03_IRSP_U67_CTRL);

    reg [95:0] ad5272_reg;
    reg [95:0] sir_rdat_next;

    // --------------------------------------------------------
    // AD5272 command pulse register
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ad5272_reg <= 96'd0;
        end
        else if (write_ad5272) begin
            ad5272_reg <= sir_wdat;
        end
        else begin
            ad5272_reg <= 96'd0;
        end
    end

    // --------------------------------------------------------
    // AD5272 command output mapping
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ad5272_2_entry      <= 1'b0;
            ad5272_2_read_addr  <= 2'd0;
            ad5272_2_write_addr <= 2'd0;
            ad5272_2_write_cmd  <= 4'd0;
            ad5272_2_write_data <= 10'd0;
        end
        else begin
            ad5272_2_entry      <= ad5272_reg[28];
            ad5272_2_read_addr  <= ad5272_reg[27:26];
            ad5272_2_write_addr <= ad5272_reg[15:14];
            ad5272_2_write_cmd  <= ad5272_reg[13:10];
            ad5272_2_write_data <= ad5272_reg[9:0];
        end
    end

    // --------------------------------------------------------
    // PMIC / IRSP U68 command pulse register
    //
    // Preserve the legacy behavior:
    // - load on a U68 write;
    // - hold during another BAR03 write cycle;
    // - clear when there is no BAR03 write cycle.
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            irsp_u68_value          <= 64'd0;
            irsp_u68_data_bit_ctrl  <= 1'b0;
            irsp_u68_send_byte_ctrl <= 1'b0;
        end
        else if (write_irsp_u68) begin
            irsp_u68_value          <= sir_wdat[63:0];
            irsp_u68_data_bit_ctrl  <= sir_wdat[80];
            irsp_u68_send_byte_ctrl <= sir_wdat[88];
        end
        else if (!write_cycle) begin
            irsp_u68_value          <= 64'd0;
            irsp_u68_data_bit_ctrl  <= 1'b0;
            irsp_u68_send_byte_ctrl <= 1'b0;
        end
    end

    // --------------------------------------------------------
    // PMIC / IRSP U67 command pulse register
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            irsp_u67_value          <= 64'd0;
            irsp_u67_data_bit_ctrl  <= 1'b0;
            irsp_u67_send_byte_ctrl <= 1'b0;
        end
        else if (write_irsp_u67) begin
            irsp_u67_value          <= sir_wdat[63:0];
            irsp_u67_data_bit_ctrl  <= sir_wdat[80];
            irsp_u67_send_byte_ctrl <= sir_wdat[88];
        end
        else if (!write_cycle) begin
            irsp_u67_value          <= 64'd0;
            irsp_u67_data_bit_ctrl  <= 1'b0;
            irsp_u67_send_byte_ctrl <= 1'b0;
        end
    end

    // --------------------------------------------------------
    // PMIC / IRSP IIC device address register
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            irsp_iic_device_addr <= 7'h43;
        else if (write_iic_device_addr)
            irsp_iic_device_addr <= sir_wdat[6:0];
    end

    // --------------------------------------------------------
    // EEPROM command pulse register
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            eeprom_value          <= 64'd0;
            eeprom_data_bit_ctrl  <= 1'b1;
            eeprom_send_byte_ctrl <= 1'b0;
        end
        else if (write_eeprom) begin
            eeprom_value          <= sir_wdat[63:0];
            eeprom_data_bit_ctrl  <= 1'b1;
            eeprom_send_byte_ctrl <= 1'b0;
        end
        else begin
            eeprom_value          <= 64'd0;
            eeprom_data_bit_ctrl  <= 1'b1;
            eeprom_send_byte_ctrl <= 1'b0;
        end
    end

    // --------------------------------------------------------
    // Relay and power switch register
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            g3vm_k1              <= 1'b1;
            g3vm_k3              <= 1'b1;
            g3vm_k5              <= 1'b1;
            g3vm_k7              <= 1'b1;
            g3vm_k15             <= 1'b1;
            g3vm_k16             <= 1'b1;
            en_vpp_dut           <= 1'b0;
            adc_mi_pm1_sa_sla0   <= 1'b0;
            adc_mi_pm1_sc_sla0   <= 1'b0;
            adc_mi_pm2_sc_sla0   <= 1'b0;
            adc_mi_pm2_sc_sla1   <= 1'b1;
            adc_mp2c_fh2_sla2    <= 1'b0;
            adc_mi_fh1_sla0      <= 1'b0;
            adc_mi_fh1_sla1      <= 1'b1;
            fh1_h_key            <= 1'b1;
            fh1_l_key            <= 1'b0;
            fh2_h_key            <= 1'b1;
            fh2_l_key            <= 1'b0;
            adc_mh_sla2          <= 1'b0;
            adc_mh_sla1          <= 1'b0;
            adc_mh_sla0          <= 1'b0;
        end
        else if (write_relay) begin
            adc_mi_pm1_sa_sla0 <= sir_wdat[1];
            adc_mi_pm1_sc_sla0 <= sir_wdat[9];
            adc_mi_pm2_sc_sla0 <= sir_wdat[23];
            adc_mi_pm2_sc_sla1 <= sir_wdat[22];
            adc_mp2c_fh2_sla2  <= sir_wdat[21];
            adc_mi_fh1_sla0    <= sir_wdat[33];
            adc_mi_fh1_sla1    <= sir_wdat[32];
            fh1_h_key          <= sir_wdat[41];
            fh1_l_key          <= sir_wdat[40];
            fh2_h_key          <= sir_wdat[51];
            fh2_l_key          <= sir_wdat[50];
            adc_mh_sla2        <= sir_wdat[42];
            adc_mh_sla1        <= sir_wdat[43];
            adc_mh_sla0        <= sir_wdat[44];
            g3vm_k1            <= sir_wdat[3];
            g3vm_k3            <= sir_wdat[7];
            g3vm_k5            <= sir_wdat[11];
            g3vm_k7            <= sir_wdat[15];
            g3vm_k15           <= sir_wdat[39];
            g3vm_k16           <= sir_wdat[38];
            en_vpp_dut         <= sir_wdat[49];
        end
    end

    // --------------------------------------------------------
    // Watchdog reset register
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rst_signal     <= 1'b0;
            rst_12v_signal <= 1'b0;
        end
        else if (write_reset) begin
            rst_signal     <= sir_wdat[0];
            rst_12v_signal <= sir_wdat[1];
        end
    end

    // --------------------------------------------------------
    // BAR03 read data decode
    // --------------------------------------------------------
    always_comb begin
        case (sir_addr)
            `bar03_IRSP_U68_CTRL: sir_rdat_next = {16'd0, irsp_u68_data_out, 64'd0};
            `bar03_IRSP_U68_DATA: sir_rdat_next = {16'd0, irsp_u68_data_out, 64'd0};
            `bar03_AD5272_CTRL:   sir_rdat_next = ad5272_reg;
            `bar03_AD5272_DATA:   sir_rdat_next = {{80{1'b0}}, ad5272_2_read_data, 6'd0};
            `bar03_EEPROM_CTRL:   sir_rdat_next = {16'd0, 64'd0, eeprom_data_out};
            `bar03_EEPROM_DATA:   sir_rdat_next = {16'd0, 64'd0, eeprom_data_out};
            `bar03_IRSP_U67_CTRL: sir_rdat_next = {16'd0, irsp_u67_data_out, 64'd0};
            default:                  sir_rdat_next = 96'h0;
        endcase
    end

    bar_response u_bar_response (
        .clk           (clk           ),
        .rst_n         (rst_n         ),
        .sir_sel       (sir_sel       ),
        .sir_read      (sir_read      ),
        .sir_rdat_next (sir_rdat_next ),
        .sir_dack      (sir_dack      ),
        .sir_rdat      (sir_rdat      )
    );

endmodule
