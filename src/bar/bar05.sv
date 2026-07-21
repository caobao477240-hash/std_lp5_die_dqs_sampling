`include "dram_driver_head.vh"

/**
 * bar05
 * GF test control and result aggregation.
 * Manages test start flag, algorithm parameters, and captures
 * algorithm info / bad-block info on test completion.
 */
module bar05 (
    input  wire                 clk                     ,
    input  wire                 rst_n                   ,
    input  wire [  7:0]         sir_addr                ,
    input  wire                 sir_read                ,
    input  wire [ 95:0]         sir_wdat                ,
    input  wire                 sir_sel                 ,
    output wire                 sir_dack                ,
    output wire [ 95:0]         sir_rdat                ,

    output reg                  gf_start                ,
    input  wire                 gf_done                 ,
    input  wire [ 95:0]         gf_result               ,
    input  wire [ 95:0]         gf_aux_result           ,
    input  wire [ 95:0]         gf_bad_block_info       ,
    input  wire [  7:0]         gf_bad_block_count      ,
    output reg  [ 15:0]         gf_clk_sel              ,
    output reg  [ 55:0]         gf_addr_start           ,
    output reg  [ 55:0]         gf_addr_end
);

    // --------------------------------------------------------
    // Internal signals
    // --------------------------------------------------------
    reg [95:0]          gf_result_reg         ;
    reg [95:0]          bad_block_info_reg    ;
    reg [ 7:0]          cnt_bad_block_reg     ;
    reg [95:0]          gf_result_r           ;
    reg [95:0]          bad_block_info_r      ;
    reg [ 7:0]          cnt_bad_block_r       ;
    reg                 gf_done_r             ;
    reg                 gf_done_r_1           ;
    reg                 gf_done_rise          ;
    reg [95:0]          sir_rdat_next         ;

    // --------------------------------------------------------
    // Output control registers (write commands & auto-clear)
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gf_start        <= 1'b0;
            gf_clk_sel      <= 16'd100;
            gf_addr_start   <= 56'd0;
            gf_addr_end     <= 56'hFF_FFFF_FFFF_FFFF;
        end
        else begin
            // Auto-clear GF start flag on test completion
            if (gf_done)
                gf_start <= 1'b0;

            // Write commands
            if (sir_sel && !sir_read) begin
                case (sir_addr)
                    `bar05_GF_CTRL:        gf_start        <= sir_wdat[0];
                    `bar05_CLK_SEL:        gf_clk_sel      <= sir_wdat[15:0];
                    `bar05_ALG_ADDR_START: gf_addr_start   <= sir_wdat[55:0];
                    `bar05_ALG_ADDR_END:   gf_addr_end     <= sir_wdat[55:0];
                    default: ;
                endcase
            end
        end
    end

    // --------------------------------------------------------
    // Rising-edge detection for GF done
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gf_done_r    <= 1'b0;
            gf_done_r_1  <= 1'b0;
            gf_done_rise <= 1'b0;
        end
        else begin
            gf_done_r   <= gf_done;
            gf_done_r_1 <= gf_done_r;

            if (!gf_done_r_1 && gf_done_r)
                gf_done_rise <= 1'b1;
            else
                gf_done_rise <= 1'b0;
        end
    end

    // --------------------------------------------------------
    // Input synchronization registers
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gf_result_r      <= 96'd0;
            bad_block_info_r <= 96'd0;
            cnt_bad_block_r  <= 8'd0;
        end
        else begin
            gf_result_r      <= gf_result;
            bad_block_info_r <= gf_bad_block_info;
            cnt_bad_block_r  <= gf_bad_block_count;
        end
    end

    // --------------------------------------------------------
    // Result registers (latched on test completion)
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gf_result_reg      <= 96'd0;
            bad_block_info_reg <= 96'd0;
            cnt_bad_block_reg  <= 8'd0;
        end
        else begin
            if (gf_start && !gf_done_r) begin
                // Clear results while a new test is in progress
                gf_result_reg      <= 96'd0;
                bad_block_info_reg <= 96'd0;
                cnt_bad_block_reg  <= 8'd0;
            end
            else begin
                // Continuously update GF result snapshot
                gf_result_reg <= gf_result_r;

                // Latch bad-block info on test done rising edge
                if (gf_done_r && gf_done_rise) begin
                    bad_block_info_reg <= bad_block_info_r;
                    cnt_bad_block_reg  <= cnt_bad_block_r;
                end
            end
        end
    end

    // --------------------------------------------------------
    // Read data multiplexer
    // --------------------------------------------------------
    always_comb begin
        case (sir_addr)
            `bar05_GF_CTRL: sir_rdat_next = {95'h0, gf_start};
            `bar05_GF_RESULT: sir_rdat_next = {
                    cnt_bad_block_reg,
                    bad_block_info_reg[63:32],
                    gf_result_reg[7:0],
                    cnt_bad_block_reg,
                    bad_block_info_reg[31:0],
                    gf_result_reg[7:0]
                };
            `bar05_GF_AUX_RESULT: sir_rdat_next = gf_aux_result;
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
