/**
 * uart_bps_cfg
 * Baud rate configuration module using a phase accumulator.
 * Generates baud-rate-related edge signals (any edge, positive edge, negative edge).
 * Supports pre-computed frequency tuning words (FTW) for 9600, 115200, and 600000 bps
 * at a 200 MHz system clock. (100 MHz values provided as comments.)
 */
module uart_bps_cfg
#(
    parameter BPS_SEL = 32'd600000   // Supported: 9600, 115200, 600000
)
(
    input  logic       uart_clk_i    , // System clock (200 MHz)
    output logic       clk_bps_edg_o , // Baud clock edge (any transition)
    output logic       clk_bps_pdg_o , // Baud clock positive edge
    output logic       clk_bps_ndg_o   // Baud clock negative edge
);

    // --------------------------------------------------------
    // Internal signals
    // --------------------------------------------------------
    logic [31:0]       ftw           = '0;  // Frequency tuning word
    logic [31:0]       cnt           = '0;  // Phase accumulator
    logic              cnt_msb       = '0;  // MSB of accumulator (current)
    logic              cnt_msb_r0    = '0;  // MSB delayed by 1 cycle
    logic              cnt_msb_r1    = '0;  // MSB delayed by 2 cycles

    // --------------------------------------------------------
    // FTW lookup table
    // Formula: FTW = 2^32 * 16 * BPS_SEL / F_clk
    // For 200 MHz system clock:
    //    9600   -> 3,298,534
    //  115200   -> 39,582,418
    //  600000   -> 206,158,430
    // --------------------------------------------------------
    always_comb begin
        case (BPS_SEL)
            // 100 MHz values (commented out)
            // 32'd9600   : ftw = 32'd6_597_069;
            // 32'd115200 : ftw = 32'd79_164_837;
            // 32'd600000 : ftw = 32'd412_316_860;
            // default    : ftw = 32'd79164837;

            // 200 MHz values
            32'd9600   : ftw = 32'd3_298_534;
            32'd115200 : ftw = 32'd39_582_418;
            32'd600000 : ftw = 32'd206_158_430;
            default    : ftw = 32'd39_582_418;
        endcase
    end

    // --------------------------------------------------------
    // Phase accumulator and edge detection
    // --------------------------------------------------------
    always_ff @(posedge uart_clk_i) begin
        cnt          <= cnt + ftw;
        cnt_msb      <= cnt[31];
        cnt_msb_r0   <= cnt_msb;
        cnt_msb_r1   <= cnt_msb_r0;

        clk_bps_edg_o <= cnt_msb_r1 ^ cnt_msb_r0;      // Any edge
        clk_bps_pdg_o <= ~cnt_msb_r1 & cnt_msb_r0;     // Rising edge
        clk_bps_ndg_o <= cnt_msb_r1 & ~cnt_msb_r0;     // Falling edge
    end

endmodule