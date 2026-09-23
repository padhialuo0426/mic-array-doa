`timescale 1ns/1ps
module hdmi_display(
    (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 aclk CLK", X_INTERFACE_PARAMETER="ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET aresetn, FREQ_HZ 100000000" *) input wire aclk,
    (* X_INTERFACE_INFO="xilinx.com:signal:reset:1.0 aresetn RST", X_INTERFACE_PARAMETER="POLARITY ACTIVE_LOW" *) input wire aresetn,
    (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 pclk CLK", X_INTERFACE_PARAMETER="FREQ_HZ 74250000" *) input wire pclk,
    (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 sclk CLK", X_INTERFACE_PARAMETER="FREQ_HZ 371250000" *) input wire sclk,
    input wire locked,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWADDR", X_INTERFACE_PARAMETER="PROTOCOL AXI4LITE, ADDR_WIDTH 18, DATA_WIDTH 32" *) input wire [17:0] s_axi_awaddr,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *) input wire s_axi_awvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *) output wire s_axi_awready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WDATA" *) input wire [31:0] s_axi_wdata,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *) input wire [3:0] s_axi_wstrb,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WVALID" *) input wire s_axi_wvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WREADY" *) output wire s_axi_wready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI BRESP" *) output wire [1:0] s_axi_bresp,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI BVALID" *) output wire s_axi_bvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI BREADY" *) input wire s_axi_bready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *) input wire [17:0] s_axi_araddr,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *) input wire s_axi_arvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *) output wire s_axi_arready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RDATA" *) output wire [31:0] s_axi_rdata,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RRESP" *) output wire [1:0] s_axi_rresp,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RVALID" *) output wire s_axi_rvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RREADY" *) input wire s_axi_rready,
    (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 hdmi_clk_p CLK", X_INTERFACE_PARAMETER="FREQ_HZ 74250000" *) output wire hdmi_clk_p,
    (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 hdmi_clk_n CLK", X_INTERFACE_PARAMETER="FREQ_HZ 74250000" *) output wire hdmi_clk_n,
    output wire [2:0] hdmi_data_p,hdmi_data_n,
    input wire hdmi_hpd,output wire hdmi_out_en
);
    (* ASYNC_REG="TRUE" *) reg [2:0] reset_pipe;
    wire arst=!aresetn||!locked;
    always @(posedge pclk or posedge arst)begin
        if(arst)reset_pipe<=0;else reset_pipe<={reset_pipe[1:0],1'b1};
    end
    wire presetn=reset_pipe[2];
    wire [14:0] addr;wire [31:0] pixels;wire bars,visible,boundary;
    wire [23:0] rgb;wire hs,vs,de;
    assign hdmi_out_en=1'b1; // TPS2051B active-high enable; output supplies sink +5 V.
    video_canvas canvas(
        .aclk(aclk),.aresetn(aresetn),.pclk(pclk),.presetn(presetn),.locked(locked),.hpd(hdmi_hpd),
        .awaddr(s_axi_awaddr),.awvalid(s_axi_awvalid),.awready(s_axi_awready),
        .wdata(s_axi_wdata),.wstrb(s_axi_wstrb),.wvalid(s_axi_wvalid),.wready(s_axi_wready),
        .bresp(s_axi_bresp),.bvalid(s_axi_bvalid),.bready(s_axi_bready),
        .araddr(s_axi_araddr),.arvalid(s_axi_arvalid),.arready(s_axi_arready),
        .rdata(s_axi_rdata),.rresp(s_axi_rresp),.rvalid(s_axi_rvalid),.rready(s_axi_rready),
        .pixel_addr(addr),.pixel_data(pixels),.frame_boundary(boundary),.bars(bars),.visible(visible));
    video_scan scan(.pclk(pclk),.resetn(presetn),.word_addr(addr),.word_data(pixels),
        .bars(bars),.visible(visible),.frame_boundary(boundary),.rgb(rgb),.hsync(hs),.vsync(vs),.de(de));
    // Digilent's input bus is R-B-G, not the conventional R-G-B ordering.
    rgb2dvi #(.kGenerateSerialClk(0),.kRstActiveHigh(1)) encoder(
        .PixelClk(pclk),.SerialClk(sclk),.aRst(!presetn),.aRst_n(presetn),
        .vid_pData({rgb[23:16],rgb[7:0],rgb[15:8]}),.vid_pVDE(de),.vid_pHSync(hs),.vid_pVSync(vs),
        .TMDS_Clk_p(hdmi_clk_p),.TMDS_Clk_n(hdmi_clk_n),.TMDS_Data_p(hdmi_data_p),.TMDS_Data_n(hdmi_data_n));
endmodule
