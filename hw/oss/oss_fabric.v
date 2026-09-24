`timescale 1ns/1ps
// All programmable logic of the Vivado block design except the PS7, clock
// buffers and MMCM, for the open-source flow. Address map and data path are
// those of hw/build.tcl:
//   0x4040_0000 64 KiB  s2mm_dma registers (replaces axi_dma)
//   0x43C0_0000 64 KiB  mic_capture
//   0x43C1_0000 64 KiB  sk9822_driver
//   0x43C4_0000 256 KiB hdmi_display
//   capture -> axis_fifo (4096) -> s2mm_dma -> HP0 (64-bit AXI3)
// Other GP0 addresses return DECERR, as the Vivado interconnect does.
module oss_fabric(
    input wire aclk, input wire aresetn,
    // PS7 M_AXI_GP0 (AXI3, 32-bit)
    input wire [11:0] gp_awid, input wire [31:0] gp_awaddr, input wire [3:0] gp_awlen, input wire [1:0] gp_awsize,
    input wire [1:0] gp_awburst, input wire gp_awvalid, output wire gp_awready,
    input wire [11:0] gp_wid, input wire [31:0] gp_wdata, input wire [3:0] gp_wstrb, input wire gp_wlast,
    input wire gp_wvalid, output wire gp_wready,
    output wire [11:0] gp_bid, output wire [1:0] gp_bresp, output wire gp_bvalid, input wire gp_bready,
    input wire [11:0] gp_arid, input wire [31:0] gp_araddr, input wire [3:0] gp_arlen, input wire [1:0] gp_arsize,
    input wire [1:0] gp_arburst, input wire gp_arvalid, output wire gp_arready,
    output wire [11:0] gp_rid, output wire [31:0] gp_rdata, output wire [1:0] gp_rresp, output wire gp_rlast,
    output wire gp_rvalid, input wire gp_rready,
    // PS7 S_AXI_HP0 write channels (AXI3, 64-bit)
    output wire [31:0] hp_awaddr, output wire [3:0] hp_awlen, output wire [1:0] hp_awsize, output wire [1:0] hp_awburst,
    output wire [3:0] hp_awcache, output wire hp_awvalid, input wire hp_awready,
    output wire [63:0] hp_wdata, output wire [7:0] hp_wstrb, output wire hp_wlast, output wire hp_wvalid, input wire hp_wready,
    input wire [1:0] hp_bresp, input wire hp_bvalid, output wire hp_bready,
    // Video clocks from the MMCM
    input wire pclk, input wire sclk, input wire locked,
    // Pins
    input wire [3:0] mic_sd, output wire mic_bclk, output wire mic_ws,
    output wire led_da, output wire led_ck,
    output wire hdmi_clk_p, output wire hdmi_clk_n, output wire [2:0] hdmi_data_p, output wire [2:0] hdmi_data_n,
    input wire hdmi_hpd, output wire hdmi_out_en
);
    // GP0 -> single AXI-Lite master
    wire [31:0] awaddr, wdata, araddr; wire [3:0] wstrb;
    wire awvalid, wvalid, arvalid, bready, rready;
    reg awready, wready, arready, bvalid, rvalid; reg [1:0] bresp, rresp; reg [31:0] rdata;
    axi3_lite_bridge bridge(
        .aclk(aclk), .aresetn(aresetn),
        .s_awid(gp_awid), .s_awaddr(gp_awaddr), .s_awlen(gp_awlen), .s_awsize(gp_awsize), .s_awburst(gp_awburst),
        .s_awvalid(gp_awvalid), .s_awready(gp_awready), .s_wid(gp_wid), .s_wdata(gp_wdata), .s_wstrb(gp_wstrb),
        .s_wlast(gp_wlast), .s_wvalid(gp_wvalid), .s_wready(gp_wready),
        .s_bid(gp_bid), .s_bresp(gp_bresp), .s_bvalid(gp_bvalid), .s_bready(gp_bready),
        .s_arid(gp_arid), .s_araddr(gp_araddr), .s_arlen(gp_arlen), .s_arsize(gp_arsize), .s_arburst(gp_arburst),
        .s_arvalid(gp_arvalid), .s_arready(gp_arready),
        .s_rid(gp_rid), .s_rdata(gp_rdata), .s_rresp(gp_rresp), .s_rlast(gp_rlast), .s_rvalid(gp_rvalid), .s_rready(gp_rready),
        .m_awaddr(awaddr), .m_awvalid(awvalid), .m_awready(awready), .m_wdata(wdata), .m_wstrb(wstrb),
        .m_wvalid(wvalid), .m_wready(wready), .m_bresp(bresp), .m_bvalid(bvalid), .m_bready(bready),
        .m_araddr(araddr), .m_arvalid(arvalid), .m_arready(arready),
        .m_rdata(rdata), .m_rresp(rresp), .m_rvalid(rvalid), .m_rready(rready));

    // Decoder: the bridge keeps one transaction and a stable address.
    function [2:0] slave_of; input [31:0] a;
        slave_of = a[31:16]==16'h4040 ? 3'd0 : a[31:16]==16'h43C0 ? 3'd1 : a[31:16]==16'h43C1 ? 3'd2 :
                   a[31:18]==14'h10F1 ? 3'd3 : 3'd4;
    endfunction
    // Registered decode: the bridge holds each address a cycle before valid.
    reg [2:0] ws, rs;
    always @(posedge aclk) begin ws <= slave_of(awaddr); rs <= slave_of(araddr); end
    wire [4:0] s_awready, s_wready, s_bvalid, s_arready, s_rvalid;
    wire [1:0] s_bresp [0:4]; wire [1:0] s_rresp [0:4]; wire [31:0] s_rdata [0:4];
    always @(*) begin
        awready = s_awready[ws]; wready = s_wready[ws]; bvalid = s_bvalid[ws]; bresp = s_bresp[ws];
        arready = s_arready[rs]; rvalid = s_rvalid[rs]; rresp = s_rresp[rs]; rdata = s_rdata[rs];
    end
    wire [4:0] aw_sel = awvalid ? (5'd1 << ws) : 5'd0, w_sel = wvalid ? (5'd1 << ws) : 5'd0;
    wire [4:0] b_sel = bready ? (5'd1 << ws) : 5'd0, ar_sel = arvalid ? (5'd1 << rs) : 5'd0;
    wire [4:0] r_sel = rready ? (5'd1 << rs) : 5'd0;

    // Unmapped: DECERR responder.
    reg dec_aw, dec_w, dec_b, dec_r;
    assign s_awready[4] = !dec_aw && !dec_b; assign s_wready[4] = !dec_w && !dec_b;
    assign s_bvalid[4] = dec_b; assign s_bresp[4] = 2'b11;
    assign s_arready[4] = !dec_r; assign s_rvalid[4] = dec_r; assign s_rresp[4] = 2'b11; assign s_rdata[4] = 0;
    always @(posedge aclk) begin
        if(!aresetn) begin dec_aw<=0; dec_w<=0; dec_b<=0; dec_r<=0; end
        else begin
            if(aw_sel[4] && s_awready[4]) dec_aw<=1;
            if(w_sel[4] && s_wready[4]) dec_w<=1;
            if(dec_aw && dec_w && !dec_b) begin dec_b<=1; dec_aw<=0; dec_w<=0; end
            if(dec_b && b_sel[4]) dec_b<=0;
            if(ar_sel[4] && s_arready[4]) dec_r<=1;
            else if(dec_r && r_sel[4]) dec_r<=0;
        end
    end

    // Stream path
    wire [31:0] cap_tdata, fifo_tdata; wire [3:0] cap_tkeep;
    wire cap_tvalid, cap_tready, cap_tlast, fifo_tvalid, fifo_tready, fifo_tlast;
    s2mm_dma dma(
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_awaddr(awaddr[15:0]), .s_axi_awvalid(aw_sel[0]), .s_axi_awready(s_awready[0]),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(w_sel[0]), .s_axi_wready(s_wready[0]),
        .s_axi_bresp(s_bresp[0]), .s_axi_bvalid(s_bvalid[0]), .s_axi_bready(b_sel[0]),
        .s_axi_araddr(araddr[15:0]), .s_axi_arvalid(ar_sel[0]), .s_axi_arready(s_arready[0]),
        .s_axi_rdata(s_rdata[0]), .s_axi_rresp(s_rresp[0]), .s_axi_rvalid(s_rvalid[0]), .s_axi_rready(r_sel[0]),
        .s_axis_tdata(fifo_tdata), .s_axis_tlast(fifo_tlast), .s_axis_tvalid(fifo_tvalid), .s_axis_tready(fifo_tready),
        .m_awaddr(hp_awaddr), .m_awlen(hp_awlen), .m_awsize(hp_awsize), .m_awburst(hp_awburst), .m_awcache(hp_awcache),
        .m_awvalid(hp_awvalid), .m_awready(hp_awready), .m_wdata(hp_wdata), .m_wstrb(hp_wstrb), .m_wlast(hp_wlast),
        .m_wvalid(hp_wvalid), .m_wready(hp_wready), .m_bresp(hp_bresp), .m_bvalid(hp_bvalid), .m_bready(hp_bready));
    mic_capture capture(
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_awaddr(awaddr[5:0]), .s_axi_awvalid(aw_sel[1]), .s_axi_awready(s_awready[1]),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(w_sel[1]), .s_axi_wready(s_wready[1]),
        .s_axi_bresp(s_bresp[1]), .s_axi_bvalid(s_bvalid[1]), .s_axi_bready(b_sel[1]),
        .s_axi_araddr(araddr[5:0]), .s_axi_arvalid(ar_sel[1]), .s_axi_arready(s_arready[1]),
        .s_axi_rdata(s_rdata[1]), .s_axi_rresp(s_rresp[1]), .s_axi_rvalid(s_rvalid[1]), .s_axi_rready(r_sel[1]),
        .m_axis_tdata(cap_tdata), .m_axis_tkeep(cap_tkeep), .m_axis_tvalid(cap_tvalid), .m_axis_tready(cap_tready),
        .m_axis_tlast(cap_tlast), .mic_sd(mic_sd), .mic_bclk(mic_bclk), .mic_ws(mic_ws));
    axis_fifo fifo(
        .aclk(aclk), .aresetn(aresetn),
        .s_tdata(cap_tdata), .s_tlast(cap_tlast), .s_tvalid(cap_tvalid), .s_tready(cap_tready),
        .m_tdata(fifo_tdata), .m_tlast(fifo_tlast), .m_tvalid(fifo_tvalid), .m_tready(fifo_tready));
    sk9822_driver leds(
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_awaddr(awaddr[5:0]), .s_axi_awvalid(aw_sel[2]), .s_axi_awready(s_awready[2]),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(w_sel[2]), .s_axi_wready(s_wready[2]),
        .s_axi_bresp(s_bresp[2]), .s_axi_bvalid(s_bvalid[2]), .s_axi_bready(b_sel[2]),
        .s_axi_araddr(araddr[5:0]), .s_axi_arvalid(ar_sel[2]), .s_axi_arready(s_arready[2]),
        .s_axi_rdata(s_rdata[2]), .s_axi_rresp(s_rresp[2]), .s_axi_rvalid(s_rvalid[2]), .s_axi_rready(r_sel[2]),
        .led_da(led_da), .led_ck(led_ck));
    hdmi_display video(
        .aclk(aclk), .aresetn(aresetn), .pclk(pclk), .sclk(sclk), .locked(locked),
        .s_axi_awaddr(awaddr[17:0]), .s_axi_awvalid(aw_sel[3]), .s_axi_awready(s_awready[3]),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(w_sel[3]), .s_axi_wready(s_wready[3]),
        .s_axi_bresp(s_bresp[3]), .s_axi_bvalid(s_bvalid[3]), .s_axi_bready(b_sel[3]),
        .s_axi_araddr(araddr[17:0]), .s_axi_arvalid(ar_sel[3]), .s_axi_arready(s_arready[3]),
        .s_axi_rdata(s_rdata[3]), .s_axi_rresp(s_rresp[3]), .s_axi_rvalid(s_rvalid[3]), .s_axi_rready(r_sel[3]),
        .hdmi_clk_p(hdmi_clk_p), .hdmi_clk_n(hdmi_clk_n), .hdmi_data_p(hdmi_data_p), .hdmi_data_n(hdmi_data_n),
        .hdmi_hpd(hdmi_hpd), .hdmi_out_en(hdmi_out_en));
endmodule
