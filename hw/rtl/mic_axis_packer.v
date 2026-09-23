`timescale 1ns/1ps
// Whole-frame queue: a stalled stream never mixes samples from two frames.
module mic_axis_packer #(
    parameter integer FRAMES_PER_PKT = 256,
    parameter integer FIFO_BITS = 4
)(
    input wire clk, input wire resetn,
    input wire frame_valid, input wire [167:0] frame_data,
    input wire [31:0] frame_seq, input wire frame_last,
    output wire frame_ready,
    output wire [31:0] m_axis_tdata, output wire [3:0] m_axis_tkeep,
    output wire m_axis_tvalid, input wire m_axis_tready, output wire m_axis_tlast
);
    localparam integer DEPTH = 1 << FIFO_BITS;
    reg [256:0] memory [0:DEPTH-1];
    reg [FIFO_BITS-1:0] write_ptr, read_ptr;
    reg [FIFO_BITS:0] count;
    reg [2:0] beat;
    reg [15:0] packet_frames;
    reg [255:0] packed_frame;
    integer i;
    wire pop = m_axis_tvalid && m_axis_tready && beat == 7;
    wire push = frame_valid && frame_ready;
    assign frame_ready = count < DEPTH || pop;
    assign m_axis_tvalid = count != 0;
    assign m_axis_tkeep = 4'hf;
    assign m_axis_tdata = memory[read_ptr][32*beat +: 32];
    assign m_axis_tlast = memory[read_ptr][256] && beat == 7 && m_axis_tvalid;
    always @* begin
        packed_frame = 0;
        for (i=0;i<7;i=i+1) packed_frame[32*i +: 32] = {frame_data[24*i +: 24],8'h00};
        packed_frame[255:224] = frame_seq;
    end
    always @(posedge clk) begin
        if (!resetn) begin
            write_ptr<=0; read_ptr<=0; count<=0; beat<=0; packet_frames<=0;
        end else begin
            if (push) begin
                memory[write_ptr] <= {frame_last || packet_frames == FRAMES_PER_PKT-1,packed_frame};
                write_ptr <= write_ptr+1'b1;
                if (frame_last || packet_frames == FRAMES_PER_PKT-1) packet_frames<=0;
                else packet_frames<=packet_frames+1'b1;
            end
            if (m_axis_tvalid && m_axis_tready) begin
                beat <= beat+1'b1;
                if (pop) read_ptr <= read_ptr+1'b1;
            end
            case ({push,pop})
                2'b10: count<=count+1'b1;
                2'b01: count<=count-1'b1;
                default: count<=count;
            endcase
        end
    end
endmodule
