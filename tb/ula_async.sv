//
//
// ZX Spectrum 48K ULA - Simulation model
// Note: don't sythesize this code!
//
// Based on The ZX Spectrum ULA: How to Design a Microcomputer by Chris Smith
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

module ULA_ASYNC
(
	input         reset,

	input         clk_7,
	output        cpuclk,

	// CPU interfacing
	input  [15:0] addr,
	input   [7:0] din,
	input         nMREQ,
	input         nIORQ,
	input         nRD,
	input         nWR,
	output        nINT,

	// VRAM interfacing
	output        RAS_N,
	output        CAS_N,
	output [13:0] vram_addr,
	input   [7:0] vram_dout,
	output  [7:0] port_ff,
	
	// Misc. signals
	input         mZX,
	input         m128,
	input         page_scr,
	input   [2:0] page_ram,
	input   [2:0] border_color,

	// Video outputs
	output reg        HSync,
	output reg        VSync,
	output reg        HBlank,
	output reg  [2:0] Rx,
	output reg  [2:0] Gx,
	output reg  [2:0] Bx
);



////// HORIZONTAL AND VERTICAL COUNTERS ///////////////

/* verilator lint_off MULTIDRIVEN */
/* verilator lint_off UNOPTFLAT */
reg  [8:0] c;
always @(negedge clk_7) c[0] <= ~c[0];
wire c1_clk = clk_7&c[0]; always @(negedge c1_clk) c[1] <= ~c[1];
wire c2_clk = clk_7&c[0]&c[1]; always @(negedge c2_clk) c[2] <= ~c[2];
wire c3_clk = clk_7&c[0]&c[1]&c[2]; always @(negedge c3_clk) c[3] <= ~c[3];
always @(negedge c[3]) c[4] <= ~c[4];
wire c5_clk = c[4]&c[3]; always @(negedge c5_clk) c[5] <= ~c[5];
wire clkhc6 = c[5];

wire HCrst = c[7]&c[8];
always @(negedge clkhc6) begin
	if (HCrst)
		c[8:6] <= 0;
	else
		c[8:6] <= c[8:6] + 1'd1;
end

reg  [8:0] v;
wire       VRst = v[8]&v[5]&v[4]&v[2]&v[1]&v[0];
always @(negedge clkhc6) begin
	if (HCrst) begin
		if (VRst) v <= 0;
		else v <= v + 1'd1;
	end
end

/* verilator lint_on UNOPTFLAT */
/* verilator lint_on MULTIDRIVEN */

//////// SYNC AND BLANKING ///////

reg blank1;
reg blank2;
assign HBlank = blank1 | blank2;

reg hsyncpulses_n;
reg hsyncselect_n;

assign HSync = ~(hsyncselect_n | hsyncpulses_n);

always @(*) begin
	reg X;
	reg hsyncA_n;
	reg hsyncB_n;

	blank1 = ~(~c[8] |  c[7] | ~c[6]);
	blank2 = ~(~c[8] | ~c[7] |  c[5]);
	if (m128) begin
		// ULA 6C
		X = ~(c[4] | ~c[3]);
		hsyncA_n = ~ (c[5] |  X);
		hsyncB_n = ~(~c[5] | ~X);
	end else begin
		// ULA 5C
		hsyncA_n = ~( c[5] |  c[4]);
		hsyncB_n = ~(~c[5] | ~c[4]);
	end
	hsyncpulses_n = hsyncA_n | hsyncB_n;
	hsyncselect_n = ~c[8] | c[7] | ~c[6];
end

assign VSync = ~(~v[7] | ~v[6] | ~v[5] | ~v[4] | ~v[3] | v[2]);
assign nINT = ~VSync | v[2] | v[1] | v[0] | c[8] | c[7] | c[6];

////////// VIDEO CONTROL ///////////

wire Border = ((v[7] & v[6]) | v[8] | c[8]);
wire VidC3_n = Border | ~c[3];
/* verilator lint_off UNOPTFLAT */
wire VidEN = c[3] ? ~Border : VidEN;
/* verilator lint_on UNOPTFLAT */

wire DataLatch_n = (clk_7 & c[0]) | ~c[0] |  c[1] | VidC3_n;
wire AttrLatch_n = (clk_7 & c[0]) | ~c[0] | ~c[1] | VidC3_n;
wire SLoad_n = c[0] | c[1] | ~c[2] | ~VidEN;
wire AOLatch_n = ~c[0] | c[1] | ~c[2];
wire FlashClock = 1;

/////////// VIDEO RAS AND CAS GENERATION //////////

wire VidRASPulse = ~c[0] | ~c[1];
wire VidRAS_n = ~VidRASPulse | VidC3_n;
wire VidCASPulse = ~c[0] | ~clk_7;
wire VidCASac = ~(VidC3_n |  c[1] | ~VidCASPulse | VidRAS_n);
wire VidCASbd = ~(VidC3_n | ~c[1] | ~VidCASPulse);
wire VidCAS = VidCASac + VidCASbd; // Must delay by tRCD (20ns)

//////////// VIDEO ADDRESSING /////////////

wire AE_n = Border | ~(c[3] | ~(~c[0] | ~c[1] | ~c[2]));
wire RSel_n = ~VidRAS_n;
wire CDataSel_n = VidRAS_n | c[1];
wire CAttrSel_n = VidRAS_n | ~c[1];
wire [6:0] VidRasAddr = {v[4:3], c[7:4], c[2]};
wire [6:0] DataColAddr = {1'b0, v[7:6], v[2:0], v[5]};
wire [6:0] AttrColAddr = {4'b0110, v[7:5]};

assign vram_addr = {CDataSel_n ? AttrColAddr : DataColAddr, VidRasAddr};

/////////// CPU RAS AND CAS GENERATION /////////

wire ram16_n = nMREQ | ~addr[14] | addr[15];
wire cpucas_n = nRD | nWR | ram16_n;

assign RAS_N = ~(~ram16_n | ~VidRAS_n);
assign CAS_N = cpucas_n & ~VidCAS;

////////////// VIDEO DATA LATCH AND SHIFT REGISTER //////////////////

reg   [7:0] SRegister;
/* verilator lint_off UNOPTFLAT */
reg   [7:0] bits;
reg   [7:0] attr;
always @(negedge clk_7) begin
	// These should be transparent latches
	if (~DataLatch_n) bits = vram_dout;
	if (~AttrLatch_n) attr = vram_dout;
end
/* verilator lint_on UNOPTFLAT */
wire  [7:0] AttrOut = VidEN ? attr : {2'b00,border_color,border_color};

reg   [7:0] AttrLatch;
always @(*) if (~AOLatch_n) AttrLatch = AttrOut;

always @(negedge clk_7) begin
		if (~SLoad_n) begin
			SRegister <= bits;
		end else begin
			SRegister   <= {SRegister[6:0],   1'b0};
		end
end

wire       I,G,R,B;
wire       Pixel = SRegister[7] ^ (AttrLatch[7] & FlashClock);
assign     {I,G,R,B} = Pixel ? {AttrLatch[6],AttrLatch[2:0]} : {AttrLatch[6],AttrLatch[5:3]};

always_comb casez({HBlank | VSync})
	'b1: {Gx,Rx,Bx} = 0;
	'b0: {Gx,Rx,Bx} = {{G, I & G, I & G}, {R, I & R, I & R}, {B, I & B, I & B}};
endcase


/////////////// CPU CLOCK GENERATOR  ////////////////

wire ioreq_n    = addr[0] | nIORQ;

/* verilator lint_off UNOPTFLAT */
reg  mreqt23_a, ioreqtw3_a;
always @(*) if (~cpuclk) {mreqt23_a, ioreqtw3_a} = {~nMREQ, ~ioreq_n};

wire clkwait_n = ~(c[3] | c[2]);
wire contend_common_disable = Border | ioreqtw3_a | ~cpuclk;
wire contend_mem = ~(~(addr[14] | ~ioreq_n) | ~(~addr[15] | ~ioreq_n) | clkwait_n | mreqt23_a | contend_common_disable);
wire contend_io = ~(clkwait_n | ioreq_n | contend_common_disable);
assign cpuclk = c[0] | contend_mem | contend_io;
/* verilator lint_on UNOPTFLAT */

endmodule
