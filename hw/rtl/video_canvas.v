`timescale 1ns/1ps
// AXI-Lite back buffer + bundled toggle handshake. No DDR/display DMA traffic.
// A commit holds mode/data stable until the pixel-domain vertical blank ACK.
module video_canvas #(
    parameter WATCHDOG_FRAMES=120
)(
    input wire aclk,aresetn,pclk,presetn,locked,hpd,
    input wire [17:0] awaddr,input wire awvalid,output wire awready,
    input wire [31:0] wdata,input wire [3:0] wstrb,input wire wvalid,output wire wready,
    output reg [1:0] bresp,output reg bvalid,input wire bready,
    input wire [17:0] araddr,input wire arvalid,output wire arready,
    output reg [31:0] rdata,output reg [1:0] rresp,output reg rvalid,input wire rready,
    input wire [14:0] pixel_addr,output reg [31:0] pixel_data,
    input wire frame_boundary,output reg bars,output wire visible
);
    localparam WORDS=28800;
    (* ram_style="block" *) reg [31:0] memory[0:57599];
    reg [17:0] wa;reg [31:0] wd;reg [3:0] ws;reg have_aw,have_w;
    reg request,mode_hold;
    (* ASYNC_REG="TRUE" *) reg ack_meta,ack_sync;
    (* ASYNC_REG="TRUE" *) reg req_meta,req_sync;
    (* ASYNC_REG="TRUE" *) reg [2:0] health_meta,health_sync;
    reg ack,front,frame_valid,expired_status;
    reg [7:0] age;
    reg [31:0] frames,frames_gray;
    (* ASYNC_REG="TRUE" *) reg [31:0] gray_meta,gray_sync;
    reg [31:0] commits;
    wire busy=(request!=ack_sync);
    wire pixel_expired=!frame_valid || age>=WATCHDOG_FRAMES;
    assign visible=frame_valid&&!pixel_expired;
    wire [14:0] write_offset=wa[16:2];
    wire [15:0] write_index=(request?16'd0:16'd28800)+write_offset;
    wire [15:0] read_index=(request?16'd0:16'd28800)+araddr[16:2];
    wire write_memory=have_aw&&have_w&&!bvalid&&wa>=18'h20000&&wa<18'h3c200&&wa[1:0]==0&&!busy;
    wire [15:0] bus_index=write_memory?write_index:read_index;
    reg [31:0] bus_mem_q;reg read_pending,read_is_mem;
    reg [31:0] read_control;reg [1:0] read_error;
    assign awready=!have_aw&&!bvalid;
    assign wready=!have_w&&!bvalid;
    // Port A is shared by AXI reads and writes; port B is scanout. Independent
    // simultaneous bus-read and bus-write addresses would infer a THIRD port
    // and duplicate the entire video RAM in Vivado.
    assign arready=!rvalid&&!read_pending&&!write_memory;
    integer b,j;
    function [31:0] from_gray;
        input [31:0] g;integer k;
        begin from_gray[31]=g[31];for(k=30;k>=0;k=k-1)from_gray[k]=from_gray[k+1]^g[k];end
    endfunction
    // Byte-enabled true dual-port RAM: do not reset the RAM array.
    always @(posedge aclk) begin
        if(write_memory) for(b=0;b<4;b=b+1)if(ws[b])memory[bus_index][b*8 +: 8]<=wd[b*8 +: 8];
        bus_mem_q<=memory[bus_index];
    end
    always @(posedge pclk)pixel_data<=memory[(front?16'd28800:16'd0)+(pixel_addr<WORDS?pixel_addr:15'd0)];
    always @(posedge aclk)begin
        if(!aresetn)begin
            have_aw<=0;have_w<=0;wa<=0;wd<=0;ws<=0;bvalid<=0;bresp<=0;
            rvalid<=0;rdata<=0;rresp<=0;read_pending<=0;read_is_mem<=0;read_control<=0;read_error<=0;
            request<=0;mode_hold<=1;ack_meta<=0;ack_sync<=0;health_meta<=0;health_sync<=0;
            gray_meta<=0;gray_sync<=0;commits<=0;
        end else begin
            ack_meta<=ack;ack_sync<=ack_meta;health_meta<={expired_status,locked,hpd};health_sync<=health_meta;
            gray_meta<=frames_gray;gray_sync<=gray_meta;
            if(awvalid&&awready)begin wa<=awaddr;have_aw<=1;end
            if(wvalid&&wready)begin wd<=wdata;ws<=wstrb;have_w<=1;end
            if(bvalid&&bready)bvalid<=0;
            if(have_aw&&have_w&&!bvalid)begin
                have_aw<=0;have_w<=0;bvalid<=1;bresp<=0;
                if(wa==0)begin
                    if(ws[0]&&wd[0])begin
                        if(busy)bresp<=2;
                        else begin mode_hold<=wd[1];request<=~request;commits<=commits+1;end
                    end
                end else if(wa>=18'h20000&&wa<18'h3c200&&wa[1:0]==0)begin
                    if(busy)bresp<=2;
                end else bresp<=2;
            end
            if(rvalid&&rready)rvalid<=0;
            if(arvalid&&arready)begin
                read_pending<=1;read_is_mem<=0;read_error<=0;read_control<=0;
                if(araddr>=18'h20000&&araddr<18'h3c200&&araddr[1:0]==0)begin
                    read_is_mem<=1;if(busy)read_error<=2;
                end else case(araddr)
                    0:read_control<=0;
                    4:read_control<={27'b0,ack_sync,health_sync,busy};
                    8:read_control<=32'h48444d31;
                    12:read_control<=from_gray(gray_sync);
                    16:read_control<=32'h02800168;
                    20:read_control<=commits;
                    default:read_error<=2;
                endcase
            end
            if(read_pending)begin rvalid<=1;rdata<=read_is_mem?bus_mem_q:read_control;rresp<=read_error;read_pending<=0;end
        end
    end
    always @(posedge pclk)begin
        if(!presetn)begin
            req_meta<=0;req_sync<=0;ack<=0;front<=0;bars<=1;frame_valid<=0;age<=0;frames<=0;frames_gray<=0;expired_status<=1;
        end else begin
            req_meta<=request;req_sync<=req_meta;
            expired_status<=pixel_expired;
            if(frame_boundary)begin
                frames<=frames+1;frames_gray<=((frames+1)>>1)^(frames+1);
                if(req_sync!=ack)begin
                    front<=req_sync;bars<=mode_hold;ack<=req_sync;frame_valid<=1;age<=0;
                end else if(age<WATCHDOG_FRAMES)age<=age+1'b1;
            end
        end
    end
endmodule
