`timescale 1ns/1ps
// Register-compatible subset of AMD AXI DMA (simple mode, S2MM only, 64-bit
// memory side) as used by sw/mic_demo:
//   0x30 S2MM_DMACR  bit0 RS, bit2 Reset (self-clears when idle), others stored
//   0x34 S2MM_DMASR  bit0 Halted, bit1 Idle, bit4 DMAIntErr, bit5 DMASlvErr,
//                    bit6 DMADecErr, bit12 IOC_Irq (write 1 to clear)
//   0x48 S2MM_DA     destination byte address (8-byte aligned)
//   0x58 S2MM_LENGTH write starts a transfer; after completion reads the
//                    number of bytes received (up to and including TLAST)
// A transfer ends at TLAST or when LENGTH bytes arrived; the latter without
// TLAST sets DMAIntErr, as the IP does for a packet longer than the buffer.
// The stream is accepted only while a transfer is armed, so the upstream FIFO
// holds data between transfers. Writes are single 8-byte AXI3 beats, one
// outstanding: the 7-channel capture needs ~0.5 MB/s.
module s2mm_dma(
    input wire aclk, input wire aresetn,
    // AXI4-Lite register slave (16-bit offset)
    input wire [15:0] s_axi_awaddr, input wire s_axi_awvalid, output wire s_axi_awready,
    input wire [31:0] s_axi_wdata, input wire [3:0] s_axi_wstrb, input wire s_axi_wvalid, output wire s_axi_wready,
    output wire [1:0] s_axi_bresp, output reg s_axi_bvalid, input wire s_axi_bready,
    input wire [15:0] s_axi_araddr, input wire s_axi_arvalid, output wire s_axi_arready,
    output reg [31:0] s_axi_rdata, output wire [1:0] s_axi_rresp, output reg s_axi_rvalid, input wire s_axi_rready,
    // AXI4-Stream input
    input wire [31:0] s_axis_tdata, input wire s_axis_tlast, input wire s_axis_tvalid, output wire s_axis_tready,
    // AXI3 write master to PS7 S_AXI_HP0
    output reg [31:0] m_awaddr, output wire [3:0] m_awlen, output wire [1:0] m_awsize,
    output wire [1:0] m_awburst, output wire [3:0] m_awcache, output reg m_awvalid, input wire m_awready,
    output reg [63:0] m_wdata, output reg [7:0] m_wstrb, output wire m_wlast, output reg m_wvalid, input wire m_wready,
    input wire [1:0] m_bresp, input wire m_bvalid, output wire m_bready
);
    assign m_awlen=4'd0; assign m_awsize=2'd3; assign m_awburst=2'b01; assign m_awcache=4'b0011;
    assign m_wlast=1'b1; assign m_bready=1'b1;
    reg [31:0] dmacr, dest, length, received, addr;
    reg int_err, slv_err, dec_err, ioc, busy, write_pending, reset_pending;
    reg [31:0] low_word; reg have_low, ending;
    wire running = dmacr[0];
    // A beat is formed from two words, or from one word when TLAST ends it.
    wire room = busy && !write_pending && !ending && !reset_pending;
    assign s_axis_tready = room;
    wire take = s_axis_tvalid && room;
    // at_last: the next stream word reaches LENGTH. Registered whenever
    // received changes, so no adder/comparator sits on the stream path.
    reg at_last;
    wire done_by_length = at_last;
    // Register interface: address/data captured independently, one response.
    reg [15:0] wa; reg [31:0] wd; reg [3:0] ws; reg have_aw, have_w;
    assign s_axi_awready = !have_aw && !s_axi_bvalid;
    assign s_axi_wready = !have_w && !s_axi_bvalid;
    assign s_axi_bresp = 2'b00; assign s_axi_rresp = 2'b00;
    assign s_axi_arready = !s_axi_rvalid;
    wire reg_write = have_aw && have_w && !s_axi_bvalid;
    always @(posedge aclk) begin
        if(!aresetn) begin
            dmacr<=0; dest<=0; length<=0; received<=0; addr<=0; int_err<=0; slv_err<=0; dec_err<=0; ioc<=0;
            busy<=0; write_pending<=0; reset_pending<=0; low_word<=0; have_low<=0; ending<=0; at_last<=0;
            m_awvalid<=0; m_wvalid<=0; m_awaddr<=0; m_wdata<=0; m_wstrb<=0;
            wa<=0; wd<=0; ws<=0; have_aw<=0; have_w<=0; s_axi_bvalid<=0; s_axi_rvalid<=0; s_axi_rdata<=0;
        end else begin
            if(s_axi_awvalid && s_axi_awready) begin wa<=s_axi_awaddr; have_aw<=1; end
            if(s_axi_wvalid && s_axi_wready) begin wd<=s_axi_wdata; ws<=s_axi_wstrb; have_w<=1; end
            if(s_axi_bvalid && s_axi_bready) s_axi_bvalid<=0;
            if(reg_write) begin
                have_aw<=0; have_w<=0; s_axi_bvalid<=1;
                case(wa[7:0])
                    8'h30: begin
                        if(wd[2]) reset_pending<=1;
                        else dmacr<={wd[31:3],1'b0,wd[1:0]};
                    end
                    8'h34: if(wd[12]) ioc<=0;
                    8'h48: dest<=wd;
                    8'h58: if(running && !busy && !reset_pending && wd[25:0]!=0) begin
                        length<=wd[25:0]; received<=0; addr<=dest; busy<=1; have_low<=0; ending<=0;
                        at_last<=wd[25:0]<=26'd4;
                    end
                    default: ;
                endcase
            end
            if(s_axi_arvalid && s_axi_arready) begin
                s_axi_rvalid<=1;
                case(s_axi_araddr[7:0])
                    8'h30: s_axi_rdata<={dmacr[31:3],reset_pending,dmacr[1:0]};
                    8'h34: s_axi_rdata<={19'd0,ioc,5'd0,dec_err,slv_err,int_err,2'd0,running&&!busy,!running};
                    8'h48: s_axi_rdata<=dest;
                    8'h58: s_axi_rdata<=busy ? length : received;
                    default: s_axi_rdata<=0;
                endcase
            end else if(s_axi_rvalid && s_axi_rready) s_axi_rvalid<=0;
            // Stream words -> 64-bit beats.
            if(take) begin
                received<=received+4;
                at_last<=received+8>=length;
                if(!have_low && !s_axis_tlast && !done_by_length) begin
                    low_word<=s_axis_tdata; have_low<=1;
                end else begin
                    m_awaddr<=addr; m_awvalid<=1; m_wvalid<=1; write_pending<=1; have_low<=0;
                    m_wdata<=have_low ? {s_axis_tdata,low_word} : {32'd0,s_axis_tdata};
                    m_wstrb<=have_low ? 8'hff : 8'h0f;
                    addr<=addr+8;
                    if(s_axis_tlast || done_by_length) begin
                        ending<=1;
                        if(!s_axis_tlast) int_err<=1;
                    end
                end
            end
            if(m_awvalid && m_awready) m_awvalid<=0;
            if(m_wvalid && m_wready) m_wvalid<=0;
            if(m_bvalid && write_pending) begin
                write_pending<=0;
                if(m_bresp==2'b10) slv_err<=1;
                if(m_bresp==2'b11) dec_err<=1;
                if(ending) begin ending<=0; busy<=0; ioc<=1; end
            end
            // Soft reset once no AXI write is outstanding.
            if(reset_pending && !write_pending && !m_awvalid && !m_wvalid) begin
                reset_pending<=0; dmacr<=0; busy<=0; ending<=0; have_low<=0; received<=0; length<=0;
                int_err<=0; slv_err<=0; dec_err<=0; ioc<=0;
            end
        end
    end
endmodule
