// ***************************************************************************************
// Filename        :    protocol_ctrl.sv
// Author          :    yuxiaodong
// Date            :    2026.03.03
// Description     :    UART protocol controller for EFT system.
//                      Handles packet framing, CRC/ADD8 check, SIR bus access,
//                      and remote update frame support.
// ***************************************************************************************

module protocol_ctrl (
    input  wire                sys_clk_i          ,  // 200 MHz
    input  wire                sys_rstn_i         ,  // Active-low reset

    // UART RX
    input  wire [ 7:0]         rx_data_i          ,
    input  wire                rx_wren_i          ,

    // UART TX
    output logic               txfifo_wren_o      ,
    output logic [ 7:0]        txfifo_data_o      ,

    // RSU bus (remote update)
    output logic               rsu_bus_wenb       ,
    output logic [ 7:0]        rsu_bus_wdat       ,

    // SIR register bus
    output logic               sir_sel            ,
    output logic [15:0]        sir_addr           ,
    output logic               sir_read           ,
    output logic [95:0]        sir_wdat           ,
    input  wire  [95:0]        sir_rdat           ,
    input  wire                sir_dack
);

    // --------------------------------------------------------
    // Local parameters
    // --------------------------------------------------------
    localparam FRAME_4KB         = 15'd4096;
    localparam FRAME_1KB         = 11'd1024;
    localparam FRAME_512B        = 10'd512;
    localparam FRAME_12B         =  4'd12;

    localparam FH1               = 8'hAA;       // Frame header 1
    localparam FH2               = 8'h55;       // Frame header 2
    localparam FE1               = 8'h55;       // Frame end   1
    localparam FE2               = 8'hAA;       // Frame end   2
    localparam R_FLAG            = 8'h66;       // Read flag
    localparam W_FLAG            = 8'h77;       // Write flag
    localparam RIGHT_RT          = 8'h88;       // Correct status
    localparam ERROR_RT          = 8'h99;       // Error   status
    localparam LONG_FRAME_ADDR   = 16'h0005;    // Address that triggers long (4KB) frame

    localparam CMD_WRITE         = 1'b1;
    localparam CMD_READ          = 1'b0;

    localparam TIMEOUT           = 5'h1f;       // 16 clocks no dack -> address error

    // --------------------------------------------------------
    // Finite state machine type definitions
    // --------------------------------------------------------
    typedef enum logic [5:0] {
        RX_HEAD1        ,
        RX_HEAD2        ,
        RX_CS           ,
        RX_R_W          ,
        RX_ADDR1        ,
        RX_ADDR2        ,
        RX_DATA_12B     ,
        RX_DATA_4KB     ,
        RX_4K_NUM_1     ,
        RX_4K_NUM_2     ,
        RX_CHECK1       ,
        RX_CHECK2       ,
        RX_END1_ADD8    ,
        RX_END1_CRC16   ,
        RX_END2         ,
        RX_ADD8_ERR     ,
        RX_CRC16_ERR    ,
        RX_WAIT_TX
    } rx_fsm_t;

    typedef enum logic [5:0] {
        TX_IDLE         ,
        TX_HEAD1        ,
        TX_HEAD2        ,
        TX_CS           ,
        TX_RT           ,
        TX_ADDR1        ,
        TX_ADDR2        ,
        TX_DATA_12B     ,
        TX_DATA_1KB     ,
        TX_DATA_512B    ,
        TX_CHECK1       ,
        TX_CHECK2       ,
        TX_END1         ,
        TX_END2
    } tx_fsm_t;

    // --------------------------------------------------------
    // Internal signals
    // --------------------------------------------------------
    rx_fsm_t        rx_state_c         ;
    rx_fsm_t        rx_state_n         ;
    tx_fsm_t        tx_state_c         ;
    tx_fsm_t        tx_state_n         ;

    logic           rx_wren_r          ;
    logic [ 7:0]    rx_cs              ;
    logic [ 7:0]    rx_cs_r            ;
    logic           rx_rw              ;
    logic [ 7:0]    rx_addr1           ;
    logic [ 7:0]    rx_addr2           ;

    logic [ 7:0]    rx_12b_data [11:0] ;
    logic [ 7:0]    rx_add8            ;
    logic [ 7:0]    rx_add8_r          ;
    logic           rx_add8_err        ;
    logic [15:0]    rx_crc16           ;
    logic [15:0]    rx_crc16_r         ;
    logic           rx_crc16_err       ;
    logic [ 3:0]    rx_12_data_cnt     ;
    logic [14:0]    rx_4k_data_cnt     ;
    logic           rx_4K_flag         ;  // 1: 4KB frame active

    // ADD8 calculation
    logic [ 7:0]    rx_add_in          ;
    logic [ 7:0]    rx_add_data        ;
    logic [ 7:0]    rx_add_out         ;

    // CRC16 calculation
    logic [15:0]    rx_crc_in          ;
    logic [ 7:0]    rx_crc_data        ;
    logic [15:0]    rx_crc_out         ;

    logic           tx_end             ;
    logic [ 4:0]    timeout_cnt        ;

    // --------------------------------------------------------
    // Combinational functions
    // --------------------------------------------------------
    function automatic logic [7:0] add8 (
        input logic [7:0] a,
        input logic [7:0] b
    );
        logic [7:0] sum;
        logic       carry = 1'b0;
        for (int i = 0; i < 8; i++) begin
            logic bit_sum   =  a[i] ^ b[i]  ^  carry;
            logic bit_carry = (a[i] & b[i]) | (a[i] & carry) | (b[i] & carry);
            sum[i] = bit_sum;
            carry  = bit_carry;
        end
        return sum;
    endfunction

    function automatic logic [15:0] crc16_modbus (
        input logic [15:0] crcIn,
        input logic [ 7:0] data
    );
        logic [15:0] crcOut;
        crcOut[15] = ^{crcIn[7:0],           data        };
        crcOut[14] = ^{crcIn[6:0],           data[6:0]   };
        crcOut[13] = ^{crcIn[7:6],           data[7:6]   };
        crcOut[12] = ^{crcIn[6:5],           data[6:5]   };
        crcOut[11] = ^{crcIn[5:4],           data[5:4]   };
        crcOut[10] = ^{crcIn[4:3],           data[4:3]   };
        crcOut[9]  = ^{crcIn[3:2],           data[3:2]   };
        crcOut[8]  = ^{crcIn[2:1],           data[2:1]   };
        crcOut[7]  = ^{crcIn[15], crcIn[1:0], data[1:0] };
        crcOut[6]  = ^{crcIn[14], crcIn[0],   data[0]    };
        crcOut[5]  =   crcIn[13]                           ;
        crcOut[4]  =   crcIn[12]                           ;
        crcOut[3]  =   crcIn[11]                           ;
        crcOut[2]  =   crcIn[10]                           ;
        crcOut[1]  =   crcIn[9]                            ;
        crcOut[0]  = ^{crcIn[8:0],           data        };
        return crcOut;
    endfunction

    // ================================================================
    //  RX State Machine
    // ================================================================
    always_ff @(posedge sys_clk_i or negedge sys_rstn_i) begin
        if (!sys_rstn_i)
            rx_state_c <= RX_HEAD1;
        else
            rx_state_c <= rx_state_n;
    end

    always_comb begin
        rx_state_n = RX_HEAD1;
        case (rx_state_c)
            RX_HEAD1:
                if ((rx_data_i inside {FH1}) && rx_wren_i)
                    rx_state_n = RX_HEAD2;
                else
                    rx_state_n = rx_state_c;
            RX_HEAD2:
                if (rx_wren_i)
                    rx_state_n = (rx_data_i inside {FH2}) ? RX_CS : RX_HEAD1;
                else
                    rx_state_n = rx_state_c;
            RX_CS:
                if (rx_wren_i)
                    rx_state_n = (rx_data_i inside {[0:8]}) ? RX_R_W : RX_HEAD1;
                else
                    rx_state_n = rx_state_c;
            RX_R_W:
                if (rx_wren_i)
                    rx_state_n = ((rx_data_i inside {R_FLAG, W_FLAG})) ? RX_ADDR1 : RX_HEAD1;
                else
                    rx_state_n = rx_state_c;
            RX_ADDR1:
                if (rx_wren_i)
                    rx_state_n = RX_ADDR2;
                else
                    rx_state_n = rx_state_c;
            RX_ADDR2:
                if (rx_wren_i && ((rx_data_i != LONG_FRAME_ADDR[15:8]) || (rx_addr1 != LONG_FRAME_ADDR[7:0])))
                    rx_state_n = RX_DATA_12B;
                else if (rx_wren_i && (rx_data_i == LONG_FRAME_ADDR[15:8]) && (rx_addr1 == LONG_FRAME_ADDR[7:0]))
                    rx_state_n = RX_DATA_4KB;
                else
                    rx_state_n = rx_state_c;
            RX_DATA_12B:
                if (rx_wren_i && (rx_12_data_cnt == FRAME_12B - 1))
                    rx_state_n = RX_CHECK1;
                else
                    rx_state_n = rx_state_c;
            RX_DATA_4KB:
                if (rx_wren_i && (rx_4k_data_cnt == FRAME_4KB - 1))
                    rx_state_n = RX_4K_NUM_1;
                else
                    rx_state_n = rx_state_c;
            RX_4K_NUM_1:
                if (rx_wren_i)
                    rx_state_n = RX_4K_NUM_2;
                else
                    rx_state_n = rx_state_c;
            RX_4K_NUM_2:
                if (rx_wren_i)
                    rx_state_n = RX_CHECK1;
                else
                    rx_state_n = rx_state_c;
            RX_CHECK1:
                if (rx_wren_i)
                    rx_state_n = RX_CHECK2;
                else
                    rx_state_n = rx_state_c;
            RX_CHECK2:
                if (rx_wren_i)
                    rx_state_n = rx_4K_flag ? RX_END1_CRC16 : RX_END1_ADD8;
                else
                    rx_state_n = rx_state_c;
            RX_END1_ADD8:
                if (rx_wren_i && (rx_data_i inside {FE1}) && (rx_add8 == rx_add8_r))
                    rx_state_n = RX_END2;
                else if (rx_wren_i && (rx_data_i inside {FE1}) && (rx_add8 != rx_add8_r))
                    rx_state_n = RX_ADD8_ERR;
                else
                    rx_state_n = rx_state_c;
            RX_END1_CRC16:
                if (rx_wren_i && (rx_data_i inside {FE1}) && (rx_crc16 == rx_crc16_r))
                    rx_state_n = RX_END2;
                else if (rx_wren_i && (rx_data_i inside {FE1}) && (rx_crc16 != rx_crc16_r))
                    rx_state_n = RX_CRC16_ERR;
                else
                    rx_state_n = rx_state_c;
            RX_END2:
                if (rx_wren_i)
                    rx_state_n = RX_WAIT_TX;
                else
                    rx_state_n = rx_state_c;
            RX_ADD8_ERR,
            RX_CRC16_ERR:
                if (rx_wren_i)
                    rx_state_n = RX_WAIT_TX;
                else
                    rx_state_n = rx_state_c;
            RX_WAIT_TX:
                if (tx_end)
                    rx_state_n = RX_HEAD1;
                else
                    rx_state_n = rx_state_c;
            default:
                rx_state_n = RX_HEAD1;
        endcase
    end

    // --------------------------------------------------------
    // RX path register updates
    // --------------------------------------------------------
    always_ff @(posedge sys_clk_i or negedge sys_rstn_i) begin
        if (!sys_rstn_i)
            rx_wren_r <= 1'b0;
        else
            rx_wren_r <= rx_wren_i;
    end

    always_ff @(posedge sys_clk_i or negedge sys_rstn_i) begin
        if (!sys_rstn_i)
            rx_cs <= 8'd3;
        else if ((rx_state_c inside {RX_CS}) && rx_wren_i)
            rx_cs <= rx_data_i;
        else
            rx_cs <= rx_cs;
    end

    always_ff @(posedge sys_clk_i or negedge sys_rstn_i) begin
        if (!sys_rstn_i)
            rx_cs_r <= 8'd3;
        else if ((rx_state_c inside {RX_CHECK1}) && ({rx_addr1, rx_addr2} == '0))
            rx_cs_r <= rx_cs;
        else
            rx_cs_r <= rx_cs_r;
    end

    always_ff @(posedge sys_clk_i or negedge sys_rstn_i) begin
        if (!sys_rstn_i)
            rx_rw <= CMD_READ;
        else if (tx_end)
            rx_rw <= CMD_READ;
        else if (rx_wren_i && (rx_state_c inside {RX_R_W}) && (rx_data_i inside {R_FLAG}))
            rx_rw <= CMD_READ;
        else if (rx_wren_i && (rx_state_c inside {RX_R_W}) && (rx_data_i inside {W_FLAG}))
            rx_rw <= CMD_WRITE;
        else
            rx_rw <= rx_rw;
    end

    always_ff @(posedge sys_clk_i or negedge sys_rstn_i) begin
        if (!sys_rstn_i)
            rx_addr1 <= '0;
        else if (rx_wren_i && (rx_state_c inside {RX_ADDR1}))
            rx_addr1 <= rx_data_i;
        else
            rx_addr1 <= rx_addr1;
    end

    always_ff @(posedge sys_clk_i or negedge sys_rstn_i) begin
        if (!sys_rstn_i)
            rx_addr2 <= '0;
        else if (rx_wren_i && (rx_state_c inside {RX_ADDR2}))
            rx_addr2 <= rx_data_i;
        else
            rx_addr2 <= rx_addr2;
    end

    // --------------------------------------------------------
    // 12-byte data counter
    // --------------------------------------------------------
    always_ff @(posedge sys_clk_i or negedge sys_rstn_i) begin
        if (!sys_rstn_i)
            rx_12_data_cnt <= '0;
        else if (rx_state_c != RX_DATA_12B)
            rx_12_data_cnt <= '0;
        else if (rx_wren_i && (rx_state_c inside {RX_DATA_12B}))
            rx_12_data_cnt <= rx_12_data_cnt + 1'b1;
        else
            rx_12_data_cnt <= rx_12_data_cnt;
    end

    // --------------------------------------------------------
    // ADD8 checksum calculation (RX side)
    // --------------------------------------------------------
    always_ff @(posedge sys_clk_i or negedge sys_rstn_i) begin
        if (!sys_rstn_i)
            rx_add_in <= '0;
        else
            case (rx_state_c)
                RX_CS       : rx_add_in <= '0;
                RX_R_W,
                RX_ADDR1,
                RX_ADDR2,
                RX_DATA_12B : rx_add_in <= rx_wren_i ? rx_add_out : rx_add_in;
                default     : rx_add_in <= rx_add_in;
            endcase
    end

    always_ff @(posedge sys_clk_i or negedge sys_rstn_i) begin
        if (!sys_rstn_i)
            rx_add_data <= '0;
        else
            case (rx_state_c)
                RX_CS       : rx_add_data <= rx_wren_i ? rx_data_i : rx_add_data;
                RX_R_W,
                RX_ADDR1,
                RX_ADDR2,
                RX_DATA_12B : rx_add_data <= rx_wren_i ? rx_data_i : rx_add_data;
                default     : rx_add_data <= rx_add_data;
            endcase
    end

    always_comb begin
        rx_add_out = add8(rx_add_in, rx_add_data);
    end

    always_ff @(posedge sys_clk_i or negedge sys_rstn_i) begin
        if (!sys_rstn_i)
            rx_add8 <= '0;
        else if (rx_wren_i && (rx_state_c inside {RX_CHECK1}))
            rx_add8 <= rx_data_i;
        else
            rx_add8 <= rx_add8;
    end

    always_ff @(posedge sys_clk_i or negedge sys_rstn_i) begin
        if (!sys_rstn_i)
            rx_add8_r <= '0;
        else if (rx_state_c inside {RX_CHECK1})
            rx_add8_r <= rx_wren_i ? rx_add_out : rx_add8_r;
        else
            rx_add8_r <= rx_add8_r;
    end

    always_ff @(posedge sys_clk_i or negedge sys_rstn_i) begin
        if (!sys_rstn_i)
            rx_add8_err <= '0;
        else if (tx_state_c inside {TX_END2})
            rx_add8_err <= '0;
        else if ((rx_state_c inside {RX_ADD8_ERR}) || (timeout_cnt == TIMEOUT))
            rx_add8_err <= '1;
        else
            rx_add8_err <= rx_add8_err;
    end

    // --------------------------------------------------------
    // Store received 12-byte data payload
    // --------------------------------------------------------
    generate
        for (genvar i = 0; i < 12; i++) begin : rx_12b_data_store
            always_ff @(posedge sys_clk_i or negedge sys_rstn_i) begin
                if (!sys_rstn_i)
                    rx_12b_data[i] <= '0;
                else if ((rx_wren_i == 1'b1) && (rx_rw inside {CMD_WRITE}) &&
                         (rx_state_c inside {RX_DATA_12B}) && (rx_12_data_cnt == i))
                    rx_12b_data[i] <= rx_data_i;
                else
                    rx_12b_data[i] <= rx_12b_data[i];
            end
        end
    endgenerate

    // ================================================================
    //  Remote update frame support (4KB data)
    // ================================================================
    always_ff @(posedge sys_clk_i or negedge sys_rstn_i) begin
        if (!sys_rstn_i)
            rx_4K_flag <= 1'b0;
        else if (tx_end)
            rx_4K_flag <= 1'b0;
        else if (rx_state_c == RX_DATA_4KB)
            rx_4K_flag <= 1'b1;
        else
            rx_4K_flag <= rx_4K_flag;
    end

    always_ff @(posedge sys_clk_i or negedge sys_rstn_i) begin
        if (!sys_rstn_i)
            rx_4k_data_cnt <= '0;
        else if (rx_state_c != RX_DATA_4KB)
            rx_4k_data_cnt <= '0;
        else if (rx_wren_i && (rx_state_c inside {RX_DATA_4KB}))
            rx_4k_data_cnt <= rx_4k_data_cnt + 1'b1;
        else
            rx_4k_data_cnt <= rx_4k_data_cnt;
    end

    // --------------------------------------------------------
    // CRC16 checksum calculation (for 4KB frame)
    // --------------------------------------------------------
    always_ff @(posedge sys_clk_i or negedge sys_rstn_i) begin
        if (!sys_rstn_i)
            rx_crc_in <= '1;
        else
            case (rx_state_c)
                RX_CS       : rx_crc_in <= 16'hFFFF;
                RX_R_W,
                RX_ADDR1,
                RX_ADDR2,
                RX_DATA_4KB,
                RX_4K_NUM_1,
                RX_4K_NUM_2 : rx_crc_in <= rx_wren_i ? rx_crc_out : rx_crc_in;
                default     : rx_crc_in <= rx_crc_in;
            endcase
    end

    always_ff @(posedge sys_clk_i or negedge sys_rstn_i) begin
        if (!sys_rstn_i)
            rx_crc_data <= '0;
        else
            case (rx_state_c)
                RX_CS       : rx_crc_data <= rx_wren_i ? rx_data_i : rx_crc_data;
                RX_R_W,
                RX_ADDR1,
                RX_ADDR2,
                RX_DATA_4KB,
                RX_4K_NUM_1,
                RX_4K_NUM_2 : rx_crc_data <= rx_wren_i ? rx_data_i : rx_crc_data;
                default     : rx_crc_data <= rx_crc_data;
            endcase
    end

    always_comb begin
        rx_crc_out = crc16_modbus(rx_crc_in, rx_crc_data);
    end

    always_ff @(posedge sys_clk_i or negedge sys_rstn_i) begin
        if (!sys_rstn_i)
            rx_crc16 <= '0;
        else if (rx_wren_i)
            case (rx_state_c)
                RX_CHECK1 : rx_crc16 <= {rx_crc16[15:8], rx_data_i};
                RX_CHECK2 : rx_crc16 <= {rx_data_i, rx_crc16[7:0]};
                default   : rx_crc16 <= rx_crc16;
            endcase
        else
            rx_crc16 <= rx_crc16;
    end

    always_ff @(posedge sys_clk_i or negedge sys_rstn_i) begin
        if (!sys_rstn_i)
            rx_crc16_r <= '0;
        else if (rx_state_c inside {RX_CHECK1})
            rx_crc16_r <= rx_wren_i ? rx_crc_out : rx_crc16_r;
        else
            rx_crc16_r <= rx_crc16_r;
    end

    always_ff @(posedge sys_clk_i or negedge sys_rstn_i) begin
        if (!sys_rstn_i)
            rx_crc16_err <= '0;
        else if (tx_end)
            rx_crc16_err <= '0;
        else if (rx_state_c inside {RX_CRC16_ERR})
            rx_crc16_err <= '1;
        else
            rx_crc16_err <= rx_crc16_err;
    end

    // --------------------------------------------------------
    // RSU bus write (remote update)
    // --------------------------------------------------------
    always_ff @(posedge sys_clk_i or negedge sys_rstn_i) begin
        if (!sys_rstn_i)
            rsu_bus_wenb <= '0;
        else
            rsu_bus_wenb <= ((rx_state_c == RX_DATA_4KB) && rx_wren_i);
    end

    always_ff @(posedge sys_clk_i) begin
        if (!sys_rstn_i)
            rsu_bus_wdat <= '0;
        else if ((rx_state_c == RX_DATA_4KB) && rx_wren_i)
            rsu_bus_wdat <= rx_data_i;
        else
            rsu_bus_wdat <= rsu_bus_wdat;
    end

    // ================================================================
    //  Protocol to SIR bus conversion
    // ================================================================
    always_ff @(posedge sys_clk_i) begin
        sir_wdat <= {
            rx_12b_data[11], rx_12b_data[10], rx_12b_data[9], rx_12b_data[8],
            rx_12b_data[ 7], rx_12b_data[ 6], rx_12b_data[5], rx_12b_data[4],
            rx_12b_data[ 3], rx_12b_data[ 2], rx_12b_data[1], rx_12b_data[0]
        };
    end

    always_ff @(posedge sys_clk_i or negedge sys_rstn_i) begin
        if (!sys_rstn_i) begin
            sir_sel  <= 1'b0;
            sir_addr <= 16'h0;
            sir_read <= 1'b0;
        end
        else begin
            sir_sel  <= ((rx_wren_r == 1'b1) && (rx_state_c == RX_WAIT_TX)) ? 1'b1 : 1'b0;
            sir_addr <= ((rx_wren_r == 1'b1) && (rx_state_c == RX_WAIT_TX)) ? {rx_addr2, rx_addr1} : sir_addr;
            sir_read <= ((rx_wren_r == 1'b1) && (rx_state_c == RX_WAIT_TX)) ? (~rx_rw) : 1'b0;
        end
    end

    // --------------------------------------------------------
    // Timeout counter (SIR access acknowledge)
    // --------------------------------------------------------
    always_ff @(posedge sys_clk_i or negedge sys_rstn_i) begin
        if (!sys_rstn_i)
            timeout_cnt <= 5'h0;
        else if (tx_state_c == TX_HEAD1)
            timeout_cnt <= 5'h0;
        else if (rx_state_c == RX_WAIT_TX)
            if (sir_sel)
                timeout_cnt <= 5'h1;
            else
                timeout_cnt <= (timeout_cnt == 5'h0) ? timeout_cnt : (timeout_cnt + 5'h1);
        else
            timeout_cnt <= 5'h0;
    end

    // ================================================================
    //  TX State Machine
    // ================================================================
    logic           tx_fifo_wen_r      ;
    logic [ 7:0]    tx_fifo_data_r     ;
    logic [ 7:0]    tx_cs_r            ;
    logic [ 7:0]    tx_chk_res_r       ;
    logic [ 7:0]    tx_addr1_r         ;
    logic [ 7:0]    tx_addr2_r         ;
    logic [ 7:0]    tx_12b_data_r      ;
    logic [ 7:0]    tx_add_in          ;
    logic [ 7:0]    tx_add_data        ;
    logic [ 7:0]    tx_add_out         ;
    logic [ 3:0]    tx_12_data_cnt     ;

    logic [95:0]    sir_rdat_r;

    wire            tx_ack;

    assign tx_ack = (((sir_dack == 1'b1) || (sir_sel & rx_addr2[7]) || (timeout_cnt == TIMEOUT)) &&
                     (rx_state_c == RX_WAIT_TX));

    always_ff @(posedge sys_clk_i or negedge sys_rstn_i) begin
        if (!sys_rstn_i)
            tx_state_c <= TX_IDLE;
        else
            tx_state_c <= tx_state_n;
    end

    always_comb begin
        tx_state_n = TX_IDLE;
        case (tx_state_c)
            TX_IDLE     : tx_state_n = tx_ack ? TX_HEAD1 : tx_state_c;
            TX_HEAD1    : tx_state_n = TX_HEAD2;
            TX_HEAD2    : tx_state_n = TX_CS;
            TX_CS       : tx_state_n = TX_RT;
            TX_RT       : tx_state_n = TX_ADDR1;
            TX_ADDR1    : tx_state_n = TX_ADDR2;
            TX_ADDR2    : tx_state_n = TX_DATA_12B;
            TX_DATA_12B : tx_state_n = (tx_12_data_cnt == FRAME_12B) ? TX_CHECK1 : tx_state_c;
            TX_CHECK1   : tx_state_n = TX_CHECK2;
            TX_CHECK2   : tx_state_n = TX_END1;
            TX_END1     : tx_state_n = TX_END2;
            TX_END2     : tx_state_n = TX_IDLE;
            default     : tx_state_n = TX_IDLE;
        endcase
    end

    always_ff @(posedge sys_clk_i or negedge sys_rstn_i) begin
        if (!sys_rstn_i)
            tx_12_data_cnt <= '0;
        else if ((tx_state_c != TX_ADDR2) && (tx_state_c != TX_DATA_12B))
            tx_12_data_cnt <= '0;
        else if ((tx_state_c == TX_ADDR2) || (tx_state_c == TX_DATA_12B))
            tx_12_data_cnt <= tx_12_data_cnt + 1'b1;
        else
            tx_12_data_cnt <= tx_12_data_cnt;
    end

    // --------------------------------------------------------
    // Latch SIR read data on acknowledge
    // --------------------------------------------------------
    always_ff @(posedge sys_clk_i) begin
        if ((sir_dack == 1'b1) && (tx_state_c == TX_IDLE))
            if (rx_rw == CMD_READ)
                sir_rdat_r <= sir_rdat;
            else
                sir_rdat_r <= sir_wdat;
        else
            sir_rdat_r <= sir_rdat_r;
    end

    // --------------------------------------------------------
    // Map SIR data to 12-byte TX payload
    // --------------------------------------------------------
    always_ff @(posedge sys_clk_i or negedge sys_rstn_i) begin
        if (!sys_rstn_i)
            tx_12b_data_r <= '0;
        else if (!rx_add8_err && (rx_rw inside {CMD_WRITE}))
            case (tx_12_data_cnt)
                4'd0  : tx_12b_data_r <= sir_rdat_r[ 0+:8];
                4'd1  : tx_12b_data_r <= sir_rdat_r[ 8+:8];
                4'd2  : tx_12b_data_r <= sir_rdat_r[16+:8];
                4'd3  : tx_12b_data_r <= sir_rdat_r[24+:8];
                4'd4  : tx_12b_data_r <= sir_rdat_r[32+:8];
                4'd5  : tx_12b_data_r <= sir_rdat_r[40+:8];
                4'd6  : tx_12b_data_r <= sir_rdat_r[48+:8];
                4'd7  : tx_12b_data_r <= sir_rdat_r[56+:8];
                4'd8  : tx_12b_data_r <= sir_rdat_r[64+:8];
                4'd9  : tx_12b_data_r <= sir_rdat_r[72+:8];
                4'd10 : tx_12b_data_r <= sir_rdat_r[80+:8];
                4'd11 : tx_12b_data_r <= sir_rdat_r[88+:8];
                default : ;
            endcase
        else if (!rx_add8_err && (rx_rw inside {CMD_READ}))
            case (tx_12_data_cnt)
                4'd0  : tx_12b_data_r <= sir_rdat_r[ 0+:8];
                4'd1  : tx_12b_data_r <= sir_rdat_r[ 8+:8];
                4'd2  : tx_12b_data_r <= sir_rdat_r[16+:8];
                4'd3  : tx_12b_data_r <= sir_rdat_r[24+:8];
                4'd4  : tx_12b_data_r <= sir_rdat_r[32+:8];
                4'd5  : tx_12b_data_r <= sir_rdat_r[40+:8];
                4'd6  : tx_12b_data_r <= sir_rdat_r[48+:8];
                4'd7  : tx_12b_data_r <= sir_rdat_r[56+:8];
                4'd8  : tx_12b_data_r <= sir_rdat_r[64+:8];
                4'd9  : tx_12b_data_r <= sir_rdat_r[72+:8];
                4'd10 : tx_12b_data_r <= sir_rdat_r[80+:8];
                4'd11 : tx_12b_data_r <= sir_rdat_r[88+:8];
                default : ;
            endcase
        else
            tx_12b_data_r <= '0;
    end

    // --------------------------------------------------------
    // TX completion flag
    // --------------------------------------------------------
    always_ff @(posedge sys_clk_i or negedge sys_rstn_i) begin
        if (!sys_rstn_i)
            tx_end <= '0;
        else if (tx_state_c inside {TX_END2})
            tx_end <= '0;
        else if (tx_state_c inside {TX_END1})
            tx_end <= '1;
        else
            tx_end <= tx_end;
    end

    // --------------------------------------------------------
    // Copy RX fields to TX registers
    // --------------------------------------------------------
    always_ff @(posedge sys_clk_i) begin
        tx_cs_r    <= rx_cs_r;
        tx_addr1_r <= rx_addr1;
        tx_addr2_r <= rx_addr2;
    end

    // --------------------------------------------------------
    // TX response code (error or success)
    // --------------------------------------------------------
    always_ff @(posedge sys_clk_i or negedge sys_rstn_i) begin
        if (!sys_rstn_i)
            tx_chk_res_r <= RIGHT_RT;
        else if (tx_end)
            tx_chk_res_r <= RIGHT_RT;
        else if (rx_add8_err || rx_crc16_err)
            tx_chk_res_r <= ERROR_RT;
        else
            tx_chk_res_r <= tx_chk_res_r;
    end

    // --------------------------------------------------------
    // TX ADD8 checksum calculation
    // --------------------------------------------------------
    always_ff @(posedge sys_clk_i or negedge sys_rstn_i) begin
        if (!sys_rstn_i)
            tx_add_in <= '0;
        else
            case (tx_state_c)
                TX_CS       : tx_add_in <= '0;
                TX_RT,
                TX_ADDR1,
                TX_ADDR2,
                TX_DATA_12B : tx_add_in <= tx_add_out;
                default     : tx_add_in <= tx_add_in;
            endcase
    end

    always_ff @(posedge sys_clk_i or negedge sys_rstn_i) begin
        if (!sys_rstn_i)
            tx_add_data <= '0;
        else
            case (tx_state_c)
                TX_CS       : tx_add_data <= tx_cs_r;
                TX_RT       : tx_add_data <= tx_chk_res_r;
                TX_ADDR1    : tx_add_data <= tx_addr1_r;
                TX_ADDR2    : tx_add_data <= tx_addr2_r;
                TX_DATA_12B : tx_add_data <= tx_12b_data_r;
                default     : tx_add_data <= tx_add_data;
            endcase
    end

    always_comb begin
        tx_add_out = add8(tx_add_in, tx_add_data);
    end

    // --------------------------------------------------------
    // TX FIFO interface (drive UART TX)
    // --------------------------------------------------------
    always_ff @(posedge sys_clk_i or negedge sys_rstn_i) begin
        if (!sys_rstn_i)
            tx_fifo_wen_r <= '0;
        else
            case (tx_state_c) inside
                [TX_HEAD1:TX_END2] : tx_fifo_wen_r <= '1;
                default            : tx_fifo_wen_r <= '0;
            endcase
    end

    always_ff @(posedge sys_clk_i or negedge sys_rstn_i) begin
        if (!sys_rstn_i)
            tx_fifo_data_r <= '0;
        else
            case (tx_state_c)
                TX_HEAD1    : tx_fifo_data_r <= FH1;
                TX_HEAD2    : tx_fifo_data_r <= FH2;
                TX_CS       : tx_fifo_data_r <= tx_cs_r;
                TX_RT       : tx_fifo_data_r <= tx_chk_res_r;
                TX_ADDR1    : tx_fifo_data_r <= tx_addr1_r;
                TX_ADDR2    : tx_fifo_data_r <= tx_addr2_r;
                TX_DATA_12B : tx_fifo_data_r <= tx_12b_data_r;
                TX_CHECK1   : tx_fifo_data_r <= tx_add_out;
                TX_END1     : tx_fifo_data_r <= FE1;
                TX_END2     : tx_fifo_data_r <= FE2;
                default     : tx_fifo_data_r <= '0;
            endcase
    end

    always_ff @(posedge sys_clk_i) begin
        txfifo_wren_o <= tx_fifo_wen_r;
        txfifo_data_o <= tx_fifo_data_r;
    end

endmodule