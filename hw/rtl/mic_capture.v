`timescale 1ns/1ps
module mic_capture #(
    parameter integer BCLK_DIV=96,
    parameter integer WARMUP_FRAMES=2048,
    parameter integer FRAMES_PER_PKT=256
)(
    (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 aclk CLK", X_INTERFACE_PARAMETER="ASSOCIATED_BUSIF S_AXI:M_AXIS, ASSOCIATED_RESET aresetn, FREQ_HZ 100000000" *) input wire aclk,
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
    (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 M_AXIS TDATA" *) output wire [31:0] m_axis_tdata,
    (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 M_AXIS TKEEP" *) output wire [3:0] m_axis_tkeep,
    (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 M_AXIS TVALID" *) output wire m_axis_tvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 M_AXIS TREADY" *) input wire m_axis_tready,
    (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 M_AXIS TLAST" *) output wire m_axis_tlast,
    input wire [3:0] mic_sd, output wire mic_bclk, output wire mic_ws
);
    reg [31:0] control, capture_frames;
    reg [5:0] awaddr;
    reg [31:0] wdata;
    reg [3:0] wstrb;
    reg aw_pending, w_pending;
    reg [31:0] accepted, dropped, warmup, empty_nonzero;
    wire [167:0] raw_data;
    wire [31:0] frame_seq;
    wire [23:0] empty_left;
    wire frame_valid, frame_ready;
    wire enabled=control[0];
    wire test_mode=control[1];
    wire capture_done=accepted>=capture_frames;
    wire warmed=test_mode || warmup>=WARMUP_FRAMES;
    wire take_frame=frame_valid && warmed && !capture_done;
    reg [167:0] chosen_data;
    integer i;
    function [23:0] test_value;
        input integer channel;
        input [31:0] seq;
        reg [23:0] base;
        begin
            case(channel)
                0: base=24'h123456; 1: base=24'hfedcba; 2: base=24'h800000;
                3: base=24'h7fffff; 4: base=24'haaaaaa; 5: base=24'h555555;
                default: base=24'h800001;
            endcase
            test_value=base+seq[23:0];
        end
    endfunction
    always @* begin
        chosen_data=raw_data;
        if (test_mode) for(i=0;i<7;i=i+1) chosen_data[24*i +: 24]=test_value(i,frame_seq);
    end
    assign s_axi_awready=!aw_pending && !s_axi_bvalid;
    assign s_axi_wready=!w_pending && !s_axi_bvalid;
    assign s_axi_bresp=2'b00;
    assign s_axi_arready=!s_axi_rvalid;
    assign s_axi_rresp=2'b00;
    i2s_mic_master #(.BCLK_DIV(BCLK_DIV)) rx (
        .clk(aclk),.resetn(aresetn && enabled),.mic_sd(mic_sd),.mic_bclk(mic_bclk),.mic_ws(mic_ws),
        .frame_valid(frame_valid),.frame_data(raw_data),.frame_seq(frame_seq),.empty_left(empty_left));
    mic_axis_packer #(.FRAMES_PER_PKT(FRAMES_PER_PKT)) packer (
        .clk(aclk),.resetn(aresetn && enabled),.frame_valid(take_frame),.frame_data(chosen_data),
        .frame_seq(frame_seq),.frame_last(accepted+1>=capture_frames),.frame_ready(frame_ready),
        .m_axis_tdata(m_axis_tdata),.m_axis_tkeep(m_axis_tkeep),.m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),.m_axis_tlast(m_axis_tlast));
    always @(posedge aclk) begin
        if (!aresetn || !enabled) begin
            accepted<=0; dropped<=0; warmup<=0; empty_nonzero<=0;
        end else if(frame_valid) begin
            if(!warmed) warmup<=warmup+1'b1;
            if(take_frame) begin
                if(frame_ready) accepted<=accepted+1'b1;
                else dropped<=dropped+1'b1;
                if(!test_mode && empty_left!=0) empty_nonzero<=empty_nonzero+1'b1;
            end
        end
    end
    always @(posedge aclk) begin
        if(!aresetn) begin
            control<=0; capture_frames<=16384; aw_pending<=0; w_pending<=0;
            s_axi_bvalid<=0; s_axi_rvalid<=0; s_axi_rdata<=0;
            awaddr<=0; wdata<=0; wstrb<=0;
        end else begin
            if(s_axi_awvalid && s_axi_awready) begin awaddr<=s_axi_awaddr; aw_pending<=1; end
            if(s_axi_wvalid && s_axi_wready) begin wdata<=s_axi_wdata; wstrb<=s_axi_wstrb; w_pending<=1; end
            if(s_axi_bvalid && s_axi_bready) s_axi_bvalid<=0;
            if(aw_pending && w_pending && !s_axi_bvalid) begin
                if(awaddr[5:2]==0 && wstrb[0]) begin
                    if(!enabled) control<={30'b0,wdata[1:0]};
                    else if(!wdata[0]) control<=0;
                end
                if(awaddr[5:2]==1 && !enabled && wstrb==4'hf && wdata!=0) capture_frames<=wdata;
                aw_pending<=0; w_pending<=0; s_axi_bvalid<=1;
            end
            if(s_axi_rvalid && s_axi_rready) s_axi_rvalid<=0;
            if(s_axi_arvalid && s_axi_arready) begin
                s_axi_rvalid<=1;
                case(s_axi_araddr[5:2])
                    0: s_axi_rdata<=control;
                    1: s_axi_rdata<=capture_frames;
                    2: s_axi_rdata<={28'b0,warmed,(dropped!=0),capture_done,enabled};
                    3: s_axi_rdata<=accepted;
                    4: s_axi_rdata<=dropped;
                    5: s_axi_rdata<=frame_seq;
                    6: s_axi_rdata<=empty_nonzero;
                    7: s_axi_rdata<=BCLK_DIV;
                    8: s_axi_rdata<=32'h4d494331;
                    9: s_axi_rdata<=FRAMES_PER_PKT;
                    default: s_axi_rdata<=0;
                endcase
            end
        end
    end
endmodule
