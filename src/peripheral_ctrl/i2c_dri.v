/**
 * i2c_dri
 * I2C driver with 4x SCL clock generation, supporting 8/16-bit data,
 * single-byte command mode, and configurable sub-address width.
 */
module i2c_dri
#(
    parameter CLK_FREQ  = 32'd50_000_000,  // Input clock frequency (Hz)
    parameter I2C_FREQ  = 18'd250_000      // I2C SCL frequency (Hz)
)
(
    input                clk               ,  // System clock
    input                rst_n             ,  // Active-low reset

    // I2C configuration
    input                send_byte_ctrl    ,  // 1 = command byte only, no data byte
    input                data_bit_ctrl     ,  // 0 = 8-bit data, 1 = 16-bit data
    input  [ 6:0]        SLAVE_ADDR        ,  // 7-bit slave address
    input                i2c_exec          ,  // I2C execution trigger
    input                bit_ctrl          ,  // Sub-address width: 1 = 16-bit, 0 = 8-bit
    input                i2c_rh_wl         ,  // 0 = write, 1 = read
    input  [15:0]        i2c_addr          ,  // Internal register address
    input  [15:0]        i2c_data_w        ,  // Write data
    output reg [15:0]    i2c_data_r        ,  // Read data
    output reg           i2c_done          ,  // Transaction complete flag
    output reg           i2c_ack           ,  // ACK flag: 0 = ACK, 1 = NACK
    output reg           scl               ,  // I2C serial clock
    inout                sda               ,  // I2C serial data

    output reg           dri_clk              // 4x SCL driving clock
);

    // --------------------------------------------------------
    // One-hot state encoding (16 bits)
    // --------------------------------------------------------
    localparam st_idle        = 16'b0000_0000_0000_0001;  // Idle
    localparam st_sladdr      = 16'b0000_0000_0000_0010;  // Send slave address
    localparam st_addr16      = 16'b0000_0000_0000_0100;  // Send 16-bit sub-address
    localparam st_addr8       = 16'b0000_0000_0000_1000;  // Send 8-bit sub-address
    localparam st_data_wr     = 16'b0000_0000_0001_0000;  // Write data (8-bit)
    localparam st_addr_rd     = 16'b0000_0000_0010_0000;  // Send slave address for read
    localparam st_data_rd     = 16'b0000_0000_0100_0000;  // Read data (8-bit)
    localparam st_stop        = 16'b0000_0000_1000_0000;  // Stop condition
    localparam st_data_wr_16  = 16'b0000_0001_0000_0000;  // Write data (16-bit, high byte)
    localparam st_data_rd_16  = 16'b0000_0010_0000_0000;  // Read data (16-bit, high byte)

    // --------------------------------------------------------
    // Internal registers
    // --------------------------------------------------------
    reg                 sda_dir        ;  // SDA direction: 1 = output, 0 = input
    reg                 sda_out        ;  // SDA output value
    reg                 st_done        ;  // State completion flag
    reg                 wr_flag        ;  // Write flag (0 = write, 1 = read)
    reg  [ 6:0]         cnt            ;  // Bit counter within state
    reg  [15:0]         cur_state      ;  // Current state
    reg  [15:0]         next_state     ;  // Next state
    reg  [15:0]         addr_t         ;  // Latched sub-address
    reg  [ 7:0]         data_r         ;  // Received data byte buffer
    reg  [15:0]         data_wr_t      ;  // Latched write data
    reg  [ 9:0]         clk_cnt        ;  // Clock divider counter

    // --------------------------------------------------------
    // Derived wires
    // --------------------------------------------------------
    wire                sda_in         ;  // SDA input value
    wire [ 8:0]         clk_divide     ;  // Clock division factor

    // --------------------------------------------------------
    // SDA bidirectional buffer
    // --------------------------------------------------------
    assign sda       = sda_dir ? sda_out : 1'bz;
    assign sda_in    = sda;

    // Clock division: dri_clk = CLK_FREQ / (4 * I2C_FREQ)
    assign clk_divide = (CLK_FREQ / I2C_FREQ) >> 2'd2;

    // --------------------------------------------------------
    // Generate 4x SCL driving clock (dri_clk)
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dri_clk <= 1'b0;
            clk_cnt <= 10'd0;
        end
        else if (clk_cnt == clk_divide[8:1] - 1'd1) begin
            clk_cnt <= 10'd0;
            dri_clk <= ~dri_clk;
        end
        else begin
            clk_cnt <= clk_cnt + 1'b1;
        end
    end

    // --------------------------------------------------------
    // State machine: synchronous state transition
    // --------------------------------------------------------
    always @(posedge dri_clk or negedge rst_n) begin
        if (!rst_n)
            cur_state <= st_idle;
        else
            cur_state <= next_state;
    end

    // --------------------------------------------------------
    // State machine: combinational next-state logic
    // --------------------------------------------------------
    always @(*) begin
        next_state = st_idle;
        case (cur_state)
            st_idle: begin                              // Idle
                if (i2c_exec)
                    next_state = st_sladdr;
                else
                    next_state = st_idle;
            end
            st_sladdr: begin
                if (st_done)
                    next_state = bit_ctrl ? st_addr16 : st_addr8;
                else
                    next_state = st_sladdr;
            end
            st_addr16: begin                            // Send 16-bit sub-address
                if (st_done)
                    next_state = st_addr8;
                else
                    next_state = st_addr16;
            end
            st_addr8: begin                             // 8-bit sub-address
                if (st_done) begin
                    if (wr_flag == 1'b0 && send_byte_ctrl == 1'b0)
                        next_state = st_data_wr;
                    else if (wr_flag == 1'b0 && send_byte_ctrl == 1'b1)
                        next_state = st_stop;
                    else
                        next_state = st_addr_rd;
                end
                else
                    next_state = st_addr8;
            end
            st_data_wr: begin                           // Write data (8-bit)
                if (st_done)
                    next_state = (data_bit_ctrl == 1'b0) ? st_stop : st_data_wr_16;
                else
                    next_state = st_data_wr;
            end
            st_data_wr_16: begin                        // Write data (high byte)
                if (st_done)
                    next_state = st_stop;
                else
                    next_state = st_data_wr_16;
            end
            st_addr_rd: begin                           // Send address for read
                if (st_done)
                    next_state = st_data_rd;
                else
                    next_state = st_addr_rd;
            end
            st_data_rd: begin                           // Read data (8-bit)
                if (st_done)
                    next_state = (data_bit_ctrl == 1'b0) ? st_stop : st_data_rd_16;
                else
                    next_state = st_data_rd;
            end
            st_data_rd_16: begin                        // Read data (high byte)
                if (st_done)
                    next_state = st_stop;
                else
                    next_state = st_data_rd_16;
            end
            st_stop: begin                              // Stop condition
                if (st_done)
                    next_state = st_idle;
                else
                    next_state = st_stop;
            end
            default: next_state = st_idle;
        endcase
    end

    // --------------------------------------------------------
    // State machine: output logic (registered)
    // --------------------------------------------------------
    always @(posedge dri_clk or negedge rst_n) begin
        if (!rst_n) begin
            scl        <= 1'b1;
            sda_out    <= 1'b1;
            sda_dir    <= 1'b1;
            i2c_done   <= 1'b0;
            i2c_ack    <= 1'b0;
            cnt        <= 7'd0;
            st_done    <= 1'b0;
            data_r     <= 8'd0;
            i2c_data_r <= 16'd0;
            wr_flag    <= 1'b0;
            addr_t     <= 16'd0;
            data_wr_t  <= 16'd0;
        end
        else begin
            st_done <= 1'b0;
            cnt     <= cnt + 1'b1;
            case (cur_state)
                // ----------------------------------------------------
                // IDLE
                // ----------------------------------------------------
                st_idle: begin
                    scl      <= 1'b1;
                    sda_out  <= 1'b1;
                    sda_dir  <= 1'b1;
                    i2c_done <= 1'b0;
                    cnt      <= 7'd0;
                    if (i2c_exec) begin
                        wr_flag   <= i2c_rh_wl;
                        addr_t    <= i2c_addr;
                        data_wr_t <= i2c_data_w;
                        i2c_ack   <= 1'b0;
                    end
                end

                // ----------------------------------------------------
                // Send slave address + R/W bit
                // ----------------------------------------------------
                st_sladdr: begin
                    case (cnt)
                        7'd1 : sda_out <= 1'b0;              // Start condition
                        7'd3 : scl     <= 1'b0;
                        7'd4 : sda_out <= SLAVE_ADDR[6];     // Addr[6]
                        7'd5 : scl     <= 1'b1;
                        7'd7 : scl     <= 1'b0;
                        7'd8 : sda_out <= SLAVE_ADDR[5];
                        7'd9 : scl     <= 1'b1;
                        7'd11: scl     <= 1'b0;
                        7'd12: sda_out <= SLAVE_ADDR[4];
                        7'd13: scl     <= 1'b1;
                        7'd15: scl     <= 1'b0;
                        7'd16: sda_out <= SLAVE_ADDR[3];
                        7'd17: scl     <= 1'b1;
                        7'd19: scl     <= 1'b0;
                        7'd20: sda_out <= SLAVE_ADDR[2];
                        7'd21: scl     <= 1'b1;
                        7'd23: scl     <= 1'b0;
                        7'd24: sda_out <= SLAVE_ADDR[1];
                        7'd25: scl     <= 1'b1;
                        7'd27: scl     <= 1'b0;
                        7'd28: sda_out <= SLAVE_ADDR[0];
                        7'd29: scl     <= 1'b1;
                        7'd31: scl     <= 1'b0;
                        7'd32: sda_out <= 1'b0;              // R/W = 0 (write)
                        7'd33: scl     <= 1'b1;
                        7'd35: scl     <= 1'b0;
                        7'd36: begin                        // Release SDA for ACK
                            sda_dir <= 1'b0;
                            sda_out <= 1'b1;
                        end
                        7'd37: scl     <= 1'b1;              // 9th clock rising edge
                        7'd38: begin                        // Sample ACK
                            st_done <= 1'b1;
                            if (sda_in == 1'b1)
                                i2c_ack <= 1'b1;
                        end
                        7'd39: begin
                            scl <= 1'b0;
                            cnt <= 1'b0;
                        end
                        default: ;
                    endcase
                end

                // ----------------------------------------------------
                // Send high byte of 16-bit sub-address
                // ----------------------------------------------------
                st_addr16: begin
                    case (cnt)
                        7'd0 : begin
                            sda_dir <= 1'b1;
                            sda_out <= addr_t[15];           // Addr[15]
                        end
                        7'd1 : scl <= 1'b1;
                        7'd3 : scl <= 1'b0;
                        7'd4 : sda_out <= addr_t[14];
                        7'd5 : scl <= 1'b1;
                        7'd7 : scl <= 1'b0;
                        7'd8 : sda_out <= addr_t[13];
                        7'd9 : scl <= 1'b1;
                        7'd11: scl <= 1'b0;
                        7'd12: sda_out <= addr_t[12];
                        7'd13: scl <= 1'b1;
                        7'd15: scl <= 1'b0;
                        7'd16: sda_out <= addr_t[11];
                        7'd17: scl <= 1'b1;
                        7'd19: scl <= 1'b0;
                        7'd20: sda_out <= addr_t[10];
                        7'd21: scl <= 1'b1;
                        7'd23: scl <= 1'b0;
                        7'd24: sda_out <= addr_t[9];
                        7'd25: scl <= 1'b1;
                        7'd27: scl <= 1'b0;
                        7'd28: sda_out <= addr_t[8];
                        7'd29: scl <= 1'b1;
                        7'd31: scl <= 1'b0;
                        7'd32: begin                        // Release SDA for ACK
                            sda_dir <= 1'b0;
                            sda_out <= 1'b1;
                        end
                        7'd33: scl  <= 1'b1;                 // 9th clock rising edge
                        7'd34: begin                        // Sample ACK
                            st_done <= 1'b1;
                            if (sda_in == 1'b1)
                                i2c_ack <= 1'b1;
                        end
                        7'd35: begin
                            scl <= 1'b0;
                            cnt <= 1'b0;
                        end
                        default: ;
                    endcase
                end

                // ----------------------------------------------------
                // Send low byte of sub-address
                // ----------------------------------------------------
                st_addr8: begin
                    case (cnt)
                        7'd0: begin
                            sda_dir <= 1'b1;
                            sda_out <= addr_t[7];            // Addr[7]
                        end
                        7'd1 : scl <= 1'b1;
                        7'd3 : scl <= 1'b0;
                        7'd4 : sda_out <= addr_t[6];
                        7'd5 : scl <= 1'b1;
                        7'd7 : scl <= 1'b0;
                        7'd8 : sda_out <= addr_t[5];
                        7'd9 : scl <= 1'b1;
                        7'd11: scl <= 1'b0;
                        7'd12: sda_out <= addr_t[4];
                        7'd13: scl <= 1'b1;
                        7'd15: scl <= 1'b0;
                        7'd16: sda_out <= addr_t[3];
                        7'd17: scl <= 1'b1;
                        7'd19: scl <= 1'b0;
                        7'd20: sda_out <= addr_t[2];
                        7'd21: scl <= 1'b1;
                        7'd23: scl <= 1'b0;
                        7'd24: sda_out <= addr_t[1];
                        7'd25: scl <= 1'b1;
                        7'd27: scl <= 1'b0;
                        7'd28: sda_out <= addr_t[0];
                        7'd29: scl <= 1'b1;
                        7'd31: scl <= 1'b0;
                        7'd32: begin                        // Release SDA for ACK
                            sda_dir <= 1'b0;
                            sda_out <= 1'b1;
                        end
                        7'd33: scl     <= 1'b1;             // 9th clock rising edge
                        7'd34: begin                        // Sample ACK
                            st_done <= 1'b1;
                            if (sda_in == 1'b1)
                                i2c_ack <= 1'b1;
                        end
                        7'd35: begin
                            scl <= 1'b0;
                            cnt <= 1'b0;
                        end
                        default: ;
                    endcase
                end

                // ----------------------------------------------------
                // Write 8-bit data
                // ----------------------------------------------------
                st_data_wr: begin
                    case (cnt)
                        7'd0: begin
                            sda_out <= data_wr_t[7];
                            sda_dir <= 1'b1;
                        end
                        7'd1 : scl <= 1'b1;
                        7'd3 : scl <= 1'b0;
                        7'd4 : sda_out <= data_wr_t[6];
                        7'd5 : scl <= 1'b1;
                        7'd7 : scl <= 1'b0;
                        7'd8 : sda_out <= data_wr_t[5];
                        7'd9 : scl <= 1'b1;
                        7'd11: scl <= 1'b0;
                        7'd12: sda_out <= data_wr_t[4];
                        7'd13: scl <= 1'b1;
                        7'd15: scl <= 1'b0;
                        7'd16: sda_out <= data_wr_t[3];
                        7'd17: scl <= 1'b1;
                        7'd19: scl <= 1'b0;
                        7'd20: sda_out <= data_wr_t[2];
                        7'd21: scl <= 1'b1;
                        7'd23: scl <= 1'b0;
                        7'd24: sda_out <= data_wr_t[1];
                        7'd25: scl <= 1'b1;
                        7'd27: scl <= 1'b0;
                        7'd28: sda_out <= data_wr_t[0];
                        7'd29: scl <= 1'b1;
                        7'd31: scl <= 1'b0;
                        7'd32: begin                        // Release SDA for ACK
                            sda_dir <= 1'b0;
                            sda_out <= 1'b1;
                        end
                        7'd33: scl <= 1'b1;                 // 9th clock rising edge
                        7'd34: begin                        // Sample ACK
                            st_done <= 1'b1;
                            if (sda_in == 1'b1)
                                i2c_ack <= 1'b1;
                        end
                        7'd35: begin
                            scl <= 1'b0;
                            cnt <= 1'b0;
                        end
                        default: ;
                    endcase
                end

                // ----------------------------------------------------
                // Write high byte of 16-bit data
                // ----------------------------------------------------
                st_data_wr_16: begin
                    case (cnt)
                        7'd0: begin
                            sda_out <= data_wr_t[15];
                            sda_dir <= 1'b1;
                        end
                        7'd1 : scl <= 1'b1;
                        7'd3 : scl <= 1'b0;
                        7'd4 : sda_out <= data_wr_t[14];
                        7'd5 : scl <= 1'b1;
                        7'd7 : scl <= 1'b0;
                        7'd8 : sda_out <= data_wr_t[13];
                        7'd9 : scl <= 1'b1;
                        7'd11: scl <= 1'b0;
                        7'd12: sda_out <= data_wr_t[12];
                        7'd13: scl <= 1'b1;
                        7'd15: scl <= 1'b0;
                        7'd16: sda_out <= data_wr_t[11];
                        7'd17: scl <= 1'b1;
                        7'd19: scl <= 1'b0;
                        7'd20: sda_out <= data_wr_t[10];
                        7'd21: scl <= 1'b1;
                        7'd23: scl <= 1'b0;
                        7'd24: sda_out <= data_wr_t[9];
                        7'd25: scl <= 1'b1;
                        7'd27: scl <= 1'b0;
                        7'd28: sda_out <= data_wr_t[8];
                        7'd29: scl <= 1'b1;
                        7'd31: scl <= 1'b0;
                        7'd32: begin                        // Release SDA for ACK
                            sda_dir <= 1'b0;
                            sda_out <= 1'b1;
                        end
                        7'd33: scl <= 1'b1;                 // 9th clock rising edge
                        7'd34: begin                        // Sample ACK
                            st_done <= 1'b1;
                            if (sda_in == 1'b1)
                                i2c_ack <= 1'b1;
                        end
                        7'd35: begin
                            scl <= 1'b0;
                            cnt <= 1'b0;
                        end
                        default: ;
                    endcase
                end

                // ----------------------------------------------------
                // Repeated start + slave address for read
                // ----------------------------------------------------
                st_addr_rd: begin
                    case (cnt)
                        7'd0 : begin
                            sda_dir <= 1'b1;
                            sda_out <= 1'b1;
                        end
                        7'd1 : scl <= 1'b1;
                        7'd2 : sda_out <= 1'b0;              // Repeated start
                        7'd3 : scl <= 1'b0;
                        7'd4 : sda_out <= SLAVE_ADDR[6];     // Addr[6]
                        7'd5 : scl <= 1'b1;
                        7'd7 : scl <= 1'b0;
                        7'd8 : sda_out <= SLAVE_ADDR[5];
                        7'd9 : scl <= 1'b1;
                        7'd11: scl <= 1'b0;
                        7'd12: sda_out <= SLAVE_ADDR[4];
                        7'd13: scl <= 1'b1;
                        7'd15: scl <= 1'b0;
                        7'd16: sda_out <= SLAVE_ADDR[3];
                        7'd17: scl <= 1'b1;
                        7'd19: scl <= 1'b0;
                        7'd20: sda_out <= SLAVE_ADDR[2];
                        7'd21: scl <= 1'b1;
                        7'd23: scl <= 1'b0;
                        7'd24: sda_out <= SLAVE_ADDR[1];
                        7'd25: scl <= 1'b1;
                        7'd27: scl <= 1'b0;
                        7'd28: sda_out <= SLAVE_ADDR[0];
                        7'd29: scl <= 1'b1;
                        7'd31: scl <= 1'b0;
                        7'd32: sda_out <= 1'b1;              // R/W = 1 (read)
                        7'd33: scl <= 1'b1;
                        7'd35: scl <= 1'b0;
                        7'd36: begin                        // Release SDA for ACK
                            sda_dir <= 1'b0;
                            sda_out <= 1'b1;
                        end
                        7'd37: scl     <= 1'b1;             // 9th clock rising edge
                        7'd38: begin                        // Sample ACK
                            st_done <= 1'b1;
                            if (sda_in == 1'b1)
                                i2c_ack <= 1'b1;
                        end
                        7'd39: begin
                            scl <= 1'b0;
                            cnt <= 1'b0;
                        end
                        default: ;
                    endcase
                end

                // ----------------------------------------------------
                // Read 8-bit data
                // ----------------------------------------------------
                st_data_rd: begin
                    case (cnt)
                        7'd0: sda_dir <= 1'b0;               // Release SDA
                        7'd1: begin
                            data_r[7] <= sda_in;
                            scl       <= 1'b1;
                        end
                        7'd3: scl  <= 1'b0;
                        7'd5: begin
                            data_r[6] <= sda_in;
                            scl       <= 1'b1;
                        end
                        7'd7: scl  <= 1'b0;
                        7'd9: begin
                            data_r[5] <= sda_in;
                            scl       <= 1'b1;
                        end
                        7'd11: scl  <= 1'b0;
                        7'd13: begin
                            data_r[4] <= sda_in;
                            scl       <= 1'b1;
                        end
                        7'd15: scl  <= 1'b0;
                        7'd17: begin
                            data_r[3] <= sda_in;
                            scl       <= 1'b1;
                        end
                        7'd19: scl  <= 1'b0;
                        7'd21: begin
                            data_r[2] <= sda_in;
                            scl       <= 1'b1;
                        end
                        7'd23: scl  <= 1'b0;
                        7'd25: begin
                            data_r[1] <= sda_in;
                            scl       <= 1'b1;
                        end
                        7'd27: scl  <= 1'b0;
                        7'd29: begin
                            data_r[0] <= sda_in;
                            scl       <= 1'b1;
                        end
                        7'd31: scl  <= 1'b0;
                        7'd32: begin
                            if (data_bit_ctrl) begin
                                sda_dir <= 1'b1;              // ACK (more bytes)
                                sda_out <= 1'b0;
                            end
                            else begin
                                sda_dir <= 1'b1;              // NACK (end of read)
                                sda_out <= 1'b1;
                            end
                        end
                        7'd33: scl     <= 1'b1;              // 9th clock rising edge
                        7'd34: st_done <= 1'b1;
                        7'd35: begin
                            scl <= 1'b0;
                            cnt <= 1'b0;
                            i2c_data_r[7:0] <= data_r;
                        end
                        default: ;
                    endcase
                end

                // ----------------------------------------------------
                // Read high byte of 16-bit data
                // ----------------------------------------------------
                st_data_rd_16: begin
                    case (cnt)
                        7'd0: sda_dir <= 1'b0;               // Release SDA
                        7'd1: begin
                            data_r[7] <= sda_in;
                            scl       <= 1'b1;
                        end
                        7'd3: scl  <= 1'b0;
                        7'd5: begin
                            data_r[6] <= sda_in;
                            scl       <= 1'b1;
                        end
                        7'd7: scl  <= 1'b0;
                        7'd9: begin
                            data_r[5] <= sda_in;
                            scl       <= 1'b1;
                        end
                        7'd11: scl  <= 1'b0;
                        7'd13: begin
                            data_r[4] <= sda_in;
                            scl       <= 1'b1;
                        end
                        7'd15: scl  <= 1'b0;
                        7'd17: begin
                            data_r[3] <= sda_in;
                            scl       <= 1'b1;
                        end
                        7'd19: scl  <= 1'b0;
                        7'd21: begin
                            data_r[2] <= sda_in;
                            scl       <= 1'b1;
                        end
                        7'd23: scl  <= 1'b0;
                        7'd25: begin
                            data_r[1] <= sda_in;
                            scl       <= 1'b1;
                        end
                        7'd27: scl  <= 1'b0;
                        7'd29: begin
                            data_r[0] <= sda_in;
                            scl       <= 1'b1;
                        end
                        7'd31: scl  <= 1'b0;
                        7'd32: begin
                            sda_dir <= 1'b1;                  // NACK (end of read)
                            sda_out <= 1'b1;
                        end
                        7'd33: scl     <= 1'b1;              // 9th clock rising edge
                        7'd34: st_done <= 1'b1;
                        7'd35: begin
                            scl <= 1'b0;
                            cnt <= 1'b0;
                            i2c_data_r[15:8] <= data_r;
                        end
                        default: ;
                    endcase
                end

                // ----------------------------------------------------
                // STOP condition
                // ----------------------------------------------------
                st_stop: begin
                    case (cnt)
                        7'd0: begin
                            sda_dir <= 1'b1;
                            sda_out <= 1'b0;                  // SDA low
                        end
                        7'd1 : scl     <= 1'b1;               // SCL high
                        7'd3 : sda_out <= 1'b1;               // SDA high (stop)
                        7'd15: st_done <= 1'b1;
                        7'd16: begin
                            cnt      <= 1'b0;
                            i2c_done <= 1'b1;                  // Transaction complete
                        end
                        default: ;
                    endcase
                end

                default: ;
            endcase
        end
    end

endmodule
