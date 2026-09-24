`timescale 1ns/1ps
// Open-source flow top level for AX7020: PS7, FCLK0 buffer, reset
// synchronizer (proc_sys_reset), video MMCM (clk_wiz) and oss_fabric.
// PS configuration (DDR, MIO, FCLK0 = 100 MHz, UART1, SD0, 64-bit HP0) comes
// from ps7_init executed by the FSBL, as in the Vivado design.
module top(
    input wire [3:0] mic_sd, output wire mic_bclk, output wire mic_ws,
    output wire led_da, output wire led_ck,
    output wire hdmi_clk_p, output wire hdmi_clk_n, output wire [2:0] hdmi_data_p, output wire [2:0] hdmi_data_n,
    input wire hdmi_hpd, output wire hdmi_out_en
);
    wire [3:0] fclk, fclk_resetn;
    wire aclk;
    BUFG fclk_buffer(.I(fclk[0]), .O(aclk));

    // proc_sys_reset equivalent: synchronize FCLK_RESET0_N, then hold
    // peripherals in reset 16 more cycles.
    (* ASYNC_REG="TRUE" *) reg [1:0] reset_sync = 2'b00;
    reg [4:0] reset_count = 0;
    reg aresetn = 0;
    always @(posedge aclk) begin
        reset_sync <= {reset_sync[0], fclk_resetn[0]};
        if(!reset_sync[1]) begin reset_count <= 0; aresetn <= 0; end
        else if(!reset_count[4]) reset_count <= reset_count + 1;
        else aresetn <= 1;
    end

    // Video clocks: 100 MHz * 37.125 / 5 = 742.5 MHz VCO; /10 = 74.25 MHz
    // pixel clock, /2 = 371.25 MHz serial clock (Vivado clk_wiz settings).
    // CLKIN2 is unused (CLKINSEL=1); build.sh drops nextpnr's CLKIN2 tie-off
    // route from the FASM, see there.
    wire feedback, pixel_raw, serial_raw, pclk, sclk, locked;
    MMCME2_ADV #(.BANDWIDTH("OPTIMIZED"), .CLKIN1_PERIOD(10.0), .DIVCLK_DIVIDE(5), .CLKFBOUT_MULT_F(37.125),
                 .CLKOUT0_DIVIDE_F(10.0), .CLKOUT1_DIVIDE(2), .STARTUP_WAIT("FALSE")) video_mmcm(
        .CLKIN1(aclk), .CLKINSEL(1'b1), .CLKFBIN(feedback), .CLKFBOUT(feedback),
        .CLKOUT0(pixel_raw), .CLKOUT1(serial_raw), .LOCKED(locked), .RST(1'b0), .PWRDWN(1'b0),
        .DADDR(7'd0), .DCLK(1'b0), .DEN(1'b0), .DI(16'd0), .DWE(1'b0),
        .PSCLK(1'b0), .PSEN(1'b0), .PSINCDEC(1'b0));
    BUFG pixel_buffer(.I(pixel_raw), .O(pclk));
    BUFG serial_buffer(.I(serial_raw), .O(sclk));

    // PS7 interfaces
    wire [11:0] gp_awid, gp_wid, gp_arid, gp_bid, gp_rid;
    wire [31:0] gp_awaddr, gp_wdata, gp_araddr, gp_rdata;
    wire [3:0] gp_awlen, gp_arlen, gp_wstrb;
    wire [1:0] gp_awsize, gp_arsize, gp_awburst, gp_arburst, gp_bresp, gp_rresp;
    wire gp_awvalid, gp_awready, gp_wlast, gp_wvalid, gp_wready, gp_bvalid, gp_bready;
    wire gp_arvalid, gp_arready, gp_rlast, gp_rvalid, gp_rready;
    wire [31:0] hp_awaddr; wire [3:0] hp_awlen, hp_awcache; wire [1:0] hp_awsize, hp_awburst, hp_bresp;
    wire [63:0] hp_wdata; wire [7:0] hp_wstrb;
    wire hp_awvalid, hp_awready, hp_wlast, hp_wvalid, hp_wready, hp_bvalid, hp_bready;
    PS7 ps7(
        .FCLKCLK(fclk), .FCLKRESETN(fclk_resetn),
        .MAXIGP0ACLK(aclk),
        .MAXIGP0AWID(gp_awid), .MAXIGP0AWADDR(gp_awaddr), .MAXIGP0AWLEN(gp_awlen), .MAXIGP0AWSIZE(gp_awsize),
        .MAXIGP0AWBURST(gp_awburst), .MAXIGP0AWVALID(gp_awvalid), .MAXIGP0AWREADY(gp_awready),
        .MAXIGP0WID(gp_wid), .MAXIGP0WDATA(gp_wdata), .MAXIGP0WSTRB(gp_wstrb), .MAXIGP0WLAST(gp_wlast),
        .MAXIGP0WVALID(gp_wvalid), .MAXIGP0WREADY(gp_wready),
        .MAXIGP0BID(gp_bid), .MAXIGP0BRESP(gp_bresp), .MAXIGP0BVALID(gp_bvalid), .MAXIGP0BREADY(gp_bready),
        .MAXIGP0ARID(gp_arid), .MAXIGP0ARADDR(gp_araddr), .MAXIGP0ARLEN(gp_arlen), .MAXIGP0ARSIZE(gp_arsize),
        .MAXIGP0ARBURST(gp_arburst), .MAXIGP0ARVALID(gp_arvalid), .MAXIGP0ARREADY(gp_arready),
        .MAXIGP0RID(gp_rid), .MAXIGP0RDATA(gp_rdata), .MAXIGP0RRESP(gp_rresp), .MAXIGP0RLAST(gp_rlast),
        .MAXIGP0RVALID(gp_rvalid), .MAXIGP0RREADY(gp_rready),
        .SAXIHP0ACLK(aclk),
        .SAXIHP0AWID(6'd0), .SAXIHP0AWADDR(hp_awaddr), .SAXIHP0AWLEN(hp_awlen), .SAXIHP0AWSIZE(hp_awsize),
        .SAXIHP0AWBURST(hp_awburst), .SAXIHP0AWCACHE(hp_awcache), .SAXIHP0AWLOCK(2'd0), .SAXIHP0AWPROT(3'd0),
        .SAXIHP0AWQOS(4'd0), .SAXIHP0AWVALID(hp_awvalid), .SAXIHP0AWREADY(hp_awready),
        .SAXIHP0WID(6'd0), .SAXIHP0WDATA(hp_wdata), .SAXIHP0WSTRB(hp_wstrb), .SAXIHP0WLAST(hp_wlast),
        .SAXIHP0WVALID(hp_wvalid), .SAXIHP0WREADY(hp_wready),
        .SAXIHP0BRESP(hp_bresp), .SAXIHP0BVALID(hp_bvalid), .SAXIHP0BREADY(hp_bready),
        .SAXIHP0ARID(6'd0), .SAXIHP0ARADDR(32'd0), .SAXIHP0ARLEN(4'd0), .SAXIHP0ARSIZE(2'd0),
        .SAXIHP0ARBURST(2'd0), .SAXIHP0ARCACHE(4'd0), .SAXIHP0ARLOCK(2'd0), .SAXIHP0ARPROT(3'd0),
        .SAXIHP0ARQOS(4'd0), .SAXIHP0ARVALID(1'b0), .SAXIHP0RREADY(1'b0),
        .SAXIHP0RDISSUECAP1EN(1'b0), .SAXIHP0WRISSUECAP1EN(1'b0));

    oss_fabric fabric(
        .aclk(aclk), .aresetn(aresetn),
        .gp_awid(gp_awid), .gp_awaddr(gp_awaddr), .gp_awlen(gp_awlen), .gp_awsize(gp_awsize), .gp_awburst(gp_awburst),
        .gp_awvalid(gp_awvalid), .gp_awready(gp_awready), .gp_wid(gp_wid), .gp_wdata(gp_wdata), .gp_wstrb(gp_wstrb),
        .gp_wlast(gp_wlast), .gp_wvalid(gp_wvalid), .gp_wready(gp_wready),
        .gp_bid(gp_bid), .gp_bresp(gp_bresp), .gp_bvalid(gp_bvalid), .gp_bready(gp_bready),
        .gp_arid(gp_arid), .gp_araddr(gp_araddr), .gp_arlen(gp_arlen), .gp_arsize(gp_arsize), .gp_arburst(gp_arburst),
        .gp_arvalid(gp_arvalid), .gp_arready(gp_arready),
        .gp_rid(gp_rid), .gp_rdata(gp_rdata), .gp_rresp(gp_rresp), .gp_rlast(gp_rlast), .gp_rvalid(gp_rvalid), .gp_rready(gp_rready),
        .hp_awaddr(hp_awaddr), .hp_awlen(hp_awlen), .hp_awsize(hp_awsize), .hp_awburst(hp_awburst), .hp_awcache(hp_awcache),
        .hp_awvalid(hp_awvalid), .hp_awready(hp_awready), .hp_wdata(hp_wdata), .hp_wstrb(hp_wstrb), .hp_wlast(hp_wlast),
        .hp_wvalid(hp_wvalid), .hp_wready(hp_wready), .hp_bresp(hp_bresp), .hp_bvalid(hp_bvalid), .hp_bready(hp_bready),
        .pclk(pclk), .sclk(sclk), .locked(locked),
        .mic_sd(mic_sd), .mic_bclk(mic_bclk), .mic_ws(mic_ws), .led_da(led_da), .led_ck(led_ck),
        .hdmi_clk_p(hdmi_clk_p), .hdmi_clk_n(hdmi_clk_n), .hdmi_data_p(hdmi_data_p), .hdmi_data_n(hdmi_data_n),
        .hdmi_hpd(hdmi_hpd), .hdmi_out_en(hdmi_out_en));
endmodule
