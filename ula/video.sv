`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:        Dept. Architecture and Computing Technology. University of Seville
// Engineer:       Miguel Angel Rodriguez Jodar. rodriguj@atc.us.es
// 
// Create Date:    19:13:39 4-Apr-2012 
// Design Name:    ZX Spectrum
// Module Name:    ula (video part)
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 1.00 - File Created
// Additional Comments: GPL License policies apply to the contents of this file.
//
//////////////////////////////////////////////////////////////////////////////////

`define cyclestart(a,b) ((a)==(b))
`define cycleend(a,b) ((a)==(b+1))

module video3(
    // Video clock (14 MHz)
    input         CLK,
    input         clk_cpu2x,
    input         nCONT,          
    
    // Memory interface
    output [12:0] vram_address,
    input   [7:0] vram_data,
    
    // IO interface
    input   [2:0] border,
    
    input         SPI_SCK,
    input         SPI_SS3,
    input         SPI_DI,

    // Video outputs
    output  [5:0] VGA_R,
    output  [5:0] VGA_G,
    output  [5:0] VGA_B,
    output        VGA_VS,
    output        VGA_HS,
    
    input  [15:0] A,     // Address bus from CPU (not all lines are used)
    input         nMREQ, // MREQ from CPU
    input         nIORQ, // IORQ from CPU
	 
	 output        clk_cpu,
    output        vs_nintr,
	 input         scandoubler_disable
);

assign VGA_HS     = scandoubler_disable ? ~(HSync ^ VSync) : ~sd_hs;
assign VGA_VS     = scandoubler_disable ? 1'b1 : ~sd_vs;
wire [5:0] VGA_Rx = scandoubler_disable ? {R, R, I & R, I & R, I & R, I & R} : {sd_r, sd_r[1:0]};
wire [5:0] VGA_Gx = scandoubler_disable ? {G, G, I & G, I & G, I & G, I & G} : {sd_g, sd_g[1:0]};
wire [5:0] VGA_Bx = scandoubler_disable ? {B, B, I & B, I & B, I & B, I & B} : {sd_b, sd_b[1:0]};
wire VGA_HS_OSD   = scandoubler_disable ? ~HSync : ~sd_hs;
wire VGA_VS_OSD   = scandoubler_disable ? ~VSync : ~sd_vs;

osd osd( .*, .clk_pix(CLK));

wire sd_hs, sd_vs;
wire [3:0] sd_r;
wire [3:0] sd_g;
wire [3:0] sd_b;

scandoubler scandoubler(
	.clk_x2(CLK),
	.clk(clk7),

	// scanlines (00-none 01-25% 10-50% 11-75%)
	.scanlines(2'b00),
		    
	.hs_in(HSync),
	.vs_in(VSync),
	.r_in({R,R,I&R,I&R}),
	.g_in({G,G,I&G,I&G}),
	.b_in({B,B,I&B,I&B}),

	.hs_out(sd_hs),
	.vs_out(sd_vs),
	.r_out(sd_r),
	.g_out(sd_g),
	.b_out(sd_b)
);

// Pixel clock
reg clk7 = 0;
always @(posedge CLK) clk7 <= !clk7;
		
// Horizontal counter
reg [8:0] hc = 0;
always @(posedge clk7) begin
	if (hc==447) hc <= 0;
		else hc <= hc + 9'd1;
end
	
// Vertical counter
reg [8:0] vc = 0;
always @(posedge clk7) begin
	if (hc==447) begin
		if (vc == 311) vc <= 0;
			else vc <= vc + 9'd1;
	end
end
	
// HBlank generation
reg HBlank = 0;
always @(negedge clk7) begin
	if (`cyclestart(hc,320)) HBlank <= 1;
		else if (`cycleend(hc,415)) HBlank <= 0;
end

// HSync generation (6C ULA version)
reg HSync = 0;
always @(negedge clk7) begin
	if (`cyclestart(hc,344)) HSync <= 1;
		else if (`cycleend(hc,375)) HSync <= 0;
end

// VBlank generation
reg VBlank = 0;
always @(negedge clk7) begin
	if (`cyclestart(vc,248)) VBlank <= 1;
		else if (`cycleend(vc,255)) VBlank <= 0;
end
	
// VSync generation (PAL)
reg VSync = 0;
always @(negedge clk7) begin
	if (`cyclestart(vc,248)) VSync <= 1;
		else if (`cycleend(vc,251)) VSync <= 0;
end
		
// INT generation
reg INT_n = 1;
assign vs_nintr = INT_n;
always @(negedge clk7) begin
	if (`cyclestart(vc,248) && `cyclestart(hc,0)) INT_n <= 0;
		else if (`cyclestart(vc,248) && `cycleend(hc,31)) INT_n <= 1;
end

// Border control signal (=0 when we're not displaying paper/ink pixels)
reg Border_n = 1;
always @(negedge clk7) begin
	if ( (vc[7] & vc[6]) | vc[8] | hc[8]) Border_n <= 0;
		else Border_n <= 1;
end
	
// VidEN generation (delaying Border 8 clocks)
reg VidEN_n = 1;
always @(negedge clk7) begin
	if (hc[3]) VidEN_n <= !Border_n;
end
	
// DataLatch generation (posedge to capture data from memory)
reg DataLatch_n = 1;
always @(negedge clk7) begin
	if (hc[0] & !hc[1] & Border_n & hc[3]) DataLatch_n <= 0;
		else DataLatch_n <= 1;
end
	
// AttrLatch generation (posedge to capture data from memory)
reg AttrLatch_n = 1;
always @(negedge clk7) begin
	if (hc[0] & hc[1] & Border_n & hc[3]) AttrLatch_n <= 0;
		else AttrLatch_n <= 1;
end

// SLoad generation (negedge to load shift register)
reg SLoad = 0;
always @(negedge clk7) begin
	if (!hc[0] & !hc[1] & hc[2] & !VidEN_n) SLoad <= 1;
		else SLoad <= 0;
end
	
// AOLatch generation (negedge to update attr output latch)
reg AOLatch_n = 1;
always @(negedge clk7) begin
	if (hc[0] & !hc[1] & hc[2]) AOLatch_n <= 0;
		else AOLatch_n <= 1;
end

// First buffer for bitmap
reg [7:0] BitmapReg = 0;
always @(negedge DataLatch_n) BitmapReg <= vram_data;
	
// Shift register (second bitmap register)
reg [7:0] SRegister = 0;
always @(negedge clk7) begin
	if (SLoad) SRegister <= BitmapReg;
		else SRegister <= {SRegister[6:0],1'b0};
end

// First buffer for attribute
reg [7:0] AttrReg = 0;
always @(negedge AttrLatch_n) AttrReg <= vram_data;
	
// Second buffer for attribute
reg [7:0] AttrOut = 0;
always @(negedge AOLatch_n) begin
	if (!VidEN_n) AttrOut <= AttrReg;
		else AttrOut <= {2'b00,border,border};
end

// Flash counter and pixel generation
reg [4:0] FlashCnt = 0;
always @(posedge VSync) FlashCnt <= FlashCnt + 5'd1;

wire Pixel = SRegister[7] ^ (AttrOut[7] & FlashCnt[4]);

// RGB generation
wire I = (HBlank || VBlank) ? 1'b0 : AttrOut[6];
wire G = (HBlank || VBlank) ? 1'b0 : Pixel ? AttrOut[2] : AttrOut[5];
wire R = (HBlank || VBlank) ? 1'b0 : Pixel ? AttrOut[1] : AttrOut[4];
wire B = (HBlank || VBlank) ? 1'b0 : Pixel ? AttrOut[0] : AttrOut[3];

// VRAM address and control line generation
reg [12:0] rvram_address = 13'd0;
assign vram_address = rvram_address;

// Latches to hold delayed versions of V and H counters
reg [8:0] v = 0;
reg [8:0] c = 0;
// Address and control line multiplexor ULA/CPU
always @(negedge clk7) begin
	if(Border_n) begin
		case(hc[3:0])
			4'd7: begin
					c <= hc;
					v <= vc;
				end

			4'd11: begin
					c <= hc;
					v <= vc;
					rvram_address <= {3'b110,vc[7:3],hc[7:3]};
				end

			4'd8, 4'd9, 4'd12, 4'd13: rvram_address <= {v[7:6],v[2:0],v[5:3],c[7:3]};
			4'd10, 4'd14, 4'd15:      rvram_address <= {3'b110,v[7:3],c[7:3]};

			default:
				;
		endcase
	end
end

// CPU contention
reg CPUClk = 0;
assign clk_cpu = !CPUClk;
reg ioreqtw3 = 0;
reg mreqt23 = 0;
wire ioreq_n = A[0] | nIORQ;
wire Nor1 = (~(A[14] | ~ioreq_n)) | 
            (~(~A[15] | ~ioreq_n)) | 
				(~(hc[2] | hc[3])) | 
				(~Border_n | ~ioreqtw3 | ~CPUClk | ~mreqt23);
wire Nor2 = (~(hc[2] | hc[3])) | 
            ~Border_n |
				~CPUClk |
				ioreq_n |
				~ioreqtw3;

wire CLKContention = ~Nor1 | ~Nor2;
always @(posedge clk_cpu2x) begin	
	if (CPUClk && (nCONT || !CLKContention))   // if there's no contention, the clock can go low
		CPUClk <= 0;
	else
		CPUClk <= 1;
end	

always @(posedge CPUClk) begin
	ioreqtw3 <= ioreq_n;
	mreqt23 <= nMREQ;
end

endmodule
