`timescale 1ns/1ps
// PS7 M_AXI_GP0 (AXI3 master) -> one AXI4-Lite master, replacing Vivado's
// axi_interconnect protocol conversion. One transaction at a time; INCR and
// FIXED bursts are split into single beats (the CPU's LDM/STM to device memory
// may burst). Write responses and read responses carry the worst beat status.
// Address decoding is left to the caller: m_awaddr/m_araddr are stable for one
// cycle before the matching valid rises, so the caller may register its decode.
module axi3_lite_bridge #(parameter ID_W=12)(
    input wire aclk, input wire aresetn,
    // AXI3 slave
    input wire [ID_W-1:0] s_awid, input wire [31:0] s_awaddr, input wire [3:0] s_awlen,
    input wire [1:0] s_awsize, input wire [1:0] s_awburst, input wire s_awvalid, output wire s_awready,
    input wire [ID_W-1:0] s_wid, input wire [31:0] s_wdata, input wire [3:0] s_wstrb, input wire s_wlast,
    input wire s_wvalid, output wire s_wready,
    output reg [ID_W-1:0] s_bid, output reg [1:0] s_bresp, output reg s_bvalid, input wire s_bready,
    input wire [ID_W-1:0] s_arid, input wire [31:0] s_araddr, input wire [3:0] s_arlen,
    input wire [1:0] s_arsize, input wire [1:0] s_arburst, input wire s_arvalid, output wire s_arready,
    output reg [ID_W-1:0] s_rid, output reg [31:0] s_rdata, output reg [1:0] s_rresp, output reg s_rlast,
    output reg s_rvalid, input wire s_rready,
    // AXI4-Lite master
    output reg [31:0] m_awaddr, output reg m_awvalid, input wire m_awready,
    output reg [31:0] m_wdata, output reg [3:0] m_wstrb, output reg m_wvalid, input wire m_wready,
    input wire [1:0] m_bresp, input wire m_bvalid, output wire m_bready,
    output reg [31:0] m_araddr, output reg m_arvalid, input wire m_arready,
    input wire [31:0] m_rdata, input wire [1:0] m_rresp, input wire m_rvalid, output wire m_rready
);
    localparam IDLE=0, W_DATA=1, W_LITE=2, W_RESP=3, B_SEND=4, R_LITE=5, R_RESP=6, R_SEND=7, W_ADDR=8, R_ADDR=9;
    reg [3:0] state;
    reg [ID_W-1:0] id;
    reg [31:0] addr;
    reg [3:0] left;
    reg [1:0] size, burst, worst;
    wire [31:0] next_addr = (burst==2'b00) ? addr : addr+(32'd1<<size);
    function [1:0] max_resp;
        input [1:0] a,b;
        max_resp=(a>b)?a:b;
    endfunction
    // Writes win ties so a CPU store stream cannot be starved by polling reads.
    // B_SEND/R_SEND drop s_bvalid/s_rvalid before IDLE, so IDLE alone is ready.
    assign s_awready = state==IDLE;
    assign s_arready = state==IDLE && !s_awvalid;
    assign s_wready = state==W_DATA;
    assign m_bready = state==W_RESP;
    assign m_rready = state==R_RESP;
    always @(posedge aclk) begin
        if(!aresetn) begin
            state<=IDLE; s_bvalid<=0; s_rvalid<=0; m_awvalid<=0; m_wvalid<=0; m_arvalid<=0;
            s_bid<=0; s_bresp<=0; s_rid<=0; s_rdata<=0; s_rresp<=0; s_rlast<=0; worst<=0;
            id<=0; addr<=0; left<=0; size<=0; burst<=0; m_awaddr<=0; m_wdata<=0; m_wstrb<=0; m_araddr<=0;
        end else case(state)
            default: state<=IDLE;
            IDLE: begin
                if(s_awvalid) begin
                    id<=s_awid; addr<=s_awaddr; left<=s_awlen; size<=s_awsize; burst<=s_awburst; worst<=0; state<=W_DATA;
                end else if(s_arvalid) begin
                    id<=s_arid; addr<=s_araddr; left<=s_arlen; size<=s_arsize; burst<=s_arburst; worst<=0;
                    m_araddr<=s_araddr; state<=R_ADDR;
                end
            end
            W_DATA: if(s_wvalid) begin
                m_awaddr<=addr; m_wdata<=s_wdata; m_wstrb<=s_wstrb; state<=W_ADDR;
            end
            W_ADDR: begin m_awvalid<=1; m_wvalid<=1; state<=W_LITE; end
            R_ADDR: begin m_arvalid<=1; state<=R_LITE; end
            W_LITE: begin
                if(m_awready) m_awvalid<=0;
                if(m_wready) m_wvalid<=0;
                if((!m_awvalid || m_awready) && (!m_wvalid || m_wready)) state<=W_RESP;
            end
            W_RESP: if(m_bvalid) begin
                worst<=max_resp(worst,m_bresp);
                if(left==0) begin
                    s_bid<=id; s_bresp<=max_resp(worst,m_bresp); s_bvalid<=1; state<=B_SEND;
                end else begin
                    left<=left-1; addr<=next_addr; state<=W_DATA;
                end
            end
            B_SEND: if(s_bready) begin s_bvalid<=0; state<=IDLE; end
            R_LITE: if(m_arready) begin m_arvalid<=0; state<=R_RESP; end
            R_RESP: if(m_rvalid) begin
                s_rid<=id; s_rdata<=m_rdata; s_rresp<=m_rresp; s_rlast<=(left==0); s_rvalid<=1; state<=R_SEND;
            end
            R_SEND: if(s_rready) begin
                s_rvalid<=0;
                if(s_rlast) state<=IDLE;
                else begin left<=left-1; addr<=next_addr; m_araddr<=next_addr; state<=R_ADDR; end
            end
        endcase
    end
endmodule
