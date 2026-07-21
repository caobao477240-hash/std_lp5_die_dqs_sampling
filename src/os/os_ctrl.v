/**
 * os_ctrl
 * Open / short test controller for four power rails (VDD1, VDD2H, VDD2L, VDDQ).
 * Sequentially enables each rail via G3VM relays and checks for
 * ground shorts or inter-rail shorts using ADC voltage readings.
 * Outputs a pass/fail result (0xC9 = pass, 0x9C = fail) after completing
 * all measurement phases.
 */
module os_ctrl
(
    input  wire                  clk            ,
    input  wire                  rst_n          ,

    input  wire                  os_start       ,  // Trigger start of OS test
    output reg                   os_done        ,  // OS test complete flag
    output reg  [31:0]           os_result      ,  // Test result: 4 x 8-bit pass/fail codes

    input  wire                  ad_done        ,  // ADC conversion done flag
    input  wire [15:0]           ADC_CH8_U      ,  // ADC channel 8 voltage (VDD2L rail sense)
    input  wire [15:0]           ADC_CH7_U      ,  // ADC channel 7 voltage (VDD1 rail sense)
    input  wire [15:0]           ADC_CH6_U      ,  // ADC channel 6 voltage (VDD2H rail sense)
    input  wire [15:0]           ADC_CH5_U      ,  // ADC channel 5 voltage (VDDQ rail sense)
    input  wire [15:0]           VDD2L_U        ,  // VDD2L current sense voltage
    input  wire [15:0]           VDDQ_U         ,  // VDDQ current sense voltage
    input  wire [15:0]           VDD2H_U        ,  // VDD2H current sense voltage
    input  wire [15:0]           VDD1_U         ,  // VDD1 current sense voltage

    output wire                  G3VM_K7_OS     ,  // Relay control: VDD2L
    output wire                  G3VM_K1_OS     ,  // Relay control: VDDQ
    output wire                  G3VM_K3_OS     ,  // Relay control: VDD2H
    output wire                  G3VM_K5_OS     ,  // Relay control: VDD1

    input  wire [15:0]           VDD2L_Uth      ,  // Threshold for VDD2L over-current
    input  wire [15:0]           VDDQ_Uth       ,  // Threshold for VDDQ over-current
    input  wire [15:0]           VDD2H_Uth      ,  // Threshold for VDD2H over-current
    input  wire [15:0]           VDD1_Uth       ,  // Threshold for VDD1 over-current

    input  wire [15:0]           ADC_CH5_Uth    ,  // Threshold for ADC_CH5 inter-rail short
    input  wire [15:0]           ADC_CH6_Uth    ,  // Threshold for ADC_CH6 inter-rail short
    input  wire [15:0]           ADC_CH7_Uth    ,  // Threshold for ADC_CH7 inter-rail short
    input  wire [15:0]           ADC_CH8_Uth       // Threshold for ADC_CH8 inter-rail short
);

    // --------------------------------------------------------
    // Parameters
    // --------------------------------------------------------
    localparam T_200MS   = 40000000;          // 200 ms @ 200 MHz (5 ns period)
    localparam COMP_TIME = 16;                // Number of ADC samples per measurement phase

    // One-hot state encoding (24 bits)
    localparam IDLE       = 24'b0000_0000_0000_0000_0000_0001;
    localparam S0         = 24'b0000_0000_0000_0000_0000_0010;  // Enable all relays
    localparam S1         = 24'b0000_0000_0000_0000_0000_0100;  // Measure ground short
    localparam S2         = 24'b0000_0000_0000_0000_0000_1000;  // Enable VDDQ relay only
    localparam S3         = 24'b0000_0000_0000_0000_0001_0000;  // Measure inter-rail short (VDDQ)
    localparam S4         = 24'b0000_0000_0000_0000_0010_0000;  // Enable VDD2H relay only
    localparam S5         = 24'b0000_0000_0000_0000_0100_0000;  // Measure inter-rail short (VDD2H)
    localparam S6         = 24'b0000_0000_0000_0000_1000_0000;  // Enable VDD1 relay only
    localparam S7         = 24'b0000_0000_0000_0001_0000_0000;  // Measure inter-rail short (VDD1)
    localparam S8         = 24'b0000_0000_0000_0010_0000_0000;  // Enable VDD2L relay only
    localparam S9         = 24'b0000_0000_0000_0100_0000_0000;  // Measure inter-rail short (VDD2L)

    // --------------------------------------------------------
    // Internal signals
    // --------------------------------------------------------
    reg  [23:0]          state_c;               // Current state
    reg  [23:0]          state_n;               // Next state

    // Edge detection / delay
    reg  [ 2:0]          os_start_d;
    reg  [ 2:0]          ad_done_d;
    wire                 os_start_rising = (os_start_d[1] == 1'b0) && (os_start_d[0] == 1'b1);
    wire                 ad_done_rising  = (ad_done_d[1]  == 1'b0) && (ad_done_d[0]  == 1'b1);
    reg                  ad_done_flag;

    // Ground-short detection flags
    reg                  VDD2L_OS_flag;
    reg                  VDDQ_OS_flag;
    reg                  VDD2H_OS_flag;
    reg                  VDD1_OS_flag;
    reg                  os_gnd_short_flag;     // High during ground-short measurement
    reg                  os_gnd_short_error;     // Latched error

    // Power-rail inter-short detection
    reg  [ 3:0]          os_pwr_short_flag;     // One-hot enable for which rail is being tested
    reg  [ 3:0]          os_pwr_short_r;        // Per-rail error flags
    reg                  os_pwr_short_error;     // Latched combined error

    // Relay control registers
    reg                  G3VM_K1_OS_r;
    reg                  G3VM_K3_OS_r;
    reg                  G3VM_K5_OS_r;
    reg                  G3VM_K7_OS_r;

    // Counters
    reg  [28:0]          cnt_200ms;
    wire                 add_cnt_200ms;
    wire                 end_cnt_200ms;
    reg  [28:0]          cnt_os_gnd_test;
    wire                 add_cnt_os_gnd_test;
    wire                 end_cnt_os_gnd_test;
    reg  [28:0]          cnt_os_pwr_test;
    wire                 add_cnt_os_pwr_test;
    wire                 end_cnt_os_pwr_test;

    // State transition control wires
    wire                 idle2zero;
    wire                 zero2one;
    wire                 one2two;
    wire                 one2idle;
    wire                 two2three;
    wire                 three2four;
    wire                 four2five;
    wire                 five2six;
    wire                 six2seven;
    wire                 seven2eight;
    wire                 eight2nine;
    wire                 nine2idle;

    // Debug ASCII state display
    reg  [111:0]         ASCII_STC;

    // --------------------------------------------------------
    // Relay output assignments
    // --------------------------------------------------------
    assign G3VM_K1_OS = G3VM_K1_OS_r;
    assign G3VM_K3_OS = G3VM_K3_OS_r;
    assign G3VM_K5_OS = G3VM_K5_OS_r;
    assign G3VM_K7_OS = G3VM_K7_OS_r;

    // --------------------------------------------------------
    // Input synchronizer and edge detection
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            os_start_d <= 3'd0;
        else
            os_start_d <= {os_start_d[1:0], os_start};
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ad_done_d <= 3'd0;
        else
            ad_done_d <= {ad_done_d[1:0], ad_done};
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ad_done_flag <= 1'b0;
        else if (ad_done_rising)
            ad_done_flag <= 1'b1;
        else
            ad_done_flag <= 1'b0;
    end

    // --------------------------------------------------------
    // Ground-short detection: each VDD rail current vs. threshold
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            VDD2L_OS_flag <= 1'b0;
        else if (!os_gnd_short_flag)
            VDD2L_OS_flag <= 1'b0;
        else if (os_gnd_short_flag && ad_done_flag &&
                 (VDD2L_U[14:0] > VDD2L_Uth) && (VDD2L_U[15] == 1'b0))
            VDD2L_OS_flag <= 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            VDDQ_OS_flag <= 1'b0;
        else if (!os_gnd_short_flag)
            VDDQ_OS_flag <= 1'b0;
        else if (os_gnd_short_flag && ad_done_flag &&
                 (VDDQ_U[14:0] > VDDQ_Uth) && (VDDQ_U[15] == 1'b0))
            VDDQ_OS_flag <= 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            VDD2H_OS_flag <= 1'b0;
        else if (!os_gnd_short_flag)
            VDD2H_OS_flag <= 1'b0;
        else if (os_gnd_short_flag && ad_done_flag &&
                 (VDD2H_U[14:0] > VDD2H_Uth) && (VDD2H_U[15] == 1'b0))
            VDD2H_OS_flag <= 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            VDD1_OS_flag <= 1'b0;
        else if (!os_gnd_short_flag)
            VDD1_OS_flag <= 1'b0;
        else if (os_gnd_short_flag && ad_done_flag &&
                 (VDD1_U[14:0] > VDD1_Uth) && (VDD1_U[15] == 1'b0))
            VDD1_OS_flag <= 1'b1;
    end

    // Combine ground short errors
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            os_gnd_short_error <= 1'b0;
        else if (os_start_rising)
            os_gnd_short_error <= 1'b0;
        else if (VDD1_OS_flag || VDD2H_OS_flag || VDD2L_OS_flag || VDDQ_OS_flag)
            os_gnd_short_error <= 1'b1;
    end

    // --------------------------------------------------------
    // Inter-rail short detection
    // --------------------------------------------------------
    // Test 1: VDDQ active (K1), check ADC_CH6/7/8 against thresholds
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            os_pwr_short_r[0] <= 1'b0;
        else if (os_pwr_short_flag == 4'd0)
            os_pwr_short_r[0] <= 1'b0;
        else if (os_pwr_short_flag[0] && ad_done_flag &&
                 ((ADC_CH6_U[14:0] > ADC_CH6_Uth) || (ADC_CH7_U[14:0] > ADC_CH7_Uth) ||
                  (ADC_CH8_U[14:0] > ADC_CH8_Uth)))
            os_pwr_short_r[0] <= 1'b1;
    end

    // Test 2: VDD2H active (K3), check ADC_CH5/7/8
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            os_pwr_short_r[1] <= 1'b0;
        else if (os_pwr_short_flag == 4'd0)
            os_pwr_short_r[1] <= 1'b0;
        else if (os_pwr_short_flag[1] && ad_done_flag &&
                 ((ADC_CH5_U[14:0] > ADC_CH5_Uth) || (ADC_CH7_U[14:0] > ADC_CH7_Uth) ||
                  (ADC_CH8_U[14:0] > ADC_CH8_Uth)))
            os_pwr_short_r[1] <= 1'b1;
    end

    // Test 3: VDD1 active (K5), check ADC_CH5/6/8
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            os_pwr_short_r[2] <= 1'b0;
        else if (os_pwr_short_flag == 4'd0)
            os_pwr_short_r[2] <= 1'b0;
        else if (os_pwr_short_flag[2] && ad_done_flag &&
                 ((ADC_CH5_U[14:0] > ADC_CH5_Uth) || (ADC_CH6_U[14:0] > ADC_CH6_Uth) ||
                  (ADC_CH8_U[14:0] > ADC_CH8_Uth)))
            os_pwr_short_r[2] <= 1'b1;
    end

    // Test 4: VDD2L active (K7), check ADC_CH5/6/7
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            os_pwr_short_r[3] <= 1'b0;
        else if (os_pwr_short_flag == 4'd0)
            os_pwr_short_r[3] <= 1'b0;
        else if (os_pwr_short_flag[3] && ad_done_flag &&
                 ((ADC_CH5_U[14:0] > ADC_CH5_Uth) || (ADC_CH6_U[14:0] > ADC_CH6_Uth) ||
                  (ADC_CH7_U[14:0] > ADC_CH7_Uth)))
            os_pwr_short_r[3] <= 1'b1;
    end

    // Combine inter-rail short errors
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            os_pwr_short_error <= 1'b0;
        else if (os_start_rising)
            os_pwr_short_error <= 1'b0;
        else if (|os_pwr_short_r)
            os_pwr_short_error <= 1'b1;
    end

    // --------------------------------------------------------
    // State machine: synchronous state transition
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state_c <= IDLE;
        else
            state_c <= state_n;
    end

    // --------------------------------------------------------
    // Next state logic (combinational)
    // --------------------------------------------------------
    always @(*) begin
        case (state_c)
            IDLE : state_n = idle2zero ? S0 : state_c;
            S0   : state_n = zero2one  ? S1 : state_c;
            S1   : state_n = one2idle  ? IDLE :
                             one2two   ? S2 : state_c;
            S2   : state_n = two2three ? S3 : state_c;
            S3   : state_n = three2four? S4 : state_c;
            S4   : state_n = four2five ? S5 : state_c;
            S5   : state_n = five2six  ? S6 : state_c;
            S6   : state_n = six2seven ? S7 : state_c;
            S7   : state_n = seven2eight? S8 : state_c;
            S8   : state_n = eight2nine? S9 : state_c;
            S9   : state_n = nine2idle ? IDLE : state_c;
            default : state_n = IDLE;
        endcase
    end

    // State transition conditions
    assign idle2zero    = (state_c == IDLE) && os_start_rising;
    assign zero2one     = (state_c == S0)   && end_cnt_200ms;
    assign one2two      = (state_c == S1)   && end_cnt_os_gnd_test && !os_gnd_short_error;
    assign one2idle     = (state_c == S1)   && end_cnt_os_gnd_test &&  os_gnd_short_error;
    assign two2three    = (state_c == S2)   && end_cnt_200ms;
    assign three2four   = (state_c == S3)   && end_cnt_os_pwr_test;
    assign four2five    = (state_c == S4)   && end_cnt_200ms;
    assign five2six     = (state_c == S5)   && end_cnt_os_pwr_test;
    assign six2seven    = (state_c == S6)   && end_cnt_200ms;
    assign seven2eight  = (state_c == S7)   && end_cnt_os_pwr_test;
    assign eight2nine   = (state_c == S8)   && end_cnt_200ms;
    assign nine2idle    = (state_c == S9)   && end_cnt_os_pwr_test;

    // --------------------------------------------------------
    // Output logic (Mealy-style, registered)
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            G3VM_K1_OS_r        <= 1'b1;  // Off
            G3VM_K3_OS_r        <= 1'b1;
            G3VM_K5_OS_r        <= 1'b1;
            G3VM_K7_OS_r        <= 1'b1;
            os_gnd_short_flag   <= 1'b0;
            os_pwr_short_flag   <= 4'd0;
        end
        else begin
            case (state_c)
                IDLE: begin
                    G3VM_K1_OS_r        <= 1'b1;
                    G3VM_K3_OS_r        <= 1'b1;
                    G3VM_K5_OS_r        <= 1'b1;
                    G3VM_K7_OS_r        <= 1'b1;
                    os_gnd_short_flag   <= 1'b0;
                    os_pwr_short_flag   <= 4'd0;
                end
                S0: begin  // All relays ON
                    G3VM_K1_OS_r        <= 1'b0;
                    G3VM_K3_OS_r        <= 1'b0;
                    G3VM_K5_OS_r        <= 1'b0;
                    G3VM_K7_OS_r        <= 1'b0;
                end
                S1: begin  // Measure ground short
                    os_gnd_short_flag   <= 1'b1;
                end
                S2: begin  // VDDQ only
                    os_gnd_short_flag   <= 1'b0;
                    G3VM_K1_OS_r        <= 1'b0;
                    G3VM_K3_OS_r        <= 1'b1;
                    G3VM_K5_OS_r        <= 1'b1;
                    G3VM_K7_OS_r        <= 1'b1;
                end
                S3: begin
                    os_pwr_short_flag   <= 4'b0001;  // Test VDDQ rail
                end
                S4: begin  // VDD2H only
                    os_pwr_short_flag   <= 4'b0000;
                    G3VM_K1_OS_r        <= 1'b1;
                    G3VM_K3_OS_r        <= 1'b0;
                    G3VM_K5_OS_r        <= 1'b1;
                    G3VM_K7_OS_r        <= 1'b1;
                end
                S5: begin
                    os_pwr_short_flag   <= 4'b0010;  // Test VDD2H rail
                end
                S6: begin  // VDD1 only
                    os_pwr_short_flag   <= 4'b0000;
                    G3VM_K1_OS_r        <= 1'b1;
                    G3VM_K3_OS_r        <= 1'b1;
                    G3VM_K5_OS_r        <= 1'b0;
                    G3VM_K7_OS_r        <= 1'b1;
                end
                S7: begin
                    os_pwr_short_flag   <= 4'b0100;  // Test VDD1 rail
                end
                S8: begin  // VDD2L only
                    os_pwr_short_flag   <= 4'b0000;
                    G3VM_K1_OS_r        <= 1'b1;
                    G3VM_K3_OS_r        <= 1'b1;
                    G3VM_K5_OS_r        <= 1'b1;
                    G3VM_K7_OS_r        <= 1'b0;
                end
                S9: begin
                    os_pwr_short_flag   <= 4'b1000;  // Test VDD2L rail
                end
                default: begin
                    G3VM_K1_OS_r        <= G3VM_K1_OS_r;
                    G3VM_K3_OS_r        <= G3VM_K3_OS_r;
                    G3VM_K5_OS_r        <= G3VM_K5_OS_r;
                    G3VM_K7_OS_r        <= G3VM_K7_OS_r;
                    os_gnd_short_flag   <= os_gnd_short_flag;
                    os_pwr_short_flag   <= os_pwr_short_flag;
                end
            endcase
        end
    end

    // --------------------------------------------------------
    // Counters
    // --------------------------------------------------------
    // 200 ms delay counter (used in S0, S2, S4, S6, S8)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cnt_200ms <= 29'd0;
        else if (add_cnt_200ms) begin
            if (end_cnt_200ms)
                cnt_200ms <= 29'd0;
            else
                cnt_200ms <= cnt_200ms + 29'd1;
        end
    end
    assign add_cnt_200ms = (state_c == S0) || (state_c == S2) || (state_c == S4) ||
                           (state_c == S6) || (state_c == S8);
    assign end_cnt_200ms = add_cnt_200ms && (cnt_200ms >= T_200MS - 1);

    // Ground-short measurement counter (S1)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cnt_os_gnd_test <= 29'd0;
        else if (add_cnt_os_gnd_test) begin
            if (end_cnt_os_gnd_test)
                cnt_os_gnd_test <= 29'd0;
            else
                cnt_os_gnd_test <= cnt_os_gnd_test + 29'd1;
        end
    end
    assign add_cnt_os_gnd_test = (state_c == S1);
    assign end_cnt_os_gnd_test = add_cnt_os_gnd_test && (cnt_os_gnd_test >= COMP_TIME * 430 - 1);

    // Power-rail short measurement counter (S3, S5, S7, S9)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cnt_os_pwr_test <= 29'd0;
        else if (add_cnt_os_pwr_test) begin
            if (end_cnt_os_pwr_test)
                cnt_os_pwr_test <= 29'd0;
            else
                cnt_os_pwr_test <= cnt_os_pwr_test + 29'd1;
        end
    end
    assign add_cnt_os_pwr_test = (state_c == S3) || (state_c == S5) ||
                                 (state_c == S7) || (state_c == S9);
    assign end_cnt_os_pwr_test = add_cnt_os_pwr_test && (cnt_os_pwr_test >= COMP_TIME * 430 - 1);

    // --------------------------------------------------------
    // Test completion and result
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            os_done <= 1'b0;
        else if (os_start_d[2] == 1'b0)
            os_done <= 1'b0;
        else if (one2idle || nine2idle)
            os_done <= 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            os_result <= 32'd0;
        else if (os_start_rising)
            os_result <= 32'd0;
        else if (os_done && (os_gnd_short_error || os_pwr_short_error))
            os_result <= {8'h9C, 8'h9C, 8'h9C, 8'h9C};   // Fail
        else if (os_done)
            os_result <= {8'hC9, 8'hC9, 8'hC9, 8'hC9};   // Pass
    end

    // --------------------------------------------------------
    // Debug: ASCII state name for simulation
    // --------------------------------------------------------
    always@(*) begin
        case (state_c)
            IDLE    : ASCII_STC = "IDLE      ";
            S0      : ASCII_STC = "S0        ";
            S1      : ASCII_STC = "S1        ";
            S2      : ASCII_STC = "S2        ";
            S3      : ASCII_STC = "S3        ";
            S4      : ASCII_STC = "S4        ";
            S5      : ASCII_STC = "S5        ";
            S6      : ASCII_STC = "S6        ";
            S7      : ASCII_STC = "S7        ";
            S8      : ASCII_STC = "S8        ";
            S9      : ASCII_STC = "S9        ";
            default : ASCII_STC = "OTHER     ";
        endcase
    end

    // --------------------------------------------------------
    // Integrated Logic Analyzer (ILA) debug instance
    // --------------------------------------------------------
// ila_1 ila1_os_ctrl (
//     .clk       (clk),                // input wire clk

//     .probe0    (ASCII_STC),          // input wire [111:0] probe0
//     .probe1    (os_result),          // input wire [31:0]  probe1
//     .probe2    (os_start_d),         // input wire [2:0]   probe2
//     .probe3    (os_done),            // input wire [0:0]   probe3
//     .probe4    (os_gnd_short_error), // input wire [0:0]   probe4
//     .probe5    (os_pwr_short_error), // input wire [0:0]   probe5
//     .probe6    (os_pwr_short_r),     // input wire [3:0]   probe6
//     .probe7    (os_gnd_short_flag),  // input wire [0:0]   probe7
//     .probe8    (os_pwr_short_flag),  // input wire [3:0]   probe8
//     .probe9    (G3VM_K1_OS_r),       // input wire [0:0]   probe9
//     .probe10   (G3VM_K3_OS_r),       // input wire [0:0]   probe10
//     .probe11   (G3VM_K5_OS_r),       // input wire [0:0]   probe11
//     .probe12   (G3VM_K7_OS_r),       // input wire [0:0]   probe12
//     .probe13   (ADC_CH8_U),          // input wire [15:0]  probe13
//     .probe14   (ADC_CH7_U),          // input wire [15:0]  probe14
//     .probe15   (ADC_CH6_U),          // input wire [15:0]  probe15
//     .probe16   (ADC_CH5_U),          // input wire [15:0]  probe16
//     .probe17   (VDD2L_U),            // input wire [15:0]  probe17
//     .probe18   (VDDQ_U),             // input wire [15:0]  probe18
//     .probe19   (VDD2H_U),            // input wire [15:0]  probe19
//     .probe20   (VDD1_U),             // input wire [15:0]  probe20
//     .probe21   (VDD2L_Uth),          // input wire [15:0]  probe21
//     .probe22   (VDDQ_Uth),           // input wire [15:0]  probe22
//     .probe23   (VDD2H_Uth),          // input wire [15:0]  probe23
//     .probe24   (VDD1_Uth),           // input wire [15:0]  probe24
//     .probe25   (ADC_CH5_Uth),        // input wire [15:0]  probe25
//     .probe26   (ADC_CH6_Uth),        // input wire [15:0]  probe26
//     .probe27   (ADC_CH7_Uth),        // input wire [15:0]  probe27
//     .probe28   (ADC_CH8_Uth),        // input wire [15:0]  probe28
//     .probe29   (VDD2L_OS_flag),      // input wire [0:0]   probe29
//     .probe30   (VDDQ_OS_flag),       // input wire [0:0]   probe30
//     .probe31   (VDD2H_OS_flag),      // input wire [0:0]   probe31
//     .probe32   (VDD1_OS_flag)        // input wire [0:0]   probe32
// );

endmodule
