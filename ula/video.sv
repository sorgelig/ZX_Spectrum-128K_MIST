//
//
// Spectrum Video Controller implementation with ZX48, ZX128, Pentagon 128 timings
// 
// Copyright (c) 2016 Sorgelig
//
// 
// This source file is free software: you can redistribute it and/or modify 
// it under the terms of the GNU General Public License as published 
// by the Free Software Foundation, either version 3 of the License, or 
// (at your option) any later version. 
// 
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of 
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License 
// along with this program.  If not, see <http://www.gnu.org/licenses/>. 
//

`timescale 1ns / 1ps

module video
(
    input CLK,			        // 14MHz master clock
	 
	 // CPU interfacing
	 output        clk_cpu,	  // CLK to CPU
    input  [15:0] addr,
    input         nMREQ,
    input         nIORQ,
    input         nRFSH,
	 output        nINT,
	 
	 // VRAM interfacing
    output [12:0] vram_addr,
	 input   [7:0] vram_dout,
	 output  [7:0] port_ff,
	 
	 // Misc. signals
    input         mZX,
    input         m128,
	 input   [2:0] page_ram,
    input   [2:0] border,
	 input         scandoubler_disable,

    // OSD IO interface
    input         SPI_SCK,
    input         SPI_SS3,
    input         SPI_DI,

    // Video outputs
    output  [5:0] VGA_R,
    output  [5:0] VGA_G,
    output  [5:0] VGA_B,
    output        VGA_VS,
    output        VGA_HS
);

assign clk_cpu   = ~CPUClk;
assign vram_addr = vaddr;
assign nINT      = ~INT;
assign port_ff   = mZX ? ff_data : 8'hFF;

wire  [5:0] VGA_Rs, VGA_Rd;
wire  [5:0] VGA_Gs, VGA_Gd;
wire  [5:0] VGA_Bs, VGA_Bd;
wire        hsyncd, vsyncd;

osd osd 
(
	.*,
	.clk_pix(clk7),
	.VGA_Rx({R, R, I & R, I & R, I & R, I & R}),
	.VGA_Gx({G, G, I & G, I & G, I & G, I & G}),
	.VGA_Bx({B, B, I & B, I & B, I & B, I & B}),
	.VGA_R(VGA_Rs),
	.VGA_G(VGA_Gs),
	.VGA_B(VGA_Bs),
	.OSD_HS(HSync),
	.OSD_VS(VSync)
);

scandoubler scandoubler 
(
	.clk_x2(CLK),

	.scanlines(0),

	.hs_in(HSync),
	.vs_in(VSync),
	.r_in(VGA_Rs),
	.g_in(VGA_Gs),
	.b_in(VGA_Bs),

	.hs_out(hsyncd),
	.vs_out(vsyncd),
	.r_out(VGA_Rd),
	.g_out(VGA_Gd),
	.b_out(VGA_Bd)
);

assign {VGA_R,  VGA_G,  VGA_B,  VGA_VS,  VGA_HS          } = scandoubler_disable ?
       {VGA_Rs, VGA_Gs, VGA_Bs, 1'b1,    ~(HSync ^ VSync)} :
       {VGA_Rd, VGA_Gd, VGA_Bd, ~vsyncd, ~hsyncd         };

// Pixel clock
reg clk7 = 0;
always @(posedge CLK) clk7 <= !clk7;

reg [8:0] hc = 0;
reg [8:0] vc = 0;
always @(posedge clk7) begin
	if (hc==((mZX && m128) ? 455 : 447)) begin
		hc <= 0;
		if (vc == (!mZX ? 319 : m128 ? 310 : 311)) vc <= 0;
			else vc <= vc + 1'd1;
	end else begin
		hc <= hc + 1'd1;
	end
end

reg        INT    = 0;
reg  [5:0] INTCnt = 1;
reg  [7:0] ff_data;
reg        HBlank = 1;
reg        HSync;
reg        VSync;

reg  [7:0] SRegister;
reg [12:0] vaddr;

reg  [7:0] AttrOut;
reg  [4:0] FlashCnt;

wire       Border = ((vc[7] & vc[6]) | vc[8] | hc[8]);
reg        VidEN = 0;

reg  [7:0] bits;
reg  [7:0] attr;

always @(negedge clk7) begin

	if(!mZX) begin
		if (hc == 312) HBlank <= 1;
			else if (hc == 420) HBlank <= 0;
		if (hc == 340) HSync <= 1;
			else if (hc == 372) HSync <= 0;
	end else if(m128) begin
		if (hc == 312) HBlank <= 1;
			else if (hc == 424) HBlank <= 0;
		if (hc == 340) HSync <= 1;         //ULA 6C
			else if (hc == 372) HSync <= 0; //ULA 6C
	end else begin
		if (hc == 312) HBlank <= 1;
			else if (hc == 416) HBlank <= 0;
		if (hc == 336) HSync <= 1;         //ULA 5C
			else if (hc == 368) HSync <= 0; //ULA 5C
	end

	if(mZX) begin
		if(vc == 240) VSync <= 1;
			else if (vc == 244) VSync <= 0;
	end else begin
		if(vc == 248) VSync <= 1;
			else if (vc == 256) VSync <= 0;
	end

	if( mZX && (vc == 248) && (hc == (m128 ? 6 : 2))) INT <= 1;
	if(!mZX && (vc == 239) && (hc == 324)) INT <= 1;

	if(INT)  INTCnt <= INTCnt + 1'd1;
	if(!INTCnt) INT <= 0;

	if ((hc[3:0] == 4) || (hc[3:0] == 12)) begin
		SRegister <= bits;
		AttrOut <= VidEN ? attr : {2'b00,border,border};
	end else begin
		SRegister <= {SRegister[6:0],1'b0};
	end

	//1T update for border in Pentagon mode
	if(!mZX & ((hc<12) | (hc>267) | (vc>=192))) AttrOut <= {2'b00,border,border};

	if(hc[3]) VidEN <= ~Border;
	
	if(!Border) begin
		case(hc[3:0])
			  8,12: vaddr <= {vc[7:6],vc[2:0],vc[5:3],hc[7:4], hc[2]};
			  9,13: begin bits <= vram_dout; ff_data <= vram_dout; end
			 10,14: vaddr <= {3'b110,vc[7:3],hc[7:4],hc[2]};
			 11,15: begin attr <= vram_dout; ff_data <= vram_dout; end
		endcase
	end

	if (hc[3:0] == 1) ff_data <= 255;
end

always @(posedge VSync) FlashCnt <= FlashCnt + 1'd1;

wire I,G,R,B;
wire Pixel = SRegister[7] ^ (AttrOut[7] & FlashCnt[4]);
assign {I,G,R,B} = (HBlank || VSync) ? 4'b0000 : Pixel ? {AttrOut[6],AttrOut[2:0]} : {AttrOut[6],AttrOut[5:3]};

//T80 has incorrect nIORQ signal activated at T1 instead of T2.
reg nIORQ_T2;
always @(posedge CPUClk) nIORQ_T2 <= nIORQ;

reg  CPUClk;
reg  ioreqtw3;
reg  mreqt23;
wire ioreq_n  = addr[0] | nIORQ_T2 | nIORQ;

wire ulaContend = (hc[2] | hc[3]) & ~Border & CPUClk & ioreqtw3;
wire memContend = nRFSH & ioreq_n & mreqt23 & ((addr[15:14] == 2'b01) | (m128 & (addr[15:14] == 2'b11) & page_ram[0]));
wire ioContend  = ~ioreq_n;

always @(posedge clk7) CPUClk <= ~hc[0] | (mZX & ulaContend & (memContend | ioContend));

always @(posedge CPUClk) begin
	ioreqtw3 <= ioreq_n;
	mreqt23  <= nMREQ;
end

endmodule
