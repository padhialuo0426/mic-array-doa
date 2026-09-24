`timescale 1ns/1ps
// Verilog DVI transmitter with the interface of Digilent rgb2dvi as used by
// hdmi_display.v (external 5x serial clock, active-high reset). Follows the
// DVI 1.0 TMDS algorithm: vid_pData = {red, blue, green}; channel 0 carries
// blue with HSYNC/VSYNC during blanking, channel 1 green, channel 2 red.
// Each lane is a master/slave OSERDESE2 pair (10:1 DDR) into OBUFDS.
module rgb2dvi #(
    parameter kGenerateSerialClk = 0, parameter kClkPrimitive = "MMCM", parameter kClkRange = 1,
    parameter kRstActiveHigh = 1, parameter kD0Swap = 0, parameter kD1Swap = 0,
    parameter kD2Swap = 0, parameter kClkSwap = 0
)(
    output wire TMDS_Clk_p, output wire TMDS_Clk_n,
    output wire [2:0] TMDS_Data_p, output wire [2:0] TMDS_Data_n,
    input wire aRst, input wire aRst_n,
    input wire [23:0] vid_pData, input wire vid_pVDE, input wire vid_pHSync, input wire vid_pVSync,
    input wire PixelClk, input wire SerialClk
);
    wire async_reset = kRstActiveHigh ? aRst : !aRst_n;
    // Reset: asynchronous assert, release synchronized to PixelClk, then held
    // several cycles so OSERDESE2 reset spans CLKDIV edges as UG471 requires.
    (* ASYNC_REG="TRUE" *) reg [2:0] reset_sync = 3'b111;
    reg [3:0] reset_hold = 4'hf;
    always @(posedge PixelClk or posedge async_reset)
        if(async_reset) reset_sync <= 3'b111; else reset_sync <= {reset_sync[1:0], 1'b0};
    always @(posedge PixelClk) reset_hold <= reset_sync[2] ? 4'hf : {reset_hold[2:0], 1'b0};
    wire preset = reset_hold[3];

    wire [9:0] blue, green, red;
    tmds_encoder enc0(.clk(PixelClk), .data(vid_pData[15:8]), .c({vid_pVSync, vid_pHSync}), .de(vid_pVDE), .q(blue));
    tmds_encoder enc1(.clk(PixelClk), .data(vid_pData[7:0]), .c(2'b00), .de(vid_pVDE), .q(green));
    tmds_encoder enc2(.clk(PixelClk), .data(vid_pData[23:16]), .c(2'b00), .de(vid_pVDE), .q(red));
    tmds_serializer lane0(.pclk(PixelClk), .sclk(SerialClk), .rst(preset), .word(blue), .p(TMDS_Data_p[0]), .n(TMDS_Data_n[0]));
    tmds_serializer lane1(.pclk(PixelClk), .sclk(SerialClk), .rst(preset), .word(green), .p(TMDS_Data_p[1]), .n(TMDS_Data_n[1]));
    tmds_serializer lane2(.pclk(PixelClk), .sclk(SerialClk), .rst(preset), .word(red), .p(TMDS_Data_p[2]), .n(TMDS_Data_n[2]));
    tmds_serializer clock(.pclk(PixelClk), .sclk(SerialClk), .rst(preset), .word(10'b0000011111), .p(TMDS_Clk_p), .n(TMDS_Clk_n));
endmodule

// DVI 1.0 section 3.2.3 TMDS encoder, two pipeline stages.
module tmds_encoder(input wire clk, input wire [7:0] data, input wire [1:0] c, input wire de, output reg [9:0] q);
    function [3:0] ones8; input [7:0] v; integer i; begin ones8=0; for(i=0;i<8;i=i+1) ones8=ones8+v[i]; end endfunction
    reg [8:0] qm; reg de1; reg [1:0] c1; reg signed [4:0] disparity = 0;
    wire [3:0] n1d = ones8(data);
    wire use_xnor = n1d > 4 || (n1d == 4 && !data[0]);
    reg [8:0] qm_next; integer i;
    always @(*) begin
        qm_next[0] = data[0];
        for(i=1;i<8;i=i+1) qm_next[i] = use_xnor ? !(qm_next[i-1] ^ data[i]) : (qm_next[i-1] ^ data[i]);
        qm_next[8] = !use_xnor;
    end
    always @(posedge clk) begin qm <= qm_next; de1 <= de; c1 <= c; end
    wire [3:0] n1q = ones8(qm[7:0]);
    wire signed [4:0] balance = $signed({1'b0, n1q}) - 5'sd4;   // (n1 - n0)/2
    always @(posedge clk) begin
        if(!de1) begin
            disparity <= 0;
            case(c1)
                2'b00: q <= 10'b1101010100;
                2'b01: q <= 10'b0010101011;
                2'b10: q <= 10'b0101010100;
                default: q <= 10'b1010101011;
            endcase
        end else if(disparity == 0 || balance == 0) begin
            q <= {!qm[8], qm[8], qm[8] ? qm[7:0] : ~qm[7:0]};
            disparity <= qm[8] ? disparity + 2*balance : disparity - 2*balance;
        end else if((disparity > 0 && balance > 0) || (disparity < 0 && balance < 0)) begin
            q <= {1'b1, qm[8], ~qm[7:0]};
            disparity <= disparity + (qm[8] ? 5'sd2 : 5'sd0) - 2*balance;
        end else begin
            q <= {1'b0, qm[8], qm[7:0]};
            disparity <= disparity - (qm[8] ? 5'sd0 : 5'sd2) + 2*balance;
        end
    end
endmodule

// 10:1 DDR serializer (LSB first) and TMDS_33 differential buffer.
module tmds_serializer(input wire pclk, input wire sclk, input wire rst, input wire [9:0] word, output wire p, output wire n);
    wire oq, shift1, shift2;
    OSERDESE2 #(.DATA_RATE_OQ("DDR"), .DATA_RATE_TQ("SDR"), .DATA_WIDTH(10), .SERDES_MODE("MASTER"),
                .TRISTATE_WIDTH(1), .TBYTE_CTL("FALSE"), .TBYTE_SRC("FALSE")) master(
        .OQ(oq), .OFB(), .TQ(), .TFB(), .SHIFTOUT1(), .SHIFTOUT2(), .TBYTEOUT(),
        .CLK(sclk), .CLKDIV(pclk), .D1(word[0]), .D2(word[1]), .D3(word[2]), .D4(word[3]),
        .D5(word[4]), .D6(word[5]), .D7(word[6]), .D8(word[7]), .OCE(1'b1), .RST(rst),
        .SHIFTIN1(shift1), .SHIFTIN2(shift2), .T1(1'b0), .T2(1'b0), .T3(1'b0), .T4(1'b0), .TBYTEIN(1'b0), .TCE(1'b0));
    OSERDESE2 #(.DATA_RATE_OQ("DDR"), .DATA_RATE_TQ("SDR"), .DATA_WIDTH(10), .SERDES_MODE("SLAVE"),
                .TRISTATE_WIDTH(1), .TBYTE_CTL("FALSE"), .TBYTE_SRC("FALSE")) slave(
        .OQ(), .OFB(), .TQ(), .TFB(), .SHIFTOUT1(shift1), .SHIFTOUT2(shift2), .TBYTEOUT(),
        .CLK(sclk), .CLKDIV(pclk), .D1(1'b0), .D2(1'b0), .D3(word[8]), .D4(word[9]),
        .D5(1'b0), .D6(1'b0), .D7(1'b0), .D8(1'b0), .OCE(1'b1), .RST(rst),
        .SHIFTIN1(1'b0), .SHIFTIN2(1'b0), .T1(1'b0), .T2(1'b0), .T3(1'b0), .T4(1'b0), .TBYTEIN(1'b0), .TCE(1'b0));
    OBUFDS buffer(.I(oq), .O(p), .OB(n));
endmodule
