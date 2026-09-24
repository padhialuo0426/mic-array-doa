`timescale 1ns/1ps
// Twelve SK9822 LEDs: 32 zero start bits, 12 BGR frames, 32 zero latch
// bits and 32 ZERO end clocks. Ones after the SK9822 reset would look like
// an extra full-white first-pixel frame. A refresh is an atomic snapshot.
// See cpldcpu's measured SK9822/APA102 unified protocol.
// The output
// enforces <= 4/31 global brightness and <= two nonblack pixels in hardware.
module sk9822_driver #(
    parameter integer HALF_PERIOD=50,
    parameter integer WATCHDOG_CYCLES=100000000
)(
    (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 aclk CLK", X_INTERFACE_PARAMETER="ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET aresetn, FREQ_HZ 100000000" *) input wire aclk,
    (* X_INTERFACE_INFO="xilinx.com:signal:reset:1.0 aresetn RST", X_INTERFACE_PARAMETER="POLARITY ACTIVE_LOW" *) input wire aresetn,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWADDR", X_INTERFACE_PARAMETER="PROTOCOL AXI4LITE, ADDR_WIDTH 6, DATA_WIDTH 32" *) input wire [5:0] s_axi_awaddr,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *) input wire s_axi_awvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *) output wire s_axi_awready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WDATA" *) input wire [31:0] s_axi_wdata,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *) input wire [3:0] s_axi_wstrb,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WVALID" *) input wire s_axi_wvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WREADY" *) output wire s_axi_wready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI BRESP" *) output wire [1:0] s_axi_bresp,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI BVALID" *) output reg s_axi_bvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI BREADY" *) input wire s_axi_bready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *) input wire [5:0] s_axi_araddr,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *) input wire s_axi_arvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *) output wire s_axi_arready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RDATA" *) output reg [31:0] s_axi_rdata,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RRESP" *) output wire [1:0] s_axi_rresp,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RVALID" *) output reg s_axi_rvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RREADY" *) input wire s_axi_rready,
    output wire led_da, output reg led_ck
);
    reg [31:0] pixels [0:11];
    reg [5:0] awaddr;
    reg [31:0] wdata;
    reg [3:0] wstrb;
    reg aw_pending,w_pending,request,request_blank;
    reg busy,expired,rejected,blank_pending;
    // go/go_black: the refresh decision registered one cycle ahead, so the
    // 480-bit parallel load is selected by flip-flops, not by request logic.
    reg go,go_black;
    reg last_bit; // registered bit_index==479
    reg tick; // registered (divider==HALF_PERIOD-1): the 480-bit shift enable starts at a flip-flop
    reg [31:0] divider,age;
    reg [8:0] bit_index;
    reg [479:0] shift;
    reg [479:0] frame, frame_q; // frame_q: registered copy, cuts the 12-pixel clamp chain
    reg [4:0] brightness;
    integer i,j,b;
    // Pixel i is shown if it is nonblack and fewer than two earlier pixels are:
    // any_before/two_before are pure boolean prefixes of valid[], no adders.
    reg [11:0] valid, valid_q, any_before, two_before;
    localparam [479:0] BLACK_FRAME={32'b0,{12{32'he0000000}},64'b0};
    always @* begin
        for(i=0;i<12;i=i+1) valid[i]=pixels[i][28:24]!=0 && pixels[i][23:0]!=0;
        any_before[0]=0; two_before[0]=0;
        for(i=1;i<12;i=i+1) begin
            any_before[i]=any_before[i-1] | valid_q[i-1];
            two_before[i]=two_before[i-1] | (any_before[i-1] & valid_q[i-1]);
        end
        frame=BLACK_FRAME;brightness=0;
        for(i=0;i<12;i=i+1) begin
            brightness=pixels[i][28:24]>4 ? 5'd4 : pixels[i][28:24];
            if(valid_q[i] && !two_before[i]) frame[447-i*32 -: 32]={3'b111,brightness,pixels[i][23:0]};
        end
    end
    // Two register stages (valid_q, frame_q) keep the snapshot logic within
    // 100 MHz in both flows. A refresh request follows the last pixel write by
    // at least five bus cycles, so frame_q is still the snapshot when go loads it.
    always @(posedge aclk) begin valid_q<=valid; frame_q<=frame; end
    assign led_da=busy ? shift[479] : 1'b0;
    assign s_axi_awready=!aw_pending && !s_axi_bvalid;
    assign s_axi_wready=!w_pending && !s_axi_bvalid;
    assign s_axi_bresp=0;
    assign s_axi_arready=!s_axi_rvalid;
    assign s_axi_rresp=0;
    always @(posedge aclk) begin
        if(!aresetn) begin
            aw_pending<=0;w_pending<=0;awaddr<=0;wdata<=0;wstrb<=0;
            s_axi_bvalid<=0;s_axi_rvalid<=0;s_axi_rdata<=0;
            request<=0;request_blank<=0;
            for(j=0;j<12;j=j+1) pixels[j]<=0;
        end else begin
            request<=0;
            if(s_axi_awvalid && s_axi_awready) begin awaddr<=s_axi_awaddr;aw_pending<=1;end
            if(s_axi_wvalid && s_axi_wready) begin wdata<=s_axi_wdata;wstrb<=s_axi_wstrb;w_pending<=1;end
            if(s_axi_bvalid && s_axi_bready) s_axi_bvalid<=0;
            if(aw_pending && w_pending && !s_axi_bvalid) begin
                if(awaddr[5:2]==0 && wstrb[0] && (wdata[0] || wdata[1])) begin
                    request<=1;request_blank<=wdata[1];
                end
                if(awaddr[5:2]>=4) begin
                    for(b=0;b<4;b=b+1) if(wstrb[b]) pixels[awaddr[5:2]-4][8*b +: 8]<=wdata[8*b +: 8];
                end
                aw_pending<=0;w_pending<=0;s_axi_bvalid<=1;
            end
            if(s_axi_rvalid && s_axi_rready) s_axi_rvalid<=0;
            if(s_axi_arvalid && s_axi_arready) begin
                s_axi_rvalid<=1;
                case(s_axi_araddr[5:2])
                    0:s_axi_rdata<=0;
                    1:s_axi_rdata<={29'b0,rejected,expired,busy};
                    2:s_axi_rdata<=32'h4c454431;
                    3:s_axi_rdata<=WATCHDOG_CYCLES;
                    default:s_axi_rdata<=pixels[s_axi_araddr[5:2]-4];
                endcase
            end
        end
    end
    always @(posedge aclk) begin
        if(!aresetn) begin
            busy<=0;expired<=1;rejected<=0;blank_pending<=1;go<=0;go_black<=1;last_bit<=0;
            divider<=0;tick<=(HALF_PERIOD==1);age<=0;bit_index<=0;shift<=BLACK_FRAME;led_ck<=0;
        end else begin
            if(!expired) begin
                if(age>=WATCHDOG_CYCLES-1) begin expired<=1;blank_pending<=1;end
                else age<=age+1'b1;
            end
            go<=0;
            if(request && (busy || go)) rejected<=1;
            if(!busy && !go && (request || blank_pending)) begin
                go<=1;go_black<=!request || request_blank;blank_pending<=0;
                if(request) begin age<=0;expired<=0;rejected<=0;end
            end
            if(go) begin
                shift<=go_black ? BLACK_FRAME : frame_q;
                busy<=1;divider<=0;tick<=(HALF_PERIOD==1);bit_index<=0;last_bit<=0;led_ck<=0;
            end else if(busy) begin
                if(tick) begin
                    divider<=0;tick<=(HALF_PERIOD==1);
                    if(!led_ck) led_ck<=1;
                    else begin
                        led_ck<=0;
                        if(last_bit) busy<=0;
                        else begin shift<={shift[478:0],1'b0};bit_index<=bit_index+1'b1;last_bit<=bit_index==478;end
                    end
                end else begin divider<=divider+1'b1;tick<=(divider+1'b1==HALF_PERIOD-1);end
            end
        end
    end
endmodule
