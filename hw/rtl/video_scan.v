`timescale 1ns/1ps
// 720p60, positive sync. 640x360 indexed canvas is doubled in both axes.
// BRAM data, nibble select, sync and DE travel through the same two stages.
module video_scan #(
    parameter H_ACTIVE=1280,H_TOTAL=1650,H_SYNC_START=1390,H_SYNC_END=1430,
    parameter V_ACTIVE=720,V_TOTAL=750,V_SYNC_START=725,V_SYNC_END=730
)(input wire pclk,resetn,
  output wire [14:0] word_addr,input wire [31:0] word_data,
  input wire bars,visible,output wire frame_boundary,
  output reg [23:0] rgb,output reg hsync,vsync,de);
    reg [10:0] x;reg [9:0] y;
    reg [2:0] nibble;reg hs1,vs1,de1;
    reg [23:0] bar1;
    assign word_addr=(y[9:1]*15'd80)+{8'b0,x[10:4]};
    assign frame_boundary=(x==0 && y==V_ACTIVE);
    function [23:0] palette;
        input [3:0] c;
        begin case(c)
            0:palette=24'h0b151d; 1:palette=24'h101f29;
            2:palette=24'h29434f; 3:palette=24'h718f9e;
            4:palette=24'hb0c8d3; 5:palette=24'he4f0f3;
            6:palette=24'h143e37; 7:palette=24'h1d6754;
            8:palette=24'h2e9c78; 9:palette=24'h54efbb;
            10:palette=24'h193954;11:palette=24'h71c8ff;
            12:palette=24'hf2c879;13:palette=24'he77878;
            14:palette=24'h987bd3;15:palette=24'hffffff;
        endcase end
    endfunction
    always @(posedge pclk) begin
        if(!resetn) begin
            x<=0;y<=0;nibble<=0;hs1<=0;vs1<=0;de1<=0;bar1<=0;
            rgb<=0;hsync<=0;vsync<=0;de<=0;
        end else begin
            if(x==H_TOTAL-1) begin x<=0;if(y==V_TOTAL-1)y<=0;else y<=y+1'b1;end
            else x<=x+1'b1;
            nibble<=x[3:1];hs1<=x>=H_SYNC_START&&x<H_SYNC_END;
            vs1<=y>=V_SYNC_START&&y<V_SYNC_END;de1<=x<H_ACTIVE&&y<V_ACTIVE;
            if(x<160)bar1<=24'hffffff;
            else if(x<320)bar1<=24'hffff00;
            else if(x<480)bar1<=24'h00ffff;
            else if(x<640)bar1<=24'h00ff00;
            else if(x<800)bar1<=24'hff00ff;
            else if(x<960)bar1<=24'hff0000;
            else if(x<1120)bar1<=24'h0000ff;else bar1<=0;
            hsync<=hs1;vsync<=vs1;de<=de1;
            rgb<=!de1?24'b0:(bars?bar1:(visible?palette(word_data[nibble*4 +: 4]):24'h0b151d));
        end
    end
endmodule
