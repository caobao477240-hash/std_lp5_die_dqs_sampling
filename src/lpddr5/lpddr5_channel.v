`timescale 1ns / 1ps

// =========================================================================
//  LPDDR5 Channel A
// =========================================================================
// Owns the channel IDELAY control and physical IO primitives. Command/test
// engines provide CK-edge data plus WCK run/phase controls; this module is the
// only PHY boundary.
module lpddr5_channel (
    input               i_clk_core_200m             ,
    input               i_clk_dq_tx_400m            ,
    input               i_clk_ca_wck_400m           ,
    input               i_clk_dq_rx_400m            ,
    input               i_serdes_reset_n            ,
    input               rst_n                       ,

    // Physical pins
    output              reset_n_a                   ,
    output              ck_t_a                      ,
    output              ck_c_a                      ,
    output              cs0_a                       ,
    output      [6:0]   ca_a                        ,
    inout       [15:0]  dq_a                        ,
    output      [1:0]   wck_t_a                     ,
    output      [1:0]   wck_c_a                     ,
    inout       [1:0]   rdqs_t_a                    ,
    inout       [1:0]   rdqs_c_a                    ,
    inout       [1:0]   dmi_a                       ,

    // Selected CK run enable and serialized waveform
    input               ck_a_run_en                 ,
    input               cs_a_0_rise                 ,
    input               cs_a_0_fall                 ,
    input       [6:0]   ca_a_rise                   ,
    input       [6:0]   ca_a_fall                   ,
    input       [1:0]   wck_a_run_en                ,
    input       [1:0]   wck_a_phase                 ,
    input       [63:0]  dq_a_tx_word                ,
    input       [7:0]   dmi_a_tx_word               ,
    input       [1:0]   rdqs_t_a_in_dh              ,
    input       [1:0]   rdqs_t_a_in_dl              ,
    input               reset_n_a_level             ,

    // Read data and PHY control
    output      [63:0]  dq_a_word_flat              ,
    output              dq_a_word_valid             ,
    input               dq_a_tx_oe                  ,
    input               cha_group_0_strobe_out_en   ,
    input               rx_dq_capture_en            ,
    input       [3:0]   rx_burst_beat_offset        ,
    output      [255:0] dq_a_burst_flat             ,
    output              dq_a_burst_valid            ,
    output      [63:0]  dbg_dq_word_raw             ,
    input               RDY                         ,
    input       [143:0] delay_value_dq_a
);

reg  [143:0] delay_value_dq_a_r ;
reg  [1:0] idelay_state         ;
reg  [5:0] idelay_wait_cnt      ;
reg  [1:0] idelay_init_count    ;
reg        idelay_update_load   ;
wire       idelay_load          ;
wire       idelay_en_vtc        ;
wire       delay_change_req     ;
wire       init_wait_done       ;
wire       init_load_pulse      ;

localparam [1:0] IDELAY_WAIT_RDY = 2'd0;
localparam [1:0] IDELAY_INIT     = 2'd1;
localparam [1:0] IDELAY_READY    = 2'd2;

localparam [5:0] IDELAY_LOAD_WAIT_CYCLES = 6'd49;
localparam [1:0] IDELAY_INIT_LOAD_TOTAL  = 2'd3;

// IDELAY load controller. Keep the legacy three-load power-up cadence,
// then issue one LOAD pulse whenever the host changes delay registers.
always @(posedge i_clk_core_200m or negedge rst_n) begin
    if(!rst_n) begin
        idelay_state      <= IDELAY_WAIT_RDY;
        idelay_wait_cnt   <= 6'd0;
        idelay_init_count <= 2'd0;
        idelay_update_load <= 1'b0;
    end
    else begin
        idelay_update_load <= 1'b0;

        case(idelay_state)
            IDELAY_WAIT_RDY: begin
                idelay_wait_cnt   <= 6'd0;
                idelay_init_count <= 2'd0;
                if(RDY) begin
                    idelay_state <= IDELAY_INIT;
                end
            end

            IDELAY_INIT: begin
                if(init_wait_done) begin
                    idelay_wait_cnt <= 6'd0;

                    if(idelay_init_count >= (IDELAY_INIT_LOAD_TOTAL - 2'd1)) begin
                        idelay_state <= IDELAY_READY;
                    end
                    else begin
                        idelay_init_count <= idelay_init_count + 2'd1;
                    end
                end
                else begin
                    idelay_wait_cnt <= idelay_wait_cnt + 6'd1;
                end
            end

            IDELAY_READY: begin
                if(delay_change_req) begin
                    idelay_update_load <= 1'b1;
                end
            end

            default: begin
                idelay_state <= IDELAY_WAIT_RDY;
            end
        endcase
    end
end

always @(posedge i_clk_core_200m or negedge rst_n) begin
    if(!rst_n) begin
        delay_value_dq_a_r    <= 144'd0;
    end
    else begin
        delay_value_dq_a_r    <= delay_value_dq_a;
    end
end

assign delay_change_req =
    (idelay_state == IDELAY_READY) &&
    (delay_value_dq_a != delay_value_dq_a_r);

assign init_wait_done = (idelay_wait_cnt >= IDELAY_LOAD_WAIT_CYCLES);
assign init_load_pulse = (idelay_state == IDELAY_INIT) && init_wait_done;
assign idelay_load     = init_load_pulse || idelay_update_load;
assign idelay_en_vtc  = (idelay_state != IDELAY_READY) &&
                        (idelay_init_count == 2'd0);

lpddr5_ch_a_phy_io U_lpddr5_ch_a_phy_io (
    .i_clk_core_200m                (i_clk_core_200m                 ),
    .i_clk_dq_tx_400m               (i_clk_dq_tx_400m                ),
    .i_clk_ca_wck_400m              (i_clk_ca_wck_400m               ),
    .i_clk_dq_rx_400m               (i_clk_dq_rx_400m                ),
    .i_serdes_reset_n               (i_serdes_reset_n                ),

    .reset_n_a                      (reset_n_a                      ),
    .ck_t_a                         (ck_t_a                         ),
    .ck_c_a                         (ck_c_a                         ),
    .cs0_a                          (cs0_a                          ),
    .ca_a                           (ca_a                           ),
    .dq_a                           (dq_a                           ),
    .wck_t_a                        (wck_t_a                        ),
    .wck_c_a                        (wck_c_a                        ),
    .rdqs_t_a                       (rdqs_t_a                       ),
    .rdqs_c_a                       (rdqs_c_a                       ),
    .dmi_a                          (dmi_a                          ),

    .ck_a_run_en                    (ck_a_run_en                    ),
    .wck_a_run_en                   (wck_a_run_en                   ),
    .wck_a_phase                    (wck_a_phase                    ),
    .reset_n_a_level                (reset_n_a_level                ),
    .cs_a_0_rise                    (cs_a_0_rise                    ),
    .cs_a_0_fall                    (cs_a_0_fall                    ),
    .ca_a_rise                      (ca_a_rise                      ),
    .ca_a_fall                      (ca_a_fall                      ),

    .dq_a_tx_word                   (dq_a_tx_word                   ),
    .dmi_a_tx_word                  (dmi_a_tx_word                  ),
    .dq_a_word_flat                 (dq_a_word_flat                 ),
    .dq_a_word_valid                (dq_a_word_valid                ),
    .rdqs_t_a_in_dh                 (rdqs_t_a_in_dh                 ),
    .rdqs_t_a_in_dl                 (rdqs_t_a_in_dl                 ),

    .dq_a_tx_oe                     (dq_a_tx_oe                     ),
    .cha_group_0_strobe_out_en      (cha_group_0_strobe_out_en      ),
    .delay_value_dq_a               (delay_value_dq_a_r             ),
    .idelay_en_vtc                  (idelay_en_vtc                  ),
    .idelay_load                    (idelay_load                    ),
    .rx_dq_capture_en              (rx_dq_capture_en               ),
    .rx_burst_beat_offset           (rx_burst_beat_offset           ),
    .dq_a_burst_flat                (dq_a_burst_flat                ),
    .dq_a_burst_valid               (dq_a_burst_valid               ),
    .dbg_dq_word_raw                (dbg_dq_word_raw                )
);

endmodule
