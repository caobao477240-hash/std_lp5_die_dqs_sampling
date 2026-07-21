`timescale 1ns / 1ps

// =========================================================================
//  LPDDR5 IDD Controller
// =========================================================================
// Owns all IDD-only counters, completion control and CK-edge waveforms.
module lpddr5_idd #(
`ifdef LP5_SIM_FAST
    parameter                           T_CMDPD                     = 4                    ,
    parameter                           T_CSLCK                     = 3                    ,
    parameter                           T_CKCSH                     = 3                    ,
    parameter                           T_XP                        = 3                    ,
    parameter                           T_RPab                      = 6                    ,
    parameter                           T_IDD                       = 16                   ,
    parameter                           T_500MS                     = 28'd32
`else
    parameter                           T_CMDPD                     = 10                   ,
    parameter                           T_CSLCK                     = 10                   ,
    parameter                           T_CKCSH                     = 10                   ,
    parameter                           T_XP                        = 10                   ,
    parameter                           T_RPab                      = 12                   ,
    parameter                           T_IDD                       = 16                   ,
    parameter                           T_500MS                     = 28'd100000000
`endif
) (
    input                               clk                        ,
    input                               rst_n                      ,
    input                               start_idd                  ,
    input                [   9: 0]      idd_en_r                   ,

    input                [   1: 0]      cnt_bg                     ,
    input                [   1: 0]      cnt_ba                     ,

    output                              idd_busy                   ,
    output reg           [   2: 0]      idd_state                  ,
    output reg                          idd_done                   ,
    output                              idd_ck_stop                ,
    output reg           [ 111: 0]      ascii_state                ,

    output reg                          wave_ck_a_run_en           ,
    output reg                          wave_cs_a_0_rise           ,
    output reg                          wave_cs_a_0_fall           ,
    output reg           [   6: 0]      wave_ca_a_rise             ,
    output reg           [   6: 0]      wave_ca_a_fall             ,
    output reg           [  15: 0]      wave_dq_a_in_dh            ,
    output reg           [  15: 0]      wave_dq_a_in_dl            ,
    output reg                          wave_dq_oe                 ,
    output reg                          wave_rdqs_oe
);

    localparam                          IDD2P1                      = 10'b00_0000_0011     ;
    localparam                          IDD2P2H                     = 10'b00_0000_0101     ;
    localparam                          IDD2P2L                     = 10'b00_0000_1001     ;
    localparam                          IDD2N1                      = 10'b00_0001_0001     ;
    localparam                          IDD2N2H                     = 10'b00_0010_0001     ;
    localparam                          IDD2N2L                     = 10'b00_0100_0001     ;
    localparam                          IDD61                       = 10'b00_1000_0001     ;
    localparam                          IDD62H                      = 10'b01_0000_0001     ;
    localparam                          IDD62L                      = 10'b10_0000_0001     ;

    localparam                          IDD_IDLE                    = 3'd0                 ;
    localparam                          IDD_PRECHARGE               = 3'd1                 ;
    localparam                          IDD_PD_ENTRY                = 3'd2                 ;
    localparam                          IDD_MEASURE                 = 3'd3                 ;
    localparam                          IDD_PD_EXIT                 = 3'd4                 ;
    localparam                          IDD_SRE                     = 3'd5                 ;
    localparam                          IDD_SRX                     = 3'd6                 ;

    wire                                idd_mode_2p                ;
    wire                                idd_mode_2n                ;
    wire                                idd_mode_6                 ;

    wire                                state_idle                 ;
    wire                                state_idd_precharging      ;
    wire                                state_pd_entry             ;
    wire                                state_idd                  ;
    wire                                state_pd_exit              ;
    wire                                state_sre                  ;
    wire                                state_srx                  ;

    reg                                 precharge_cnt_flag         ;
    reg                                 pdentry_cnt_flag           ;
    reg                                 idd_cnt_flag               ;
    reg                                 pdexit_cnt_flag            ;
    reg                                 sre_cnt_flag               ;
    reg                                 srx_cnt_flag               ;
    reg                                 r_ck_phase                 ;
    reg                  [   6: 0]      cnt_precharge              ;
    reg                  [  10: 0]      cnt_pdentry                ;
    reg                  [  10: 0]      cnt_idd                    ;
    reg                  [  10: 0]      cnt_pdexit                 ;
    reg                  [  27: 0]      cnt_500ms                  ;
    reg                  [  10: 0]      cnt_sre                    ;
    reg                  [  10: 0]      cnt_srx                    ;

    wire                                add_cnt_precharge          ;
    wire                                add_cnt_pdentry            ;
    wire                                add_cnt_idd                ;
    wire                                add_cnt_pdexit             ;
    wire                                add_cnt_500ms              ;
    wire                                add_cnt_sre                ;
    wire                                add_cnt_srx                ;
    wire                                end_cnt_precharge          ;
    wire                                end_cnt_pdentry            ;
    wire                                end_cnt_idd                ;
    wire                                end_cnt_pdexit             ;
    wire                                end_cnt_500ms              ;
    wire                                end_cnt_sre                ;
    wire                                end_cnt_srx                ;
    wire                                iddprecharge2pdentry       ;
    wire                                pdentry2idd                ;
    wire                                idd2pdexit                 ;
    wire                                pdexit2idle                ;
    wire                                iddprecharge2idd           ;
    wire                                idd2idle                   ;
    wire                                iddprecharge2selfrefreshentry  ;
    wire                                selfrefreshentry2pdentry   ;
    wire                                pdexit2selffreshexit       ;
    wire                                selffreshexit2idle         ;

assign idd_mode_2p = idd_en_r[1] || idd_en_r[2] || idd_en_r[3];
assign idd_mode_2n = idd_en_r[4] || idd_en_r[5] || idd_en_r[6];
assign idd_mode_6  = idd_en_r[7] || idd_en_r[8] || idd_en_r[9];

assign state_idle               = idd_state == IDD_IDLE;
assign state_idd_precharging    = idd_state == IDD_PRECHARGE;
assign state_pd_entry           = idd_state == IDD_PD_ENTRY;
assign state_idd                = idd_state == IDD_MEASURE;
assign state_pd_exit            = idd_state == IDD_PD_EXIT;
assign state_sre                = idd_state == IDD_SRE;
assign state_srx                = idd_state == IDD_SRX;
assign idd_busy                 = !state_idle;
assign idd_ck_stop              = end_cnt_idd && end_cnt_500ms;

always @(*) begin
    case (idd_state)
        IDD_PRECHARGE: ascii_state = "IDD_PRECHARGE ";
        IDD_PD_ENTRY:  ascii_state = "IDD_PD_ENTRY  ";
        IDD_MEASURE: begin
            case (idd_en_r)
                IDD2P1:    ascii_state = "IDD2P1        ";
                IDD2P2H:   ascii_state = "IDD2P2H       ";
                IDD2P2L:   ascii_state = "IDD2P2L       ";
                IDD2N1:    ascii_state = "IDD2N1        ";
                IDD2N2H:   ascii_state = "IDD2N2H       ";
                IDD2N2L:   ascii_state = "IDD2N2L       ";
                IDD61:     ascii_state = "IDD61         ";
                IDD62H:    ascii_state = "IDD62H        ";
                IDD62L:    ascii_state = "IDD62L        ";
                default:   ascii_state = "idd_default   ";
            endcase
        end
        IDD_PD_EXIT:   ascii_state = "IDD_PD_EXIT   ";
        IDD_SRE:       ascii_state = "IDD_SRE       ";
        IDD_SRX:       ascii_state = "IDD_SRX       ";
        default:       ascii_state = "IDD           ";
    endcase
end

assign iddprecharge2pdentry          = state_idd_precharging && end_cnt_precharge && idd_mode_2p;
assign pdentry2idd                   = state_pd_entry && end_cnt_pdentry;
assign idd2pdexit                    = state_idd && end_cnt_idd && end_cnt_500ms && (idd_mode_2p || idd_mode_6);
assign pdexit2idle                   = state_pd_exit && end_cnt_pdexit && idd_mode_2p;
assign iddprecharge2idd              = state_idd_precharging && end_cnt_precharge && idd_mode_2n;
assign idd2idle                      = state_idd && end_cnt_idd && end_cnt_500ms && idd_mode_2n;
assign iddprecharge2selfrefreshentry = state_idd_precharging && end_cnt_precharge && idd_mode_6;
assign selfrefreshentry2pdentry      = state_sre && end_cnt_sre;
assign pdexit2selffreshexit          = state_pd_exit && end_cnt_pdexit && idd_mode_6;
assign selffreshexit2idle            = state_srx && end_cnt_srx;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        idd_state <= IDD_IDLE;
    else begin
        case (idd_state)
            IDD_IDLE: begin
                if (start_idd)
                    idd_state <= IDD_PRECHARGE;
            end

            IDD_PRECHARGE: begin
                if (iddprecharge2pdentry)
                    idd_state <= IDD_PD_ENTRY;
                else if (iddprecharge2idd)
                    idd_state <= IDD_MEASURE;
                else if (iddprecharge2selfrefreshentry)
                    idd_state <= IDD_SRE;
            end

            IDD_PD_ENTRY: begin
                if (pdentry2idd)
                    idd_state <= IDD_MEASURE;
            end

            IDD_MEASURE: begin
                if (idd2pdexit)
                    idd_state <= IDD_PD_EXIT;
                else if (idd2idle)
                    idd_state <= IDD_IDLE;
            end

            IDD_PD_EXIT: begin
                if (pdexit2idle)
                    idd_state <= IDD_IDLE;
                else if (pdexit2selffreshexit)
                    idd_state <= IDD_SRX;
            end

            IDD_SRE: begin
                if (selfrefreshentry2pdentry)
                    idd_state <= IDD_PD_ENTRY;
            end

            IDD_SRX: begin
                if (selffreshexit2idle)
                    idd_state <= IDD_IDLE;
            end

            default:
                idd_state <= IDD_IDLE;
        endcase
    end
end

assign add_cnt_precharge = state_idd_precharging && precharge_cnt_flag;
assign end_cnt_precharge = add_cnt_precharge && cnt_precharge >= T_RPab - 1;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        cnt_precharge <= 7'd0;
    else if (!idd_en_r[0])
        cnt_precharge <= 7'd0;
    else if (add_cnt_precharge) begin
        if (end_cnt_precharge)
            cnt_precharge <= 7'd0;
        else
            cnt_precharge <= cnt_precharge + 7'd1;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        precharge_cnt_flag <= 1'b0;
    else if (!idd_en_r[0])
        precharge_cnt_flag <= 1'b0;
    else if (end_cnt_precharge)
        precharge_cnt_flag <= 1'b0;
    else if (r_ck_phase && state_idd_precharging)
        precharge_cnt_flag <= 1'b1;
end

assign add_cnt_pdentry = state_pd_entry && pdentry_cnt_flag;
assign end_cnt_pdentry = add_cnt_pdentry && cnt_pdentry >= T_CMDPD + T_CSLCK + T_CKCSH - 1;

assign add_cnt_pdexit = state_pd_exit && pdexit_cnt_flag;
assign end_cnt_pdexit = add_cnt_pdexit && cnt_pdexit >= T_CKCSH + T_XP + T_XP - 1;

assign add_cnt_sre = state_sre && sre_cnt_flag;
assign end_cnt_sre = add_cnt_sre && cnt_sre >= 10 - 1;

assign add_cnt_srx = state_srx && srx_cnt_flag;
assign end_cnt_srx = add_cnt_srx && cnt_srx >= 10 - 1;

assign add_cnt_idd = state_idd && (idd_cnt_flag || idd_mode_6);
assign end_cnt_idd = add_cnt_idd && cnt_idd >= T_IDD - 1;

assign add_cnt_500ms = state_idd;
assign end_cnt_500ms = add_cnt_500ms && cnt_500ms >= T_500MS - 1;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        cnt_pdentry <= 11'd0;
    else if (!idd_en_r[0])
        cnt_pdentry <= 11'd0;
    else if (add_cnt_pdentry) begin
        if (end_cnt_pdentry)
            cnt_pdentry <= 11'd0;
        else
            cnt_pdentry <= cnt_pdentry + 11'd1;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        pdentry_cnt_flag <= 1'b0;
    else if (!idd_en_r[0])
        pdentry_cnt_flag <= 1'b0;
    else if (end_cnt_pdentry)
        pdentry_cnt_flag <= 1'b0;
    else if (r_ck_phase && state_pd_entry)
        pdentry_cnt_flag <= 1'b1;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        cnt_pdexit <= 11'd0;
    else if (!idd_en_r[0])
        cnt_pdexit <= 11'd0;
    else if (add_cnt_pdexit) begin
        if (end_cnt_pdexit)
            cnt_pdexit <= 11'd0;
        else
            cnt_pdexit <= cnt_pdexit + 11'd1;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        pdexit_cnt_flag <= 1'b0;
    else if (!idd_en_r[0])
        pdexit_cnt_flag <= 1'b0;
    else if (end_cnt_pdexit)
        pdexit_cnt_flag <= 1'b0;
    else if (r_ck_phase && state_pd_exit)
        pdexit_cnt_flag <= 1'b1;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        cnt_sre <= 11'd0;
    else if (!idd_en_r[0])
        cnt_sre <= 11'd0;
    else if (add_cnt_sre) begin
        if (end_cnt_sre)
            cnt_sre <= 11'd0;
        else
            cnt_sre <= cnt_sre + 11'd1;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        sre_cnt_flag <= 1'b0;
    else if (!idd_en_r[0])
        sre_cnt_flag <= 1'b0;
    else if (end_cnt_sre)
        sre_cnt_flag <= 1'b0;
    else if (r_ck_phase && state_sre)
        sre_cnt_flag <= 1'b1;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        cnt_srx <= 11'd0;
    else if (!idd_en_r[0])
        cnt_srx <= 11'd0;
    else if (add_cnt_srx) begin
        if (end_cnt_srx)
            cnt_srx <= 11'd0;
        else
            cnt_srx <= cnt_srx + 11'd1;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        srx_cnt_flag <= 1'b0;
    else if (!idd_en_r[0])
        srx_cnt_flag <= 1'b0;
    else if (end_cnt_srx)
        srx_cnt_flag <= 1'b0;
    else if (r_ck_phase && state_srx)
        srx_cnt_flag <= 1'b1;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        cnt_idd <= 11'd0;
    else if (!idd_en_r[0])
        cnt_idd <= 11'd0;
    else if (add_cnt_idd) begin
        if (end_cnt_idd)
            cnt_idd <= 11'd0;
        else
            cnt_idd <= cnt_idd + 11'd1;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        idd_cnt_flag <= 1'b0;
    else if (!idd_en_r[0])
        idd_cnt_flag <= 1'b0;
    else if (end_cnt_500ms && end_cnt_idd)
        idd_cnt_flag <= 1'b0;
    else if (r_ck_phase && state_idd)
        idd_cnt_flag <= 1'b1;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        cnt_500ms <= 28'd0;
    else if (!idd_en_r[0])
        cnt_500ms <= 28'd0;
    else if (add_cnt_500ms && !end_cnt_500ms)
        cnt_500ms <= cnt_500ms + 28'd1;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        idd_done <= 1'b0;
    else if (!idd_en_r[0])
        idd_done <= 1'b0;
    else if (pdexit2idle || idd2idle || selffreshexit2idle)
        idd_done <= 1'b1;
end

// IDD6 stops CK during the self-refresh measurement window.
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        wave_ck_a_run_en <= 1'b1;
    else if (end_cnt_idd && end_cnt_500ms)
        wave_ck_a_run_en <= 1'b1;
    else if (idd_mode_6 && state_idd)
        wave_ck_a_run_en <= 1'b0;
    else
        wave_ck_a_run_en <= 1'b1;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        r_ck_phase <= 1'b0;
    else if (end_cnt_idd && end_cnt_500ms)
        r_ck_phase <= 1'b0;
    else if (idd_mode_6 && state_idd)
        r_ck_phase <= 1'b0;
    else
        r_ck_phase <= ~r_ck_phase;
end

// IDD command/address waveforms.
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wave_cs_a_0_fall   <= 1'b0;
        wave_cs_a_0_rise   <= 1'b0;
        wave_ca_a_fall     <= 7'h00;
        wave_ca_a_rise     <= 7'h00;
        wave_rdqs_oe     <= 1'b0;
    end
    else begin
        wave_cs_a_0_fall <= 1'b0;
        wave_cs_a_0_rise <= 1'b0;
        wave_ca_a_fall   <= 7'h00;
        wave_ca_a_rise   <= 7'h00;

        if (state_idle)
            wave_rdqs_oe <= 1'b0;

        if (state_idd_precharging) begin
            case (cnt_precharge)
                2: begin
                    wave_cs_a_0_fall <= 1'b1;
                end
                3: begin
                    wave_cs_a_0_fall <= 1'b1;
                    wave_cs_a_0_rise <= 1'b1;
                    wave_ca_a_fall   <= 7'b1111000;
                    wave_ca_a_rise   <= 7'b1111000;
                end
                4: begin
                    wave_cs_a_0_fall <= 1'b1;
                    wave_cs_a_0_rise <= 1'b1;
                    wave_ca_a_fall   <= {3'b111, cnt_bg, cnt_ba};
                    wave_ca_a_rise   <= {3'b111, cnt_bg, cnt_ba};
                end
            endcase
        end
        else if (state_pd_entry) begin
            if (cnt_pdentry == T_CMDPD) begin
                wave_cs_a_0_fall <= 1'b1;
            end
            else if (cnt_pdentry == (T_CMDPD + 1)) begin
                wave_cs_a_0_fall <= 1'b1;
                wave_cs_a_0_rise <= 1'b1;
                wave_ca_a_fall   <= 7'b1000000;
                wave_ca_a_rise   <= 7'b1000000;
            end
            else if (cnt_pdentry == (T_CMDPD + 2)) begin
                wave_cs_a_0_rise <= 1'b1;
                wave_ca_a_fall   <= 7'b1000000;
                wave_ca_a_rise   <= 7'b1000000;
            end
        end
        else if (state_pd_exit) begin
            if (cnt_pdexit == T_CKCSH) begin
                wave_cs_a_0_fall <= 1'b1;
            end
            else if ((cnt_pdexit == (T_CKCSH + 1)) || (cnt_pdexit == (T_CKCSH + 2))) begin
                wave_cs_a_0_fall <= 1'b1;
                wave_cs_a_0_rise <= 1'b1;
            end
        end
        else if (state_idd) begin
            if (idd_mode_2p || idd_mode_2n) begin
                wave_rdqs_oe <= 1'b1;
                case (cnt_idd)
                    0, 15: begin wave_ca_a_fall <= 7'b1111111; wave_ca_a_rise <= 7'b1111111; end
                    1, 2:  begin wave_ca_a_fall <= 7'b0101010; wave_ca_a_rise <= 7'b0101010; end
                    3, 4:  begin wave_ca_a_fall <= 7'b0000000; wave_ca_a_rise <= 7'b0000000; end
                    5, 6:  begin wave_ca_a_fall <= 7'b1010101; wave_ca_a_rise <= 7'b1010101; end
                    7, 8:  begin wave_ca_a_fall <= 7'b1111111; wave_ca_a_rise <= 7'b1111111; end
                    9, 10: begin wave_ca_a_fall <= 7'b0101010; wave_ca_a_rise <= 7'b0101010; end
                    11, 12: begin wave_ca_a_fall <= 7'b0000000; wave_ca_a_rise <= 7'b0000000; end
                    13, 14: begin wave_ca_a_fall <= 7'b1010101; wave_ca_a_rise <= 7'b1010101; end
                endcase
            end
            else if (idd_mode_6) begin
                wave_rdqs_oe <= 1'b1;
            end
        end
        else if (state_sre) begin
            case (cnt_sre)
                2: begin
                    wave_cs_a_0_fall <= 1'b1;
                end
                3: begin
                    wave_cs_a_0_fall <= 1'b1;
                    wave_cs_a_0_rise <= 1'b1;
                    wave_ca_a_fall   <= 7'b1101000;
                    wave_ca_a_rise   <= 7'b1101000;
                end
                4: begin
                    wave_cs_a_0_fall <= 1'b1;
                    wave_cs_a_0_rise <= 1'b1;
                end
            endcase
        end
        else if (state_srx) begin
            case (cnt_srx)
                2: begin
                    wave_cs_a_0_fall <= 1'b1;
                end
                3: begin
                    wave_cs_a_0_fall <= 1'b1;
                    wave_cs_a_0_rise <= 1'b1;
                    wave_ca_a_fall   <= 7'b0101000;
                    wave_ca_a_rise   <= 7'b0101000;
                end
                4: begin
                    wave_cs_a_0_fall <= 1'b1;
                    wave_cs_a_0_rise <= 1'b1;
                end
            endcase
        end
    end
end


always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wave_dq_a_in_dh   <= 16'h0000;
        wave_dq_a_in_dl   <= 16'h0000;
        wave_dq_oe        <= 1'b0;
    end
    else begin
        wave_dq_a_in_dh   <= 16'h0000;
        wave_dq_a_in_dl   <= 16'h0000;
        wave_dq_oe        <= 1'b0;
    end
end

endmodule
