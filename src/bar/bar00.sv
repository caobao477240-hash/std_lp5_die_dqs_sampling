`include "dram_driver_head.vh"

/**
 * bar00
 * Register 0x00: Configuration done latch and FPGA version readback.
 * Writes update the configuration done byte; reads return system information.
 */
module bar00 (
    input  wire                 clk           ,
    input  wire                 rst_n         ,
    input  wire [  7:0]         sir_addr      ,
    input  wire                 sir_read      ,
    input  wire [ 95:0]         sir_wdat      ,
    input  wire                 sir_sel       ,
    output wire                 sir_dack      ,
    output wire [ 95:0]         sir_rdat
);

    // --------------------------------------------------------
    // Configuration done register
    // --------------------------------------------------------
    reg [7:0] configure_done;
    reg [95:0] sir_rdat_next;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            configure_done <= 8'h00;
        end
        else if (sir_sel && !sir_read && (sir_addr == `bar00_SYSTEM_INFO)) begin
            configure_done <= sir_wdat[95:88];
        end
    end

    // --------------------------------------------------------
    // Read data mux
    // --------------------------------------------------------
    always @(*) begin
        case (sir_addr)
            `bar00_SYSTEM_INFO: sir_rdat_next = {configure_done, 24'h0, `FPGA_VERSION};
            default:                sir_rdat_next = 96'h0;
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
