//============================================================================
// The implementation of the Sinclair ZX Spectrum ULA
//
//  Copyright (C) 2014  Goran Devic
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================
module ula
(
    //-------- Clocks and reset -----------------
    input  wire [1:0] CLOCK_27,     // Input clock 27 MHz
    input  wire turbo,              // Turbo speed (3.5 MHz x 2 = 7.0 MHz)
    input  wire nRESET,             // KEY0 is reset
    output wire locked,             // PLL is locked signal

    //-------- CPU control ----------------------
    output wire clk_cpu,            // Generates CPU clock of 3.5 MHz
    output wire clk_pix,            // Pixel clock (25.175 MHz or 14 MHz)
    output wire clk_ram,            // SDRAM clock 112MHz
    output wire clk_sys,            // System master clock (28 MHz)
    output wire clk_ula,				// System master clock (14 MHz)
    output wire vs_nintr,           // Generates a vertical retrace interrupt
    output wire SDRAM_CLK,          // SDRAM clock 112MHz phase shifted for chip

    //-------- Address and data buses -----------
    input  wire [15:0] A,            // Input address bus
    input  wire [7:0]  D,            // Input data bus
    output wire [7:0]  ula_data,     // Output data
    input  wire io_we,               // Write enable to data register through IO
    input  wire io_rd,               
    output wire F11,
    output wire F1,

    //-------- PS/2 Keyboard --------------------
    input  wire PS2_CLK,
    input  wire PS2_DAT,

    //-------- Audio --------------
    output wire AUDIO_L,
    output wire AUDIO_R,
    input  wire AUDIO_IN,

    //-------- VGA connector --------------------
    output wire [5:0] VGA_Rx,
    output wire [5:0] VGA_Gx,
    output wire [5:0] VGA_Bx,
    output reg VGA_HS,
    output reg VGA_VS,
    output reg VGA_HS_OSD,
    output reg VGA_VS_OSD,
	 
    output wire [12:0] vram_address,// ULA video block requests a byte from the video RAM
    input  wire [7:0] vram_data,     // ULA video block reads a byte from the video RAM
	 input  wire scandoubler_disable
);
`default_nettype none

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Instantiate PLL and clocks block
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
wire f0,f1;

pll pll_( .inclk0(CLOCK_27[0]), .c0(f0), .c1(f1), .locked(locked));

reg [5:0] counter0 = 6'b0;
wire   clk_psg = counter0[5];       //1.75MHz
assign clk_cpu = counter0[4-turbo]; //3.5MHz
assign clk_ula = counter0[2];       //14MHz
assign clk_sys = counter0[1];       //28MHz
always @(posedge f0) counter0 <= counter0 + 6'b1;

reg [4:0] counter1 = 5'b0;
always @(posedge f1) counter1 <= counter1 + 4'b1;

//`define SLOWRAM

`ifdef SLOWRAM
	assign clk_ram = counter0[0];    //56MHz
	assign SDRAM_CLK = counter1[0];  //56MHz
`else
	assign clk_ram = f0;             //112MHz
	assign SDRAM_CLK = f1;           //112MHz
`endif


//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// The ULA output data
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
reg [2:0] border;

always @(posedge clk_sys)
begin
	if(!nRESET) begin
        border <=  3'b000;
        ear_out <= 1'b0; 
        mic_out <= 1'b0;
    end else if (!A[0] && io_we) begin
        border <= D[2:0];
        ear_out <= D[4]; 
        mic_out <= D[3];
    end
end

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Instantiate audio interface
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
reg ear_out;
reg mic_out;

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Instantiate AY8910
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
wire [7:0] sound_data;
wire [7:0] psg_ch_a;
wire [7:0] psg_ch_b;
wire [7:0] psg_ch_c;
wire psg_enable = A[0] && A[15] && !A[1];

ay8910 ay8910(
	.CLK(clk_psg),
	.EN(1),
	.RESET(!nRESET),
	.BDIR(io_we && psg_enable),
	.CS(1),
	.BC(A[14] && psg_enable && (io_we || io_rd)),
	.DI(D),
	.DO(sound_data),
	.CHANNEL_A(psg_ch_a),
	.CHANNEL_B(psg_ch_b),
	.CHANNEL_C(psg_ch_c)
);

sigma_delta_dac #(.MSBI(9)) dac_l (
	.CLK(clk_ula),
	.RESET(!nRESET),
	.DACin({1'b0, psg_ch_a} + {1'b0, psg_ch_b} + {1'b0, ear_out, mic_out, AUDIO_IN, 5'b00000}),
	.DACout(AUDIO_L)
);

sigma_delta_dac #(.MSBI(9)) dac_r(
	.CLK(clk_ula),
	.RESET(!nRESET),
	.DACin({1'b0, psg_ch_c} + {1'b0, psg_ch_b} + {1'b0, ear_out, mic_out, AUDIO_IN, 5'b00000}),
	.DACout(AUDIO_R)
);

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Instantiate ULA's video subsystem
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

// VGA version
// assign clk_pix = f2; // 25.175 MHz
// assign VGA_HS_OSD = VGA_HS;
// assign VGA_VS_OSD = VGA_VS;
//video video( .*, .VGA_R(VGA_Rx), .VGA_G(VGA_Gx), .VGA_B(VGA_Bx));

// PAL version
assign clk_pix = clk_ula;
video2 video(.*, /*.scandoubler_disable(1),*/ .CLK(clk_ula), .VGA_R(VGA_Rx), .VGA_G(VGA_Gx), .VGA_B(VGA_Bx));

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Instantiate keyboard support
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
wire [4:0] KEYB;
keyboard kbd( .*, .CLK(clk_ula));

always_comb begin
    ula_data =    (A[0]==0) ? { 1'b0, AUDIO_IN, 1'b0, KEYB[4:0] } :
					(psg_enable) ? sound_data :
									   8'hFF;
end

endmodule
