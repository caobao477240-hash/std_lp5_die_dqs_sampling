`include "dram_driver_head.vh"

/**
 * bar04
 * DUT initialization, IDD6 measurement, and EFT test control register block.
 * Latches external status flags, generates init/IDD6/EFT test pulses, and
 * reports results back through the SIR read interface.
 */
module bar04 (
    input  wire                 clk               ,
    input  wire                 rst_n             ,
    input  wire [  7:0]         sir_addr          ,
    input  wire                 sir_read          ,
    input  wire [ 95:0]         sir_wdat          ,
    input  wire                 sir_sel           ,
    output wire                 sir_dack          ,
    output wire [ 95:0]         sir_rdat          ,

    output reg                  init_start        ,
    input  wire                 init_done         ,
    input  wire                 init_fail         ,
    input  wire [  7:0]         mr8_density       ,
    output reg                  idd6_start        ,
    input  wire                 idd6_done         ,
    input  wire [ 63:0]         idd6_result
);

    // --------------------------------------------------------
    // BAR04 request decode
    // --------------------------------------------------------
    wire write_cycle;
    wire write_init;
    wire write_idd6;

    assign write_cycle     = sir_sel && !sir_read;
    assign write_init      = write_cycle && (sir_addr == `bar04_INIT_CTRL);
    assign write_idd6      = write_cycle && (sir_addr == `bar04_IDD6_CTRL);

    // --------------------------------------------------------
    // Synchronized inputs and captured results
    // --------------------------------------------------------
    localparam [ 7:0]    INIT_STATUS_PASS  = 8'hC9;
    localparam [ 7:0]    INIT_STATUS_FAIL  = 8'h9C;

    reg  [ 7:0]         init_finish       ;
    reg  [ 7:0]         idd6_finish       ;
    reg  [ 7:0]         mr8_density_r     ;
    reg                 init_done_r       ;
    reg                 init_fail_r       ;
    reg                 idd6_done_r       ;
    reg  [63:0]         idd6_result_r     ;
    reg  [63:0]         idd6_info_reg     ;
    reg  [95:0]         sir_rdat_next     ;

    // --------------------------------------------------------
    // Input synchronization registers
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            init_done_r   <= 1'b0;
            init_fail_r   <= 1'b0;
            idd6_done_r   <= 1'b0;
            mr8_density_r <= 8'd0;
            idd6_result_r <= 64'd0;
        end
        else if (write_init) begin
            init_done_r   <= 1'b0;
            init_fail_r   <= 1'b0;
            idd6_done_r   <= idd6_done;
            mr8_density_r <= mr8_density;
            idd6_result_r <= idd6_result;
        end
        else begin
            init_done_r   <= init_done;
            init_fail_r   <= init_fail;
            idd6_done_r   <= idd6_done;
            mr8_density_r <= mr8_density;
            idd6_result_r <= idd6_result;
        end
    end

    // --------------------------------------------------------
    // Initialization start control
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            init_start <= 1'b0;
        else if (write_init && sir_wdat[0])
            init_start <= 1'b1;
        else
            init_start <= 1'b0;
    end

    // --------------------------------------------------------
    // IDD6 measurement start control
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            idd6_start <= 1'b0;
        else if (write_idd6)
            idd6_start <= sir_wdat[0];
        else if (idd6_done_r)
            idd6_start <= 1'b0;
    end

    // --------------------------------------------------------
    // Initialization result status
    // --------------------------------------------------------
    // C9: initialization completed; 9C: init-time RDC training failed.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            init_finish <= 8'd0;
        else if (write_init)
            init_finish <= 8'd0;
        else if (init_fail_r)
            init_finish <= INIT_STATUS_FAIL;
        else if (init_done_r)
            init_finish <= INIT_STATUS_PASS;
    end

    // --------------------------------------------------------
    // IDD6 result status and current-data capture
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            idd6_finish   <= 8'd0;
            idd6_info_reg <= 64'd0;
        end
        else if (write_idd6) begin
            idd6_finish   <= 8'd0;
            idd6_info_reg <= 64'd0;
        end
        else if (idd6_done_r) begin
            idd6_finish   <= 8'hc9;
            idd6_info_reg <= idd6_result_r;
        end
    end

    // --------------------------------------------------------
    // BAR04 read data decode
    // --------------------------------------------------------
    always_comb begin
        case (sir_addr)
            `bar04_INIT_CTRL:   sir_rdat_next = {95'h0, init_start};
            `bar04_INIT_RESULT: sir_rdat_next = {80'h0, mr8_density_r, init_finish};
            `bar04_IDD6_CTRL:   sir_rdat_next = {95'h0, idd6_start};
            `bar04_IDD6_RESULT: sir_rdat_next = {
                    40'h0,
                    idd6_info_reg[0  +: 16],
                    idd6_info_reg[16 +: 16],
                    idd6_info_reg[32 +: 16],
                    idd6_finish
                };
            default:              sir_rdat_next = 96'h0;
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
