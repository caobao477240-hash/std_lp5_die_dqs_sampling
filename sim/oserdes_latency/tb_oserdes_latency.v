`timescale 1ps/1ps

// =========================================================================
//  tb_oserdes_latency
// -------------------------------------------------------------------------
//  Teaching testbench: show the difference between the 200 MHz CLKDIV
//  *load edge* and the 400 MHz CLK *output edges* of an OSERDESE3
//  (DATA_WIDTH=4), i.e. the fixed pipeline latency from "load" to "pin".
//
//  Two serializers are driven from the SAME clocks and loaded on the SAME
//  200 MHz edge:
//    u_ck  : raw OSERDESE3, loaded with 0110 (D0 launched first)
//    u_cmd : project RTL lpddr5_serdes_ddr_1bit, loaded rise,rise,fall,fall
//  A one-cycle "marker" pulse identifies the exact load edge so we can
//  measure load-edge -> pin-edge delay and show both lines shift together.
// =========================================================================
module tb_oserdes_latency;

    // clocks edge-aligned, same MMCM family: 400M = 1250ps half, 200M = 2500ps half
    reg clk_200m = 1'b0;
    reg clk_400m = 1'b0;
    reg rst_n    = 1'b0;

    always #1250 clk_400m = ~clk_400m;   // 400 MHz -> 800 MT/s DDR
    always #2500 clk_200m = ~clk_200m;   // 200 MHz core / CLKDIV

    // ---------------------------------------------------------------------
    //  Stimulus: a single distinctive word on one 200 MHz cycle
    // ---------------------------------------------------------------------
    // CK serializer word.  D[0] is launched first, so D[3:0]=0110 emits the
    // sequence 0,1,1,0 across the four UIs of one CK period.
    reg  [3:0] ck_word  = 4'b0000;   // {D3,D2,D1,D0}
    // Command data for CK rising/falling edges.
    reg        cmd_fall   = 1'b0;
    reg        cmd_rise   = 1'b0;
    reg        load_mark = 1'b0;     // pulses high on the marked load edge

    wire ck_q;
    wire cmd_q;

    integer cyc;
    // glbl GSR holds all OSERDES OQ at 0 for the first 100 ns of sim time.
    // Reset releases at t=30 ns (cyc starts counting there), so cyc 20 lands
    // at ~127 ns, safely past GSR release -> we observe real output.
    integer marked_cycle = 20;
    time    load_edge_ps = 0;

    // ---------------------------------------------------------------------
    //  Devices under test
    // ---------------------------------------------------------------------
    // Raw OSERDESE3 fed the CK pattern directly.
    OSERDESE3 #(
        .DATA_WIDTH        (4),
        .INIT              (1'b0),
        .IS_CLKDIV_INVERTED(1'b0),
        .IS_CLK_INVERTED   (1'b0),
        .IS_RST_INVERTED   (1'b0),
        .SIM_DEVICE        ("ULTRASCALE")
    ) u_ck (
        .OQ    (ck_q),
        .T_OUT (),
        .CLK   (clk_400m),
        .CLKDIV(clk_200m),
        .D     ({4'b0000, ck_word}),
        .RST   (~rst_n),
        .T     (1'b0)
    );

    // Project command serializer: D = {4'b0000, fall, fall, rise, rise}.
    lpddr5_serdes_ddr_1bit u_cmd (
        .clk_200m(clk_200m),
        .clk_400m(clk_400m),
        .rst_n   (rst_n),
        .data_rise(cmd_rise),
        .data_fall(cmd_fall),
        .out_q   (cmd_q)
    );

    // ---------------------------------------------------------------------
    //  Drive the marked word on exactly one 200 MHz load edge
    // ---------------------------------------------------------------------
    always @(posedge clk_200m or negedge rst_n) begin
        if (!rst_n) begin
            cyc       <= 0;
            ck_word   <= 4'b0000;
            cmd_fall  <= 1'b0;
            cmd_rise  <= 1'b0;
            load_mark <= 1'b0;
        end
        else begin
            cyc <= cyc + 1;
            // Drive the distinctive word as a 3-cycle burst (cyc 4,5,6) so the
            // OSERDES has a clean interior CLKDIV edge to latch it, and we can
            // watch the pattern switch ON (at first load) and OFF (after last),
            // each shifted by the same fixed pipeline latency.
            if (cyc >= marked_cycle && cyc <= marked_cycle + 2) begin
                ck_word   <= 4'b0110;   // launch 0,1,1,0
                cmd_fall    <= 1'b1;       // launch rise,rise,fall,fall = 0,0,1,1
                cmd_rise    <= 1'b0;
                load_mark <= (cyc == marked_cycle);
            end
            else begin
                ck_word   <= 4'b0000;
                cmd_fall    <= 1'b0;
                cmd_rise    <= 1'b0;
                load_mark <= 1'b0;
            end
        end
    end

    // Record the wall-clock time of the marked load edge.
    always @(posedge clk_200m) begin
        if (rst_n && (cyc == marked_cycle)) begin
            load_edge_ps = $time;
            $display("== LOAD  t=%0t ps : 200M edge loads ck_word=0110, cmd=rise,rise,fall,fall ==",
                     $time);
        end
    end

    // Per-UI strobe: sample the pin outputs 100 ps after every 400 MHz edge
    // (both edges -> once per UI), so the settled OQ value is captured.
    reg log_en = 1'b0;
    always @(clk_400m) begin
        if (log_en) begin
            #100;
            $display("UI t=%0t ps  ck_q=%b  cmd_q=%b  (+%0t from load)",
                     $time, ck_q, cmd_q, $time - load_edge_ps);
        end
    end

    // ---------------------------------------------------------------------
    //  Run + waveform dump
    // ---------------------------------------------------------------------
    initial begin
        $dumpfile("oserdes_latency.vcd");
        $dumpvars(0, tb_oserdes_latency);

        repeat (6) @(posedge clk_200m);
        @(negedge clk_200m);
        rst_n = 1'b1;

        // Wait until GSR has released (100 ns) before logging, then enable
        // per-UI logging a couple cycles ahead of the marked load.
        repeat (16) @(posedge clk_200m);
        log_en = 1'b1;

        repeat (12) @(posedge clk_200m);
        log_en = 1'b0;
        $display("== DONE ==");
        $finish;
    end

endmodule
