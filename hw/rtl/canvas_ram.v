`timescale 1ns/1ps
// Video canvas storage: true dual-port RAM in the standard template that both
// Vivado and yosys map to block RAM. Port A (aclk) writes bytes or reads;
// port B (pclk) reads for scanout. Port A output holds during a write
// (no-change), which the AXI logic never observes: it cannot accept a read in
// a write cycle. No reset of the array.
module canvas_ram #(parameter DEPTH=57600, parameter ABITS=16)(
    input wire clka, input wire wea, input wire [3:0] bea, input wire [ABITS-1:0] addra,
    input wire [31:0] dina, output reg [31:0] douta,
    input wire clkb, input wire [ABITS-1:0] addrb, output reg [31:0] doutb
);
    (* ram_style="block" *) reg [31:0] memory[0:DEPTH-1];
    integer b;
    always @(posedge clka) begin
        if(wea) begin
            for(b=0;b<4;b=b+1) if(bea[b]) memory[addra][b*8 +: 8]<=dina[b*8 +: 8];
        end else douta<=memory[addra];
    end
    always @(posedge clkb) doutb<=memory[addrb];
endmodule
