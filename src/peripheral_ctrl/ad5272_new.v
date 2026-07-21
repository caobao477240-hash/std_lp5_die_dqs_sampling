/**
 * ad5272_new
 * I2C-compatible driver for AD5272 digital rheostat.
 * Generates SCL at ~20kHz (from 200MHz system clock) and SDA bitstream
 * using pre-encoded 232-bit parameter vectors.
 * Supports a single write-read transaction per trigger pulse.
 */
`timescale 1ns / 1ps

module ad5272_new (
    input               sys_clk         ,  // 200 MHz system clock
    input               locked          ,  // PLL locked / system ready
    output reg          scl             ,  // I2C serial clock
    inout               sda             ,  // I2C serial data

    input               ad5272_en       ,  // Transaction trigger (pulse)
    input  [ 1:0]       Read_Addr       ,  // Read address (2-bit)
    input  [ 9:0]       Read_Data       ,  // Expected read data (10-bit)
    input  [ 1:0]       Write_Addr      ,  // Target write address (2-bit)
    input  [ 3:0]       Write_Command   ,  // Command (4-bit)
    input  [ 9:0]       Write_Data      ,  // Write data (10-bit)
    output reg          ad5272_done        // Transaction complete flag
);

    // --------------------------------------------------------
    // Parameters
    //    sys_clk = 200 MHz, T = 5ns
    //    f_scl   = 20 kHz,  T_scl = 50000ns
    //    Bit period = 50000ns / 5ns = 10000, use 2500 for 4x oversampling
    // --------------------------------------------------------
    parameter INNER_CNT_END = 9'd2;          // Internal reset release delay
    parameter SCL_CNT_END   = 12'd2500;      // SCL half-period counter max

    // Pre-encoded SCL bitstream (232 bits, 4x oversampling per bit cell)
    parameter scl_paramter  = 232'b1110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0111_1110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0111;

    // SDA enable mask (0 = drive, 1 = release / ACK)
    parameter en_paramter   = 232'b1111_1111_1111_1111_1111_1111_1111_1111_1111_0000_1111_1111_1111_1111_1111_1111_1111_1111_0000_1111_1111_1111_1111_1111_1111_1111_1111_0000_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_0000_1111_1111_0000_0000_0000_0000_0000_0000_1111_0000_0000_0000_0000_0000_0000_0000_0000_1111_1111;

    // --------------------------------------------------------
    // Internal reset generation
    // --------------------------------------------------------
    reg         rst_n;
    reg [ 8:0]  rst_inner_cnt;

    // --------------------------------------------------------
    // Counters
    // --------------------------------------------------------
    reg [11:0]  cnt_scl;
    wire        add_cnt_scl;
    wire        end_cnt_scl;

    reg [20:0]  cnt_232;
    wire        add_cnt_232;
    wire        end_cnt_232;

    reg [ 7:0]  cnt_1;
    wire        add_cnt_1;
    wire        end_cnt_1;

    // --------------------------------------------------------
    // SDA signals
    // --------------------------------------------------------
    wire        sda_in;
    reg         sda_out;
    reg         sda_en;

    // --------------------------------------------------------
    // Input pipeline and parameter registers
    // --------------------------------------------------------
    reg         ad5272_en_1     ;
    reg [ 1:0]  Read_Addr_1     ;
    reg [ 9:0]  Read_Data_1     ;
    reg [ 1:0]  Write_Addr_1    ;
    reg [ 3:0]  Write_Command_1 ;
    reg [ 9:0]  Write_Data_1    ;
    reg         ad5272_en_2     ;
    reg [ 1:0]  Read_Addr_2     ;
    reg [ 9:0]  Read_Data_2     ;
    reg [ 1:0]  Write_Addr_2    ;
    reg [ 3:0]  Write_Command_2 ;
    reg [ 9:0]  Write_Data_2    ;
    reg         ad5272_en_ok    ;
    reg [ 1:0]  Read_Addr_ok    ;
    reg [ 9:0]  Read_Data_ok    ;
    reg [ 1:0]  Write_Addr_ok   ;
    reg [ 3:0]  Write_Command_ok;
    reg [ 9:0]  Write_Data_ok   ;

    reg         done_flag;

    // SDA data bitstream (built from input fields)
    reg [231:0] sda_paramter_1_1;

    // --------------------------------------------------------
    // Latch enable pulse (hold until transaction complete)
    // --------------------------------------------------------
    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            ad5272_en_1 <= 1'b0;
        end
        else if (ad5272_done) begin
            ad5272_en_1 <= 1'b0;
        end
        else if (ad5272_en) begin
            ad5272_en_1 <= 1'b1;
        end
        else begin
            ad5272_en_1 <= ad5272_en_1;
        end
    end

    // --------------------------------------------------------
    // Input pipeline and SDA pattern assembly
    // --------------------------------------------------------
    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            Read_Addr_1      <= 'd0;
            Read_Data_1      <= 'd0;
            Write_Addr_1     <= 'd0;
            Write_Command_1  <= 'd0;
            Write_Data_1     <= 'd0;
            ad5272_en_2      <= 'd0;
            Read_Addr_2      <= 'd0;
            Read_Data_2      <= 'd0;
            Write_Addr_2     <= 'd0;
            Write_Command_2  <= 'd0;
            Write_Data_2     <= 'd0;
            ad5272_en_ok     <= 'd0;
            Read_Addr_ok     <= 'd0;
            Read_Data_ok     <= 'd0;
            Write_Addr_ok    <= 'd0;
            Write_Command_ok <= 'd0;
            Write_Data_ok    <= 'd0;
            sda_paramter_1_1 <= 232'd0;
        end
        else begin
            // Capture command fields on trigger rising edge
            Read_Addr_1      <= ad5272_en ? Read_Addr      : Read_Addr_1     ;
            Read_Data_1      <= ad5272_en ? Read_Data      : Read_Data_1     ;
            Write_Addr_1     <= ad5272_en ? Write_Addr     : Write_Addr_1    ;
            Write_Command_1  <= ad5272_en ? Write_Command  : Write_Command_1 ;
            Write_Data_1     <= ad5272_en ? Write_Data     : Write_Data_1    ;

            // Pipeline stages
            ad5272_en_2      <= ad5272_en_1     ;
            Read_Addr_2      <= Read_Addr_1     ;
            Read_Data_2      <= Read_Data_1     ;
            Write_Addr_2     <= Write_Addr_1    ;
            Write_Command_2  <= Write_Command_1 ;
            Write_Data_2     <= Write_Data_1    ;

            ad5272_en_ok     <= ad5272_en_2     ;
            Read_Addr_ok     <= Read_Addr_2     ;
            Read_Data_ok     <= Read_Data_2     ;
            Write_Addr_ok    <= Write_Addr_2    ;
            Write_Command_ok <= Write_Command_2 ;
            Write_Data_ok    <= Write_Data_2    ;

            // Assemble SDA bitstream from latched fields.
            // Each bit is replicated 4 times for 4x oversampling.
            // Format:
            //   Start + Write addr + ack + command + write data + ack
            //   + Repeated start + Read addr + ack + read data + ack + Stop
            sda_paramter_1_1 <= {
                24'b1100_0000_1111_0000_1111_1111,                     // Header
                {4{Write_Addr_ok[1]}}, {4{Write_Addr_ok[0]}},          // Write address
                16'b0000_1111_0000_0000,                                // ack + gap
                {4{Write_Command_ok[3]}}, {4{Write_Command_ok[2]}},    // Command
                {4{Write_Command_ok[1]}}, {4{Write_Command_ok[0]}},
                {4{Write_Data_ok[9]}}, {4{Write_Data_ok[8]}},          // Data high
                4'b1111,                                                // ack
                {4{Write_Data_ok[7]}}, {4{Write_Data_ok[6]}},          // Data low
                {4{Write_Data_ok[5]}}, {4{Write_Data_ok[4]}},
                {4{Write_Data_ok[3]}}, {4{Write_Data_ok[2]}},
                {4{Write_Data_ok[1]}}, {4{Write_Data_ok[0]}},
                32'b1111_0011_1100_0000_1111_0000_1111_1111,        // Repeated start + read header
                {4{Read_Addr_ok[1]}}, {4{Read_Addr_ok[0]}},            // Read address
                32'b1111_1111_0000_0000_1111_1111_1111_1111,            // ack + gap
                {4{Read_Data_ok[9]}}, {4{Read_Data_ok[8]}},            // Expected read data high
                4'b0000,                                                // ack (master)
                {4{Read_Data_ok[7]}}, {4{Read_Data_ok[6]}},            // Expected read data low
                {4{Read_Data_ok[5]}}, {4{Read_Data_ok[4]}},
                {4{Read_Data_ok[3]}}, {4{Read_Data_ok[2]}},
                {4{Read_Data_ok[1]}}, {4{Read_Data_ok[0]}},
                8'b1111_0011                                               // ack + stop
            };
        end
    end

    // --------------------------------------------------------
    // Internal reset generation (release after INNER_CNT_END cycles)
    // --------------------------------------------------------
    always @(negedge sys_clk) begin
        if (rst_inner_cnt < INNER_CNT_END)
            rst_inner_cnt <= rst_inner_cnt + 1'd1;
        else if (rst_inner_cnt == INNER_CNT_END)
            rst_inner_cnt <= rst_inner_cnt;
        else
            rst_inner_cnt <= 0;
    end

    always @(negedge sys_clk) begin
        if (rst_inner_cnt == INNER_CNT_END)
            rst_n <= 1'b1;
        else
            rst_n <= 1'b0;
    end

    // --------------------------------------------------------
    // SDA tri-state buffer
    // --------------------------------------------------------
    IOBUF IOBUF_inst (
        .O  (sda_in  ),  // Buffer output (input to FPGA)
        .I  (sda_out ),  // Buffer input (output from FPGA)
        .IO (sda     ),  // External pin
        .T  (~sda_en )   // 0 = output enabled (sda_en = 1)
    );

    // --------------------------------------------------------
    // SCL and SDA output generation
    // --------------------------------------------------------
    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            scl     <= 1'b1;
            sda_out <= 1'b1;
            sda_en  <= 1'b1;
        end
        else begin
            case (cnt_1)
                0: begin
                    scl     <= scl_paramter[232 - 1 - cnt_232];
                    sda_out <= sda_paramter_1_1[232 - 1 - cnt_232];
                    sda_en  <= en_paramter[232 - 1 - cnt_232];
                end
                default: begin
                    scl     <= 1'b1;
                    sda_out <= 1'b1;
                    sda_en  <= 1'b1;
                end
            endcase
        end
    end

    // --------------------------------------------------------
    // SCL timing counter (divide sys_clk to SCL bit cell)
    // --------------------------------------------------------
    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_scl <= 12'd0;
        end
        else if (ad5272_en_ok == 1'b0) begin
            cnt_scl <= 12'd0;
        end
        else if (add_cnt_scl) begin
            if (end_cnt_scl)
                cnt_scl <= 12'd0;
            else
                cnt_scl <= cnt_scl + 12'd1;
        end
        else begin
            cnt_scl <= cnt_scl;
        end
    end

    assign add_cnt_scl = (locked == 1'b1) && (ad5272_en_ok == 1'b1);
    assign end_cnt_scl = add_cnt_scl && (cnt_scl >= SCL_CNT_END - 1);

    // --------------------------------------------------------
    // Bit index counter (0 .. 231)
    // --------------------------------------------------------
    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_232 <= 21'd0;
        end
        else if (ad5272_en_ok == 1'b0) begin
            cnt_232 <= 21'd0;
        end
        else if (add_cnt_232) begin
            if (end_cnt_232)
                cnt_232 <= 21'd0;
            else
                cnt_232 <= cnt_232 + 21'd1;
        end
        else begin
            cnt_232 <= cnt_232;
        end
    end

    assign add_cnt_232 = end_cnt_scl;
    assign end_cnt_232 = add_cnt_232 && (cnt_232 >= 232 - 1);

    // --------------------------------------------------------
    // Transaction repeat counter (single pass: stops at 1)
    // --------------------------------------------------------
    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_1 <= 8'd0;
        end
        else if (ad5272_en_ok == 1'b0) begin
            cnt_1 <= 8'd0;
        end
        else if (add_cnt_1) begin
            if (end_cnt_1) begin
                // Hold at final value
                cnt_1 <= cnt_1;
            end
            else begin
                cnt_1 <= cnt_1 + 8'd1;
            end
        end
        else begin
            cnt_1 <= cnt_1;
        end
    end

    assign add_cnt_1 = end_cnt_232;
    assign end_cnt_1 = add_cnt_1 && (cnt_1 >= 1 - 1);   // Only one pass

    // --------------------------------------------------------
    // Transaction done flag generation
    // --------------------------------------------------------
    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            ad5272_done <= 1'b0;
            done_flag   <= 1'b0;
        end
        else if (ad5272_en_ok == 1'b0) begin
            ad5272_done <= 1'b0;
            done_flag   <= 1'b0;
        end
        else if ((cnt_1 >= 1) && (done_flag == 1'b0)) begin
            ad5272_done <= 1'b1;
            done_flag   <= 1'b1;
        end
        else begin
            ad5272_done <= ad5272_done;
            done_flag   <= done_flag;
        end
    end

endmodule
