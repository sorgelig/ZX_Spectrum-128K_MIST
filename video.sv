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
	input         reset,

	input         clk_sys,	// master clock
	input         ce_7mp,
	input         ce_7mn,
	output reg    ce_cpu_sp,
	output reg    ce_cpu_sn,

	// CPU interfacing
	input  [15:0] addr,
	input   [7:0] din,
	input         nMREQ,
	input         nIORQ,
	input         nRFSH,
	input         nWR,
	output        nINT,

	// VRAM interfacing
	output [12:0] vram_addr,
	input   [7:0] vram_dout,
	output  [7:0] port_ff,
	
	// ULA+
	output        ulap_sel,
	output  [7:0] ulap_dout,

	// Misc. signals
	input         mZX,
	input         m128,
	input   [2:0] page_ram,
	input   [2:0] border_color,
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

assign vram_addr = vaddr;
assign nINT      = ~INT;
assign port_ff   = mZX ? ff_data : 8'hFF;

wire  [5:0] VGA_Rs, VGA_Rd;
wire  [5:0] VGA_Gs, VGA_Gd;
wire  [5:0] VGA_Bs, VGA_Bd;
wire        hsyncd, vsyncd;

osd #(10'd10, 10'd0, 3'd4) osd
(
	.*,
	.ce_pix(ce_7mp),
	.VGA_Rx(Rx),
	.VGA_Gx(Gx),
	.VGA_Bx(Bx),
	.VGA_R(VGA_Rs),
	.VGA_G(VGA_Gs),
	.VGA_B(VGA_Bs),
	.OSD_HS(HSync),
	.OSD_VS(VSync)
);

scandoubler scandoubler 
(
	.clk_sys(clk_sys),
	.ce_x2(ce_7mp | ce_7mn),
	.ce_x1(ce_7mp),

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
reg [8:0] hc = 0;
reg [8:0] vc = 0;
always @(posedge clk_sys) begin
	if(ce_7mp) begin
		if (hc==((mZX && m128) ? 455 : 447)) begin
			hc <= 0;
			if (vc == (!mZX ? 319 : m128 ? 310 : 311)) begin 
				vc <= 0;
				FlashCnt <= FlashCnt + 1'd1;
			end else begin
				vc <= vc + 1'd1;
			end
		end else begin
			hc <= hc + 1'd1;
		end
	end
	if(ce_7mn) begin
		if(!mZX) begin
			if (hc == 312) HBlank <= 1;
				else if (hc == 420) HBlank <= 0;
			if (hc == 338) HSync <= 1;
				else if (hc == 370) HSync <= 0;
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
			AttrOut <= VidEN ? attr : {2'b00,border_color,border_color};
			ulap_brd <= ~VidEN;
		end else begin
			SRegister <= {SRegister[6:0],1'b0};
		end

		//1T update for border in Pentagon mode
		if(!mZX & ((hc<12) | (hc>267) | (vc>=192))) AttrOut <= {2'b00,border_color,border_color};

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
end

reg        INT    = 0;
reg  [5:0] INTCnt = 1;
reg  [7:0] ff_data;
reg        HBlank = 1;
reg        HSync;
reg        VSync;

reg  [7:0] SRegister;
reg [12:0] vaddr;

reg        ulap_brd;
reg  [7:0] AttrOut;
reg  [4:0] FlashCnt;

wire       Border = ((vc[7] & vc[6]) | vc[8] | hc[8]);
reg        VidEN = 0;

reg  [7:0] bits;
reg  [7:0] attr;

wire I,G,R,B;
wire Pixel = SRegister[7] ^ (AttrOut[7] & FlashCnt[4]);
assign {I,G,R,B} = Pixel ? {AttrOut[6],AttrOut[2:0]} : {AttrOut[6],AttrOut[5:3]};

wire [7:0] color = palette[(ulap_brd | ~SRegister[7]) ? {AttrOut[7:6],1'b1,AttrOut[5:3]} : {AttrOut[7:6],1'b0,AttrOut[2:0]}];
reg  [5:0] Rx, Gx, Bx;

always_comb casex({HBlank | VSync, ulap_ena, ulap_mono})
	'b1XX: {Rx,Gx,Bx} <= 0;
	'b00X: {Rx,Gx,Bx} <= {{R, R, I & R, I & R, I & R, I & R}, {G, G, I & G, I & G, I & G, I & G}, {B, B, I & B, I & B, I & B, I & B}};
	'b010: {Rx,Gx,Bx} <= {{color[4:2],color[4:2]}, {color[7:5],color[7:5]}, {color[1:0],|color[1:0],color[1:0],|color[1:0]}};
	'b011: {Rx,Gx,Bx} <= {color[7:2], color[7:2], color[7:2]};
endcase

///////////////////////////////////////////////////////////////////////////////

reg  nIORQ_T2; //T80 has incorrect nIORQ signal activated at T1 instead of T2.
reg  CPUClk;
reg  ioreqtw3;
reg  mreqt23;

wire ioreq_n    = addr[0] | nIORQ_T2 | nIORQ;
wire ulaContend = (hc[2] | hc[3]) & ~Border & CPUClk & ioreqtw3;
wire memContend = nRFSH & ioreq_n & mreqt23 & ((addr[15:14] == 2'b01) | (m128 & (addr[15:14] == 2'b11) & page_ram[0]));
wire ioContend  = ~ioreq_n;
wire next_clk   = ~hc[0] | (mZX & ulaContend & (memContend | ioContend));

always @(negedge clk_sys) begin
	ce_cpu_sp <= 0;
	ce_cpu_sn <= 0;
	if(ce_7mp) begin
		CPUClk <= next_clk;

		if(~CPUClk &  next_clk) ce_cpu_sp <= 1;
		if( CPUClk & ~next_clk) ce_cpu_sn <= 1;

		if(~CPUClk &  next_clk) begin
			ioreqtw3 <= ioreq_n;
			mreqt23  <= nMREQ;
			nIORQ_T2 <= nIORQ;
		end
	end
end

/////////////////  ULA+  ///////////////////

assign     ulap_dout = ulap_group ? {ulap_mono, ulap_ena} : palette[pal_addr];
assign     ulap_sel  = ulap_acc & addr[14];

wire       ulap_acc = ({addr[15], 1'b0, addr[13:0]} == 'hBF3B);
wire       io_wr = ~nIORQ & ~nWR;
reg  [5:0] pal_addr;
reg        ulap_group;
reg        ulap_ena;
reg        ulap_mono;
reg  [7:0] palette[64];

always @(posedge clk_sys) begin
	reg old_wr;
	old_wr <= io_wr;

	if(reset) ulap_ena <= 0;
	else if(~old_wr & io_wr & ulap_acc) begin
		if(addr[14]) begin
			if(ulap_group) {ulap_mono,ulap_ena} <= din[1:0];
				else palette[pal_addr] <= din;
		end else begin
			case(din[7:6])
				0: {ulap_group, pal_addr} <= {1'b0, din[5:0]};
				1: ulap_group <= 1;
				default: ;
			endcase
		end
	end
end

endmodule
