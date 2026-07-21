`include "dram_driver_head.vh"

/**
 * bar07
 * Oscilloscope trigger and voltage threshold control register block.
 * Writes update threshold values and start the OS measurement;
 * reads return current thresholds, OS start flag, and measurement result.
 */
module bar07 (
    input  wire                 clk           ,
    input  wire                 rst_n         ,
    input  wire [  7:0]         sir_addr      ,
    input  wire                 sir_read      ,
    input  wire [ 95:0]         sir_wdat      ,
    input  wire                 sir_sel       ,
    output wire                 sir_dack      ,
    output wire [ 95:0]         sir_rdat      ,

    output reg                  os_start      ,
    input  wire                 os_done       ,
    input  wire [ 31:0]         os_result     ,
    output reg  [ 15:0]         vdd2l_uth     ,
    output reg  [ 15:0]         vddq_uth      ,
    output reg  [ 15:0]         vdd2h_uth     ,
    output reg  [ 15:0]         vdd1_uth      ,
    output reg  [ 15:0]         adc_ch5_uth   ,
    output reg  [ 15:0]         adc_ch6_uth   ,
    output reg  [ 15:0]         adc_ch7_uth   ,
    output reg  [ 15:0]         adc_ch8_uth
);

    reg [95:0] sir_rdat_next;

    // --------------------------------------------------------
    // Control and threshold registers
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            os_start    <= 1'b0;
            vdd2l_uth   <= 16'h0D00;
            vddq_uth    <= 16'h0D00;
            vdd2h_uth   <= 16'h0D00;
            vdd1_uth    <= 16'h0D00;
            adc_ch5_uth <= 16'h0D00;
            adc_ch6_uth <= 16'h0D00;
            adc_ch7_uth <= 16'h1400;
            adc_ch8_uth <= 16'h0D00;
        end
        else if (os_done) begin
            os_start <= 1'b0;
        end
        else if (sir_sel && !sir_read) begin
            case (sir_addr)
                `bar07_OS_CTRL: os_start <= sir_wdat[0];
                `bar07_VDD_THRESHOLD: begin
                    vdd2l_uth <= sir_wdat[15:0];
                    vddq_uth  <= sir_wdat[31:16];
                    vdd2h_uth <= sir_wdat[47:32];
                    vdd1_uth  <= sir_wdat[63:48];
                end
                `bar07_ADC_THRESHOLD: begin
                    adc_ch5_uth <= sir_wdat[15:0];
                    adc_ch6_uth <= sir_wdat[31:16];
                    adc_ch7_uth <= sir_wdat[47:32];
                    adc_ch8_uth <= sir_wdat[63:48];
                end
                default: ;
            endcase
        end
    end

    // --------------------------------------------------------
    // Read data multiplexer
    // --------------------------------------------------------
    always_comb begin
        case (sir_addr)
            `bar07_OS_CTRL:       sir_rdat_next = {95'h0, os_start};
            `bar07_VDD_THRESHOLD: sir_rdat_next = {32'h0, vdd1_uth, vdd2h_uth, vddq_uth, vdd2l_uth};
            `bar07_ADC_THRESHOLD: sir_rdat_next = {32'h0, adc_ch8_uth, adc_ch7_uth, adc_ch6_uth, adc_ch5_uth};
            `bar07_OS_RESULT:     sir_rdat_next = {64'h0, os_result};
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
