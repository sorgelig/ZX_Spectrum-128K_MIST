//============================================================================
// The implementation of the Sinclair ZX Spectrum ULA
//
//  Copyright (C) 2015 Sorgelig
//
//  Based on sample ZX Spectrum code by Goran Devic
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
    input         CLOCK_27,     // Input clock 27 MHz

    output        clk_ram,      // SDRAM clock
    output        SDRAM_CLK,    // SDRAM clock phase shifted for chip
    input         turbo,
    output        clk_cpu,      // CPU clock
    output        clk_sys,      // System master clock (28 MHz)
    output        clk_ula,		  // System master clock (14 MHz)

    input         nRESET,
    output        locked,

    //-------- Address and data buses -----------
    input  [15:0] addr,         // Input address bus
    input   [7:0] din,          // Input data bus
    output  [7:0] dout,         // Output data
    input         nIORQ,
    input         nMREQ,
    input         nM1,
    input         nRD,
    input         nWR,
    input         nRFSH,
    input   [2:0] page_ram,
    output        nINT,         // Generates a vertical retrace interrupt

    //------- Keyboard ------------
    input         PS2_CLK,
    input         PS2_DAT,
    output [11:1] Fn,
    output  [2:0] mod,

    //-------- Audio --------------
    output        AUDIO_L,
    output        AUDIO_R,
    input         AUDIO_IN,

    //-------- Video --------------
    input         mZX,
    input         m128,
    input         SPI_SCK,
    input         SPI_SS3,
    input         SPI_DI,

    input         scandoubler_disable,
    output  [5:0] VGA_R,
    output  [5:0] VGA_G,
    output  [5:0] VGA_B,
    output        VGA_HS,
    output        VGA_VS,

    output [12:0] vram_addr,
    input   [7:0] vram_dout
);
`default_nettype none


////////////////////   CLOCKS   ///////////////////
wire clk_56m;
pll pll(.inclk0(CLOCK_27), .c0(clk_ram), .c1(SDRAM_CLK), .c2(clk_56m), .locked(locked));

reg   [4:0] counter0 = 0;
wire        clk_psg = counter0[4];  //1.75MHz
assign      clk_ula = counter0[1];  //14MHz
assign      clk_sys = counter0[0];  //28MHz
assign      dout = data;
reg   [7:0] data;
reg         clk_cpu_turbo;
reg   [3:0] counterT = 0;

always @(posedge clk_56m) begin
	counter0 <= counter0 + 1'd1;
	counterT <= counterT + 1'd1;
	if(counterT == 6) begin
		counterT <= 0;
		clk_cpu_turbo <= ~clk_cpu_turbo;
	end
end

wire clk_cpu_std;
clk_switch switch
(
	.clk_a(clk_cpu_std),
	.clk_b(clk_cpu_turbo),
	.select(~turbo),
	.out_clk(clk_cpu)
);


////////////////////  ULA PORTS  ///////////////////
wire        io_we  = ~nIORQ & ~nWR & nM1;
reg   [2:0] border;

always @(posedge clk_sys) begin
	if(!nRESET) begin
        border  <= 0;
        ear_out <= 0; 
        mic_out <= 0;
    end else if(~addr[0] & io_we) begin
        border  <= din[2:0];
        ear_out <= din[4]; 
        mic_out <= din[3];
    end
end

always_comb begin
	casex({addr[0], psg_enable})
		'b0X: data = {1'b1, AUDIO_IN, 1'b1, key_data[4:0]};
		'b11: data = (addr[14] ? sound_data : 8'hFF);
		'b10: data = port_ff;
	endcase
end


////////////////////   AUDIO   ///////////////////
reg         ear_out;
reg         mic_out;

wire  [7:0] sound_data;
wire  [7:0] psg_ch_a;
wire  [7:0] psg_ch_b;
wire  [7:0] psg_ch_c;
wire        psg_enable = addr[0] & addr[15] & ~addr[1];
wire        psg_dir = psg_delay & io_we & psg_enable;
reg         psg_delay;

always @(negedge clk_cpu) psg_delay <= io_we && psg_enable;

ym2149 ym2149
(
	.CLK(clk_psg),
	.RESET(~nRESET),
	.BDIR(psg_dir),
	.BC(addr[14]),
	.DI(din),
	.DO(sound_data),
	.CHANNEL_A(psg_ch_a),
	.CHANNEL_B(psg_ch_b),
	.CHANNEL_C(psg_ch_c),
	.SEL(0),
	.MODE(0)
);

sigma_delta_dac #(.MSBI(10)) dac_l
(
	.CLK(clk_ula),
	.RESET(~nRESET),
	.DACin({1'b0, psg_ch_a, 1'b0} + {2'b00, psg_ch_b} + {2'b00, ear_out, mic_out, AUDIO_IN, 5'b00000}),
	.DACout(AUDIO_L)
);

sigma_delta_dac #(.MSBI(10)) dac_r
(
	.CLK(clk_ula),
	.RESET(~nRESET),
	.DACin({1'b0, psg_ch_c, 1'b0} + {2'b00, psg_ch_b} + {2'b00, ear_out, mic_out, AUDIO_IN, 5'b00000}),
	.DACout(AUDIO_R)
);


////////////////////   VIDEO   ///////////////////
wire  [7:0] port_ff;
video video(.*, .CLK(clk_ula), .clk_cpu(clk_cpu_std));


//////////////////   KEYBOARD   //////////////////
wire  [4:0] key_data;
keyboard kbd( .*, .CLK(clk_ula));

endmodule


//////////////   CLOCK SWITCHER   ////////////////
module clk_switch 
(
   input  clk_a,
   input  clk_b,
   input  select,
   output out_clk
);

reg q1,q2,q3,q4;

always @ (posedge clk_a) begin
	q1 <= q4;
	q3 <= or_one;
end

always @ (posedge clk_b) begin
	q2 <= q3;
	q4 <= or_two;
end

wire or_one    = (~q1) | (~select);
wire or_two    = (~q2) | (select);
wire or_three  = (q3)  | (clk_a);
wire or_four   = (q4)  | (clk_b);

assign out_clk = or_three & or_four;

endmodule
