/**
 * i2c_cfg
 * I2C configuration wrapper with edge-triggered write/read command generation.
 * Supports 8/16-bit data modes and single-byte command mode.
 */
module i2c_cfg
#(
    parameter IIC_BIT_CTRL = 1'b0           ,  // I2C bit control mode
    parameter CLK_FREQ     = 32'd200_000_000   // System clock frequency (Hz)
)
(
    input  logic                clk                 ,  // 200 MHz, same as UART
    input  logic                rst_n               ,  // Active-low reset (PLL locked)

    input  logic                send_byte_ctrl      ,  // 1 = send command byte only, no data byte
    input  logic                data_bit_ctrl       ,  // 0 = 8-bit data, 1 = 16-bit data

    input  logic [ 6:0]         IRSP_IIC_DEVICE_ADDR,  // 7-bit I2C slave address

    output logic                scl_o               ,  // I2C serial clock
    inout  wire                 sda_io              ,  // I2C serial data

    // Register read/write interface
    input  logic                wr_en_i             ,  // Write enable
    input  logic                rd_en_i             ,  // Read enable
    input  logic [15:0]         wr_reg_addr_i       ,  // Write register address
    input  logic [15:0]         rd_reg_addr_i       ,  // Read register address
    input  logic [15:0]         data_in_i           ,  // Write data
    output reg  [15:0]          data_out_o          ,  // Read data from I2C
    output reg                  data_out_valid         // Read data valid
);

    // --------------------------------------------------------
    // Internal signals
    // --------------------------------------------------------
    logic                i2c_en_i         ;  // I2C enable
    logic [ 4:0]         bit_ctrl_i       ;  // Bit control (16-bit address / 8-bit access)
    logic                i2c_wr_i         ;  // I2C write enable
    logic [ 6:0]         slave_addr_i     ;  // I2C slave address
    logic [15:0]         i2c_addr_i       ;  // I2C register address
    logic [15:0]         i2c_data_w_i     ;  // I2C write data
    logic [15:0]         i2c_data_r_o     ;  // I2C read data
    logic                i2c_done_o       ;  // I2C operation done
    logic                i2c_done_o_r     ;  // I2C operation done (registered)
    logic                i2c_ack_o        ;  // I2C acknowledge (unused)
    logic                st_done_o        ;  // State done (unused)

    logic [ 6:0]         device_addr      ;  // Device address (from input)

    reg                  wr_en_r          ;
    reg                  rd_en_r          ;
    reg  [15:0]          wr_reg_addr_r    ;
    reg  [15:0]          rd_reg_addr_r    ;
    reg  [15:0]          data_in_r        ;
    reg                  r_send_byte_ctrl_sample ;
    reg                  r_data_bit_ctrl_sample  ;
    reg                  wr_en_r1         ;
    reg                  rd_en_r1         ;
    reg                  r_send_byte_ctrl        ;
    reg                  r_data_bit_ctrl         ;

    wire                 w_write_start           ;
    wire                 w_read_start            ;

    // --------------------------------------------------------
    // Constant assignments
    // --------------------------------------------------------
    assign bit_ctrl_i  = 5'd16;                // 16-bit register address, 8-bit access
    assign device_addr = IRSP_IIC_DEVICE_ADDR; // Connect to input port
    assign w_write_start = !wr_en_r1 && wr_en_r;
    assign w_read_start  = !rd_en_r1 && rd_en_r;

    // --------------------------------------------------------
    // Input register stage
    // The BAR controls are short pulses. Register them in the input stage,
    // then hold the accepted values until the slow I2C transaction ends.
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_en_r       <= 1'b0;
            rd_en_r       <= 1'b0;
            wr_reg_addr_r <= '0;
            rd_reg_addr_r <= '0;
            data_in_r     <= '0;
            i2c_done_o_r  <= 1'b0;
        end
        else begin
            wr_en_r       <= wr_en_i;
            rd_en_r       <= rd_en_i;
            wr_reg_addr_r <= wr_reg_addr_i;
            rd_reg_addr_r <= rd_reg_addr_i;
            data_in_r     <= data_in_i;
            i2c_done_o_r  <= i2c_done_o;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            r_send_byte_ctrl_sample <= 1'b0;
        else
            r_send_byte_ctrl_sample <= send_byte_ctrl;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            r_data_bit_ctrl_sample <= 1'b0;
        else
            r_data_bit_ctrl_sample <= data_bit_ctrl;
    end

    // --------------------------------------------------------
    // Edge detection registers
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_en_r1 <= 1'b0;
            rd_en_r1 <= 1'b0;
        end
        else begin
            wr_en_r1 <= wr_en_r;
            rd_en_r1 <= rd_en_r;
        end
    end

    // --------------------------------------------------------
    // I2C command generation (write/read)
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            i2c_en_i     <= 1'b0;
            i2c_wr_i     <= 1'b0;
            slave_addr_i <= '0;
            i2c_addr_i   <= '0;
            i2c_data_w_i <= '0;
        end
        else if (i2c_done_o == 1'b1) begin
            // Clear command after completion
            i2c_en_i     <= 1'b0;
            i2c_wr_i     <= 1'b0;
            slave_addr_i <= '0;
            i2c_addr_i   <= '0;
            i2c_data_w_i <= '0;
        end
        else if (w_write_start) begin
            // Rising edge on write enable
            i2c_en_i     <= 1'b1;
            i2c_wr_i     <= 1'b1;
            slave_addr_i <= device_addr;
            i2c_addr_i   <= wr_reg_addr_r;
            i2c_data_w_i <= data_in_r;
        end
        else if (w_read_start) begin
            // Rising edge on read enable
            i2c_en_i     <= 1'b1;
            i2c_wr_i     <= 1'b0;
            slave_addr_i <= device_addr;
            i2c_addr_i   <= rd_reg_addr_r;
            i2c_data_w_i <= '0;
        end
        else begin
            // Hold values
            i2c_en_i     <= i2c_en_i;
            i2c_wr_i     <= i2c_wr_i;
            slave_addr_i <= slave_addr_i;
            i2c_addr_i   <= i2c_addr_i;
            i2c_data_w_i <= i2c_data_w_i;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            r_send_byte_ctrl <= 1'b0;
        else if (i2c_done_o == 1'b1)
            r_send_byte_ctrl <= 1'b0;
        else if (w_write_start || w_read_start)
            r_send_byte_ctrl <= r_send_byte_ctrl_sample;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            r_data_bit_ctrl <= 1'b0;
        else if (i2c_done_o == 1'b1)
            r_data_bit_ctrl <= 1'b0;
        else if (w_write_start || w_read_start)
            r_data_bit_ctrl <= r_data_bit_ctrl_sample;
    end

    // --------------------------------------------------------
    // Read data capture (valid on i2c_done rising edge, only for reads)
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out_o     <= '0;
            data_out_valid <= 1'b0;
        end
        else if (i2c_done_o && !i2c_done_o_r && (i2c_wr_i == 1'b0)) begin
            data_out_o     <= i2c_data_r_o;
            data_out_valid <= 1'b1;
        end
        else begin
            data_out_o     <= data_out_o;
            data_out_valid <= 1'b0;
        end
    end

    // --------------------------------------------------------
    // I2C driver instantiation
    // --------------------------------------------------------
    i2c_dri
    #(
        .CLK_FREQ       (CLK_FREQ       )
    )
    u_i2c_dri (
        .clk            (clk            ),
        .rst_n          (rst_n          ),
        .send_byte_ctrl (r_send_byte_ctrl),
        .data_bit_ctrl  (r_data_bit_ctrl ),  // 0 = 8-bit, 1 = 16-bit data
        .SLAVE_ADDR     (slave_addr_i   ),
        .i2c_exec       (i2c_en_i       ),
        .bit_ctrl       (IIC_BIT_CTRL   ),
        .i2c_rh_wl      (!i2c_wr_i      ),  // High = read, low = write
        .i2c_addr       (i2c_addr_i     ),
        .i2c_data_w     (i2c_data_w_i   ),
        .i2c_data_r     (i2c_data_r_o   ),
        .i2c_done       (i2c_done_o     ),
        .i2c_ack        (),
        .scl            (scl_o          ),
        .sda            (sda_io         ),
        .dri_clk        ()
    );

endmodule
