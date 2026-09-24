`timescale 1ns/1ps
// Synchronous AXI4-Stream FIFO (data + last), replacing axis_data_fifo with
// FIFO_DEPTH 4096. Block-RAM array with a registered first-word-fall-through
// output: one word per cycle in and out. TKEEP is all ones in this design and
// is not stored.
module axis_fifo #(parameter DEPTH=4096, parameter ABITS=12)(
    input wire aclk, input wire aresetn,
    input wire [31:0] s_tdata, input wire s_tlast, input wire s_tvalid, output wire s_tready,
    output reg [31:0] m_tdata, output reg m_tlast, output reg m_tvalid, input wire m_tready
);
    // One 8-bit array per byte lane plus one for TLAST: a single 33-bit array
    // is mapped as 4Kx9 RAMB36 slices whose ninth bit uses the parity pins
    // (DIP/DOP), which read back as 0 in the openXC7 flow (bits 8, 17 and 26
    // were stuck at 0 on the board). Byte-wide arrays use DI/DO only.
    (* ram_style="block" *) reg [7:0] lane0[0:DEPTH-1];
    (* ram_style="block" *) reg [7:0] lane1[0:DEPTH-1];
    (* ram_style="block" *) reg [7:0] lane2[0:DEPTH-1];
    (* ram_style="block" *) reg [7:0] lane3[0:DEPTH-1];
    (* ram_style="block" *) reg last_bits[0:DEPTH-1];
    reg [ABITS:0] wptr, rptr;              // rptr: next RAM word to fetch
    wire [ABITS:0] stored = wptr-rptr;     // words in RAM, excluding the output register
    assign s_tready = aresetn && stored < DEPTH;
    wire fetch = stored != 0 && (!m_tvalid || m_tready);
    always @(posedge aclk) begin
        if(s_tvalid && s_tready) begin
            lane0[wptr[ABITS-1:0]] <= s_tdata[7:0];   lane1[wptr[ABITS-1:0]] <= s_tdata[15:8];
            lane2[wptr[ABITS-1:0]] <= s_tdata[23:16]; lane3[wptr[ABITS-1:0]] <= s_tdata[31:24];
            last_bits[wptr[ABITS-1:0]] <= s_tlast;
        end
        if(fetch) begin
            m_tdata <= {lane3[rptr[ABITS-1:0]], lane2[rptr[ABITS-1:0]], lane1[rptr[ABITS-1:0]], lane0[rptr[ABITS-1:0]]};
            m_tlast <= last_bits[rptr[ABITS-1:0]];
        end
    end
    always @(posedge aclk) begin
        if(!aresetn) begin
            wptr<=0; rptr<=0; m_tvalid<=0;
        end else begin
            if(s_tvalid && s_tready) wptr<=wptr+1;
            if(fetch) begin rptr<=rptr+1; m_tvalid<=1; end
            else if(m_tready) m_tvalid<=0;
        end
    end
endmodule
