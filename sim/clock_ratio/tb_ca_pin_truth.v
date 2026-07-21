`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Module Name:     tb_ca_pin_truth
// Description:
//   Pin-truth check for the CK / CA serdes wrappers.  Drives the CK wrapper
//   with a constant-enable pattern and the CA wrapper with a marker value,
//   then samples the CA pin at every CK rising and falling edge and prints
//   the sampled 7-bit values.  This nails, at the FPGA pin level:
//     1. whether rise/fall command data lands on the matching CK edge;
//     2. whether wave_ca[6] reaches the physical CA6 or is bit-reversed.
//   Uses real unisim OSERDESE3 models; compile with unisims_ver mapped.
//////////////////////////////////////////////////////////////////////////////////

module tb_ca_pin_truth;

reg         clk_200m;
reg         clk_400m;
reg         rst_n;
reg  [6:0]  ca_rise;
reg  [6:0]  ca_fall;
reg         ck_run_en;

wire        ck_pin;
wire [6:0]  ca_pin;

integer     edge_cnt;

genvar b;

lpddr5_serdes_ck_1bit U_ck (
    .clk_200m (clk_200m),
    .clk_400m (clk_400m),
    .rst_n    (rst_n   ),
    .ck_run_en(ck_run_en),
    .out_q    (ck_pin  )
);

generate
    for (b = 0; b < 7; b = b + 1) begin : GEN_CA
        lpddr5_serdes_ddr_1bit U_ca (
            .clk_200m (clk_200m),
            .clk_400m (clk_400m),
            .rst_n    (rst_n   ),
            .data_rise(ca_rise[b]),
            .data_fall(ca_fall[b]),
            .out_q    (ca_pin[b])
        );
    end
endgenerate

always #2.5 clk_200m = ~clk_200m;
always #1.25 clk_400m = ~clk_400m;

// Sample CA at every CK pin edge, JEDEC-style.
always @(posedge ck_pin) begin
    if (edge_cnt < 40) begin
        $display("CK RISE : ca_pin=%07b (CA6..CA0)", ca_pin);
        edge_cnt = edge_cnt + 1;
    end
end

always @(negedge ck_pin) begin
    if (edge_cnt < 40) begin
        $display("CK FALL : ca_pin=%07b (CA6..CA0)", ca_pin);
        edge_cnt = edge_cnt + 1;
    end
end

initial begin
    clk_200m = 1'b0;
    clk_400m = 1'b0;
    rst_n    = 1'b0;
    ca_rise  = 7'h00;
    ca_fall  = 7'h00;
    ck_run_en = 1'b0;
    edge_cnt = 0;

    repeat (8) @(posedge clk_200m);
    rst_n = 1'b1;
    repeat (8) @(posedge clk_200m);

    // Turn CK on and park CA at distinct marker values:
    //   rise = 7'b1100101, fall = 7'b0011010 (bitwise complements-ish, both
    //   asymmetric so any reversal is visible immediately).
    ck_run_en = 1'b1;
    ca_rise = 7'b1100101;
    ca_fall = 7'b0011010;

    repeat (12) @(posedge clk_200m);

    $display("MARKERS: rise=1100101 fall=0011010");
    $display("If RISE shows 1100101 -> rise data, direct bit order.");
    $display("If RISE shows 1010011 -> rise data, bit-reversed at pin.");
    $display("If RISE shows 0011010 -> fall data, direct bit order.");
    $display("If RISE shows 0101100 -> fall data, bit-reversed at pin.");
    $finish;
end

initial begin
    #100_000;
    $display("SIM FAIL: timeout");
    $finish;
end

endmodule
