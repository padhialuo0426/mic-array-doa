`timescale 1ns/1ps
// All logic stays in the 100 MHz domain. WS changes on BCLK falling edges.
// Slot bit 0 is the I2S delay bit; bits 1..24 contain signed, MSB-first data.
module i2s_mic_master #(
    parameter integer BCLK_DIV = 96
)(
    input wire clk, input wire resetn, input wire [3:0] mic_sd,
    output reg mic_bclk, output reg mic_ws,
    output reg frame_valid, output reg [167:0] frame_data,
    output reg [31:0] frame_seq, output reg [23:0] empty_left
);
    reg [15:0] divider;
    reg [5:0] bit_index;
    (* IOB = "TRUE" *) reg [3:0] sd_meta;
    (* ASYNC_REG = "TRUE" *) reg [3:0] sd_sync;
    reg [23:0] shift [0:3];
    reg [23:0] channels [0:6];
    reg [31:0] sequence_count;
    integer i;
    always @(posedge clk) begin
        sd_meta <= mic_sd;
        sd_sync <= sd_meta;
        if (!resetn) begin
            divider <= 0; bit_index <= 0; mic_bclk <= 0; mic_ws <= 0;
            frame_valid <= 0; frame_data <= 0; frame_seq <= 0;
            sequence_count <= 0; empty_left <= 0;
            for (i=0;i<4;i=i+1) shift[i] <= 0;
            for (i=0;i<7;i=i+1) channels[i] <= 0;
        end else begin
            frame_valid <= 0;
            if (divider == BCLK_DIV-1) begin
                divider <= 0;
                mic_bclk <= 0;
                if (bit_index == 31) begin
                    bit_index <= 0;
                    mic_ws <= ~mic_ws;
                end else bit_index <= bit_index + 1'b1;
            end else divider <= divider + 1'b1;
            if (divider == BCLK_DIV/2-1) mic_bclk <= 1;
            if (divider == (3*BCLK_DIV)/4-1) begin
                if (bit_index >= 1 && bit_index <= 24) begin
                    for (i=0;i<4;i=i+1) shift[i] <= {shift[i][22:0],sd_sync[i]};
                    if (bit_index == 24) begin
                        if (!mic_ws) begin
                            channels[0] <= {shift[0][22:0],sd_sync[0]};
                            channels[2] <= {shift[1][22:0],sd_sync[1]};
                            channels[4] <= {shift[2][22:0],sd_sync[2]};
                            empty_left <= {shift[3][22:0],sd_sync[3]};
                        end else begin
                            channels[1] <= {shift[0][22:0],sd_sync[0]};
                            channels[3] <= {shift[1][22:0],sd_sync[1]};
                            channels[5] <= {shift[2][22:0],sd_sync[2]};
                            channels[6] <= {shift[3][22:0],sd_sync[3]};
                        end
                    end
                end
                if (mic_ws && bit_index == 31) begin
                    frame_valid <= 1;
                    frame_seq <= sequence_count;
                    sequence_count <= sequence_count + 1'b1;
                    for (i=0;i<7;i=i+1) frame_data[24*i +: 24] <= channels[i];
                end
            end
        end
    end
endmodule
