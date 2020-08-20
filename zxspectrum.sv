//============================================================================
// Sinclair ZX Spectrum host board
// 
//  Port to MIST board. 
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
module zxspectrum
(
   input         CLOCK_27,   // Input clock 27 MHz

   output  [5:0] VGA_R,
   output  [5:0] VGA_G,
   output  [5:0] VGA_B,
   output        VGA_HS,
   output        VGA_VS,

   output        LED,

   output        AUDIO_L,
   output        AUDIO_R,

   output        UART_TX,
   input         UART_RX,

   input         SPI_SCK,
   output        SPI_DO,
   input         SPI_DI,
   input         SPI_SS2,
   input         SPI_SS3,
   input         CONF_DATA0,

   output [12:0] SDRAM_A,
   inout  [15:0] SDRAM_DQ,
   output        SDRAM_DQML,
   output        SDRAM_DQMH,
   output        SDRAM_nWE,
   output        SDRAM_nCAS,
   output        SDRAM_nRAS,
   output        SDRAM_nCS,
   output  [1:0] SDRAM_BA,
   output        SDRAM_CLK,
   output        SDRAM_CKE
);
`default_nettype none

assign LED = ~(ioctl_download | tape_led);

localparam CONF_BDI   = "(BDI)";
localparam CONF_PLUSD = "(+D) ";

`include "build_id.v"
localparam CONF_STR = {
	"SPECTRUM;;",
	"S1,TRDIMGDSKMGT,Load Disk;",
	"F,TAPCSWTZX,Load Tape;",
	"O6,Fast tape load,On,Off;",
	"O7,Joystick swap,Off,On;",
	"O89,Video timings,ULA-48,ULA-128,Pentagon;",
	"OFG,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%;",
	"OAC,Memory,Standard 128K,Pentagon 1024K,Profi 1024K,Standard 48K,+2A/+3;",
	"ODE,Features,ULA+ & Timex,ULA+,Timex,None;",
	"OHI,MMC Card,Off,divMMC,ZXMMC;",
	"OKL,General Sound,512KB,1MB,2MB,Disabled;",
	"T0,Reset;",
	"V,v3.40.",`BUILD_DATE
};


////////////////////   CLOCKS   ///////////////////
wire clk_sys;
wire locked;

pll pll
(
	.inclk0(CLOCK_27),
	.c0(clk_sys),
	.c1(SDRAM_CLK),
	.locked(locked)
);

reg  ce_psg;  //1.75MHz
reg  ce_7mp;
reg  ce_7mn;
reg  ce_14m;

reg  pause;
reg  cpu_en = 1;
reg  ce_cpu_tp;
reg  ce_cpu_tn;

wire ce_cpu_p = cpu_en & cpu_p;
wire ce_cpu_n = cpu_en & cpu_n;
wire ce_cpu   = cpu_en & ce_cpu_tp;
wire ce_wd1793 = ce_cpu;
wire ce_u765 = ce_cpu;
wire ce_tape = ce_cpu;

wire cpu_p = ~&turbo ? ce_cpu_tp : ce_cpu_sp;
wire cpu_n = ~&turbo ? ce_cpu_tn : ce_cpu_sn;

always @(posedge clk_sys) begin
	reg [5:0] counter = 0;

	counter <=  counter + 1'd1;

	ce_14m  <= !counter[2:0];
	ce_7mp  <= !counter[3] & !counter[2:0];
	ce_7mn  <=  counter[3] & !counter[2:0];
	ce_psg  <= !counter[5:0] & ~pause;

	ce_cpu_tp <= !(counter & turbo);
	ce_cpu_tn <= !((counter & turbo) ^ turbo ^ turbo[4:1]);
end

reg [4:0] turbo = 5'b11111, turbo_key = 5'b11111;
always @(posedge clk_sys) begin
	reg [9:4] old_Fn;
	old_Fn <= Fn[9:4];

	if(reset) pause <= 0;

	if(!mod) begin
		if(~old_Fn[4] & Fn[4]) turbo_key <= 5'b11111; //3.5 MHz
		if(~old_Fn[5] & Fn[5]) turbo_key <= 5'b01111; //  7 Mhz
		if(~old_Fn[6] & Fn[6]) turbo_key <= 5'b00111; // 14 MHz
		if(~old_Fn[7] & Fn[7]) turbo_key <= 5'b00011; // 28 MHz
		if(~old_Fn[8] & Fn[8]) turbo_key <= 5'b00001; // 56 MHz
		if(~old_Fn[9] & Fn[9]) pause <= ~pause;
	end
end

wire [4:0] turbo_req = (tape_active & ~status[6]) ? 5'b00001 : turbo_key;
always @(posedge clk_sys) begin
	reg [1:0] timeout;

	if(cpu_n) begin
		if(timeout) timeout <= timeout + 1'd1;
		if(turbo != turbo_req) begin
			cpu_en  <= 0;
			timeout <= 1;
			turbo   <= turbo_req;
		end else if(!cpu_en & !timeout & ram_ready) begin
			cpu_en  <= ~pause;
		end else if(!turbo[4:3] & !ram_ready) begin // SDRAM wait for 14MHz/28MHz/56MHz turbo
			cpu_en  <= 0;
		end else if(cpu_en & pause) begin
			cpu_en  <= 0;
		end
	end
end


//////////////////   MIST ARM I/O   ///////////////////
wire [10:0] ps2_key;
wire [24:0] ps2_mouse;

wire  [7:0] joystick_0;
wire  [7:0] joystick_1;
wire  [7:0] joy0 = status[7] ? joystick_1 : joystick_0; // Kempston
wire  [7:0] joy1 = status[7] ? joystick_0 : joystick_1; // Sinclair

wire  [1:0] buttons;
wire  [1:0] switches;
wire        scandoubler_disable;
wire        ypbpr;
wire [31:0] status;

wire 			sd_rd_plus3;
wire 			sd_wr_plus3;
wire [31:0] sd_lba_plus3;
wire [7:0]  sd_buff_din_plus3;

wire 			sd_rd_wd;
wire 			sd_wr_wd;
wire [31:0] sd_lba_wd;
wire [7:0]  sd_buff_din_wd;

wire        sd_busy_mmc;
wire        sd_rd_mmc;
wire        sd_wr_mmc;
wire [31:0] sd_lba_mmc;
wire  [7:0] sd_buff_din_mmc;

wire [31:0] sd_lba = sd_busy_mmc ? sd_lba_mmc : (plus3_fdd_ready ? sd_lba_plus3 : sd_lba_wd);
wire  [1:0] sd_rd = { sd_rd_plus3 | sd_rd_wd, sd_rd_mmc };
wire  [1:0] sd_wr = { sd_wr_plus3 | sd_wr_wd, sd_wr_mmc };

wire        sd_ack;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din = sd_busy_mmc ? sd_buff_din_mmc : (plus3_fdd_ready ? sd_buff_din_plus3 : sd_buff_din_wd);
wire        sd_buff_wr;
wire  [1:0] img_mounted;
wire [31:0] img_size;

wire        sd_ack_conf;
wire        sd_conf;
wire        sd_sdhc;

wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire        ioctl_download;
wire  [7:0] ioctl_index;

mist_io #(.STRLEN(($size(CONF_STR)>>3)+5)) mist_io
(
	.*,
	.ioctl_ce(1),
	.conf_str({CONF_STR, plusd_en ? CONF_PLUSD : CONF_BDI}),

	// unused
	.ps2_kbd_clk(),
	.ps2_kbd_data(),
	.ps2_mouse_clk(),
	.ps2_mouse_data(),
	.joystick_analog_0(),
	.joystick_analog_1()
);


///////////////////   CPU   ///////////////////
wire [15:0] addr;
wire  [7:0] cpu_din;
wire  [7:0] cpu_dout;
wire        nM1;
wire        nMREQ;
wire        nIORQ;
wire        nRD;
wire        nWR;
wire        nRFSH;
wire        nBUSACK;
wire        nINT;
wire        nBUSRQ = ~ioctl_download;

wire        io_wr = ~nIORQ & ~nWR & nM1;
wire        io_rd = ~nIORQ & ~nRD & nM1;
wire        m1    = ~nM1 & ~nMREQ;

// for edge detection
reg         old_wr;
reg         old_rd;
reg         old_m1;

wire[211:0]	cpu_reg;  // IFF2, IFF1, IM, IY, HL', DE', BC', IX, HL, DE, BC, PC, SP, R, I, F', A', F, A
wire [15:0] reg_DE  = cpu_reg[111:96];
wire  [7:0] reg_A   = cpu_reg[7:0];

T80pa cpu
(
	.RESET_n(~reset),
	.CLK(clk_sys),
	.CEN_p(ce_cpu_p),
	.CEN_n(ce_cpu_n),
	.WAIT_n(1),
	.INT_n(nINT),
	.NMI_n(~NMI),
	.BUSRQ_n(nBUSRQ),
	.M1_n(nM1),
	.MREQ_n(nMREQ),
	.IORQ_n(nIORQ),
	.RD_n(nRD),
	.WR_n(nWR),
	.RFSH_n(nRFSH),
	.HALT_n(1),
	.BUSAK_n(nBUSACK),
	.A(addr),
	.DO(cpu_dout),
	.DI(cpu_din),
	.REG(cpu_reg)
);

always_comb begin
	casex({nMREQ, tape_dout_en, ~nM1 | nIORQ | nRD, fdd_sel | fdd_sel2 | plus3_fdd, mf3_port, addr[7:0]==8'h1F, portBF, gs_sel, psg_enable, ulap_sel, addr[0]})
		'b01XXXXXXXXX: cpu_din = tape_dout;
		'b00XXXXXXXXX: cpu_din = ram_dout;
		'b1X01XXXXXXX: cpu_din = fdd_dout;
		'b1X001XXXXXX: cpu_din = (addr[14:13] == 2'b11 ? page_reg : page_reg_plus3);
		'b1X0001XXXXX: cpu_din = mouse_sel ? mouse_data : {2'b00, joy0[5:0]};
		'b1X00001XXXX: cpu_din = {page_scr_copy, 7'b1111111};
		'b1X000001XXX: cpu_din = gs_dout;
		'b1X0000001XX: cpu_din = (addr[14] ? sound_data : 8'hFF);
		'b1X00000001X: cpu_din = ulap_dout;
		'b1X000000001: cpu_din = port_ff;
		'b1X000000000: cpu_din = {1'b1, ~tape_in, 1'b1, key_data[4:0] & ({5{addr[12]}} | ~{joy1[1:0], joy1[2], joy1[3], joy1[4]})};
		'b1X1XXXXXXXX: cpu_din = 8'hFF;
	endcase
end

reg init_reset = 1;
always @(posedge clk_sys) begin
	reg old_download;
	old_download <= ioctl_download;
	if(old_download & ~ioctl_download) init_reset <= 0;
end

reg  NMI;
reg  reset;
reg  cold_reset_btn;
reg  warm_reset_btn;
reg  shdw_reset_btn;
wire cold_reset = cold_reset_btn | init_reset;
wire warm_reset = warm_reset_btn;
wire shdw_reset = shdw_reset_btn & ~plus3;

always @(posedge clk_sys) begin
	reg old_F11;

	old_F11 <= Fn[11];

	reset <= buttons[1] | status[0] | cold_reset | warm_reset | shdw_reset | Fn[10];

	if(reset | ~Fn[11]) NMI <= 0;
	else if(~old_F11 & Fn[11] & (mod[2:1] == 0)) NMI <= 1;

	cold_reset_btn <= (mod[2:1] == 1) & Fn[11];
	warm_reset_btn <= (mod[2:1] == 2) & Fn[11];
	shdw_reset_btn <= (mod[2:1] == 3) & Fn[11];
end

always @(posedge clk_sys) begin
	old_rd <= io_rd;
	old_wr <= io_wr;
	old_m1 <= m1;
end

//////////////////   MEMORY   //////////////////
wire        dma = (reset | ~nBUSACK) & ~nBUSRQ;
reg  [20:0] ram_addr;
reg   [7:0] ram_din;
reg         ram_we;
reg         ram_rd;
wire  [7:0] ram_dout;
wire        ram_ready;

always_comb begin
	casex({page_special, addr[15:14]})
		'b0_00: ram_addr = { 3'b101, page_rom, addr[13:0] }; //ROM
		'b0_01: ram_addr = {   4'd0, 3'd5,     addr[13:0] }; //Non-special page modes
		'b0_10: ram_addr = {   4'd0, 3'd2,     addr[13:0] };
		'b0_11: ram_addr = {   1'b0, page_ram, addr[13:0] };
		'b1_00: ram_addr = {   4'd0,                       |page_reg_plus3[2:1], 2'b00, addr[13:0] }; //Special page modes
		'b1_01: ram_addr = {   4'd0, |page_reg_plus3[2:1], &page_reg_plus3[2:1],  1'b1, addr[13:0] };
		'b1_10: ram_addr = {   4'd0,                       |page_reg_plus3[2:1], 2'b10, addr[13:0] };
		'b1_11: ram_addr = {   4'd0,     ~page_reg_plus3[2] & page_reg_plus3[1], 2'b11, addr[13:0] };
	endcase

	casex({dma, tape_req})
		'b1X: ram_din <= ioctl_dout;
		'b01: ram_din <= 0;
		'b00: ram_din <= cpu_dout;
	endcase

	casex({dma, tape_req})
		'b1X: ram_rd = 0;
		'b01: ram_rd = ~nMREQ;
		'b00: ram_rd = ~nMREQ & ~nRD;
	endcase

	casex({dma, tape_req})
		'b1X: ram_we = ioctl_wr;
		'b01: ram_we = 0;
		'b00: ram_we = (page_special | addr[15] | addr[14] | ((plusd_mem | mf128_mem) & addr[13])) & ~nMREQ & ~nWR;
	endcase
end


sdram ram
(
	.*,
	.init_n(locked),
	.clk(clk_sys),
	.clkref(ce_14m),

	// port1 is CPU/tape
	.port1_req(sdram_req),
	.port1_a(sdram_addr[23:1]),
	.port1_ds(sdram_we ? {sdram_addr[0], ~sdram_addr[0]} : 2'b11),
	.port1_d({sdram_din, sdram_din}),
	.port1_q(sdram_dout),
	.port1_we(sdram_we),
	.port1_ack(sdram_ack),

	// port 2 is General Sound CPU
	.port2_req(gs_sdram_req),
	.port2_a(gs_sdram_addr[23:1]),
	.port2_ds(gs_sdram_we ? {gs_sdram_addr[0], ~gs_sdram_addr[0]} : 2'b11),
	.port2_q(gs_sdram_dout),
	.port2_d({gs_sdram_din, gs_sdram_din}),
	.port2_we(gs_sdram_we),
	.port2_ack(gs_sdram_ack)
);

assign SDRAM_CKE = 1;

// CPU/tape port control
reg  [24:0] sdram_addr;
wire [15:0] sdram_dout;
reg   [7:0] sdram_din;
wire        sdram_ack;
reg         sdram_req;
reg         sdram_we;

reg         ram_rd_old;
reg         ram_rd_old2; // use the delayed signal to wait for mf128_mem, plusd_mem, etc...
reg         ram_we_old;
wire        new_ram_req = (~ram_rd_old2 & ram_rd_old) || (~ram_we_old & ram_we);

always @(posedge clk_sys) begin

	ram_rd_old  <= ram_rd;
	ram_rd_old2 <= ram_rd_old;
	ram_we_old <= ram_we;

	if (new_ram_req) begin

		sdram_req <= ~sdram_req;
		sdram_we <= ram_we;
		sdram_din <= ram_din;

		casex({dma, tape_req})
			'b1X: sdram_addr <= ioctl_addr;
			'b01: sdram_addr <= tape_addr;
			'b00: sdram_addr <= ram_addr;
		endcase;

	end
end

assign ram_dout = sdram_addr[0] ? sdram_dout[15:8] : sdram_dout[7:0];
assign ram_ready = (sdram_ack == sdram_req) & ~new_ram_req;

// GS port control
wire [20:0] gs_mem_addr;
wire  [7:0] gs_mem_dout;
wire  [7:0] gs_mem_din;
wire        gs_mem_rd;
wire        gs_mem_wr;
wire        gs_mem_ready;
reg   [7:0] gs_mem_mask;

always_comb begin
	gs_mem_mask = 0;
	case(status[21:20])
		0: if(gs_mem_addr[20:19]) gs_mem_mask = 8'hFF; // 512K
		1: if(gs_mem_addr[20])    gs_mem_mask = 8'hFF; // 1024K
		2,3:                      gs_mem_mask = 0;
	endcase
end

reg  [24:0] gs_sdram_addr;
wire [15:0] gs_sdram_dout;
reg   [7:0] gs_sdram_din;
wire        gs_sdram_ack;
reg         gs_sdram_req;
reg         gs_sdram_we;

wire        gs_rom_we = ioctl_wr && (ioctl_index == 0);
reg         gs_mem_rd_old;
reg         gs_mem_wr_old;
wire        new_gs_mem_req = (~gs_mem_rd_old & gs_mem_rd) || (~gs_mem_wr_old & gs_mem_wr) || gs_rom_we;

always @(posedge clk_sys) begin

	gs_mem_rd_old <= gs_mem_rd;
	gs_mem_wr_old <= gs_mem_wr;

	if (new_gs_mem_req) begin
		// don't issue a new request if a read followed by a read and the current word address is the same as the previous
		if (gs_sdram_we | gs_rom_we | gs_mem_wr | gs_sdram_addr[20:1] != gs_mem_addr[20:1]) begin
			gs_sdram_req <= ~gs_sdram_req;
			gs_sdram_we <= gs_rom_we | gs_mem_wr;
			gs_sdram_din <= gs_rom_we ? ioctl_dout : gs_mem_din;
		end
		gs_sdram_addr <= gs_rom_we ? (ioctl_addr - 24'h180000) : gs_mem_addr;
	end
end

assign gs_mem_dout = gs_sdram_addr[0] ? gs_sdram_dout[15:8] : gs_sdram_dout[7:0];
assign gs_mem_ready = (gs_sdram_ack == gs_sdram_req) & ~new_gs_mem_req;

// VRAM
wire vram_sel = (ram_addr[20:16] == 1) & ram_addr[14] & ~dma & ~tape_req;
vram vram
(
    .clock(clk_sys),

    .wraddress({ram_addr[15], ram_addr[13:0]}),
    .data(ram_din),
    .wren(ram_we & vram_sel),

    .rdaddress(vram_addr),
    .q(vram_dout)
);

(* maxfan = 10 *) reg	zx48;
(* maxfan = 10 *) reg	p1024;
(* maxfan = 10 *) reg	pf1024;
(* maxfan = 10 *) reg	plus3;
reg        page_scr_copy;
reg        shadow_rom;
reg  [7:0] page_reg;
reg  [7:0] page_reg_plus3;
reg  [7:0] page_reg_p1024;
wire       page_disable = zx48 | (~p1024 & page_reg[5]) | (p1024 & page_reg_p1024[2] & page_reg[5]);
wire       page_scr     = page_reg[3];
wire [5:0] page_ram     = {page_128k, page_reg[2:0]};
wire       page_write   = ~addr[15] & ~addr[1] & (addr[14] | ~plus3) & ~page_disable; //7ffd
wire       page_write_plus3 = ~addr[1] & addr[12] & ~addr[13] & ~addr[14] & ~addr[15] & plus3 & ~page_disable; //1ffd
wire       page_special = page_reg_plus3[0];
wire       motor_plus3 = page_reg_plus3[3];
wire       page_p1024 = addr[15] & addr[14] & addr[13] & ~addr[12] & ~addr[3]; //eff7
reg  [2:0] page_128k;

reg  [3:0] page_rom;
wire       active_48_rom = zx48 | (page_reg[4] & ~plus3) | (plus3 & page_reg[4] & page_reg_plus3[2] & ~page_special);

always_comb begin
	casex({shadow_rom, trdos_en, plusd_mem, mf128_mem, plus3})
		'b1XXXX: page_rom <= 4'b0100; //shadow
		'b01XXX: page_rom <= 4'b0101; //trdos
		'b001XX: page_rom <= 4'b1100; //plusd
		'b0001X: page_rom <= { 2'b11, plus3, ~plus3 }; //MF128/+3
		'b00001: page_rom <= { 2'b10, page_reg_plus3[2], page_reg[4] }; //+3
		'b00000: page_rom <= { zx48, 2'b11, zx48 | page_reg[4] }; //up to +2
	endcase
end

always @(posedge clk_sys) begin
	reg old_reset;
	reg [2:0] rmod;

	old_reset <= reset;
	if(~old_reset & reset) rmod <= mod;

	if(reset) begin
		page_scr_copy <= 0;
		page_reg    <= 0;
		page_reg_plus3 <= 0; 
		page_reg_p1024 <= 0;
		page_128k   <= 0;
		page_reg[4] <= Fn[10];
		page_reg_plus3[2] <= Fn[10];
		shadow_rom <= shdw_reset & ~plusd_en;
		if(Fn[10] && (rmod == 1)) begin
			p1024  <= 0;
			pf1024 <= 0;
			zx48   <= ~plus3;
		end else begin
			p1024 <= (status[12:10] == 1);
			pf1024<= (status[12:10] == 2);
			zx48  <= (status[12:10] == 3);
			plus3 <= (status[12:10] == 4);
		end
	end else begin
		if(m1 && ~old_m1 && addr[15:14]) shadow_rom <= 0;
		if(m1 && ~old_m1 && ~plusd_en && ~mod[0] && (addr == 'h66) && ~plus3) shadow_rom <= 1; 

		if(io_wr & ~old_wr) begin
			if(page_write) begin
				page_reg  <= cpu_dout;
				if(p1024 & ~page_reg_p1024[2])	page_128k[2:0] <= { cpu_dout[5], cpu_dout[7:6] };
				if(~plusd_mem) page_scr_copy <= cpu_dout[3];
			end else if (page_write_plus3) begin
				page_reg_plus3 <= cpu_dout; 
			end
			if(pf1024 & (addr == 'hDFFD)) page_128k <= cpu_dout[2:0];
			if(p1024 & page_p1024) page_reg_p1024 <= cpu_dout;
		end
	end
end


////////////////////  ULA PORT  ///////////////////
reg [2:0] border_color;
reg       ear_out;
reg       mic_out;

wire ula_we = ~addr[0] & ~nIORQ & ~nWR & nM1;
always @(posedge clk_sys) begin
	reg old_we;
	old_we <= ula_we;

	if(reset) {ear_out, mic_out} <= 2'b00;
	else if(ula_we & ~old_we) begin
		border_color <= cpu_dout[2:0];
		ear_out <= cpu_dout[4]; 
		mic_out <= cpu_dout[3];
	end
end


////////////////////   AUDIO   ///////////////////
wire [7:0] sound_data;
wire [7:0] psg_ch_a;
wire [7:0] psg_ch_b;
wire [7:0] psg_ch_c;
wire       psg_enable = addr[0] & addr[15] & ~addr[1];
wire       psg_we     = psg_enable & ~nIORQ & ~nWR & nM1;
reg        psg_reset;

// Turbosound card (Dual AY/YM chips)
turbosound turbosound
(
	.CLK(clk_sys),
	.CE(ce_psg),
	.RESET(reset | psg_reset),
	.BDIR(psg_we),
	.BC(addr[14]),
	.DI(cpu_dout),
	.DO(sound_data),
	.CHANNEL_A(psg_ch_a),
	.CHANNEL_B(psg_ch_b),
	.CHANNEL_C(psg_ch_c),
	.SEL(0),
	.MODE(0),

	.IOA_in(0),
	.IOB_in(0)
);

wire  [7:0] gs_dout;
wire [14:0] gs_l, gs_r;
wire gs_sel = (addr[7:0] ==? 'b1011?011) & ~&status[21:20];

reg [3:0] gs_ce_count;

always @(posedge clk_sys) begin
	reg gs_no_wait;

	if(reset) begin
		gs_ce_count <= 0;
		gs_no_wait <= 1;
	end else begin
		if (gs_ce_p) gs_no_wait <= 0;
		if (gs_mem_ready) gs_no_wait <= 1;
		if (gs_ce_count == 4'd7) begin
			if (gs_mem_ready | gs_no_wait) gs_ce_count <= 0;
		end else
			gs_ce_count <= gs_ce_count + 1'd1;

	end
end

// 14 MHz (112MHz/8) clock enable for GS card
wire gs_ce_p = gs_ce_count == 0;
wire gs_ce_n = gs_ce_count == 4;

// General Sound
gs #(.INT_DIV(373)) gs
(
	.RESET(reset),
	.CLK(clk_sys),
	.CE_N(gs_ce_n),
	.CE_P(gs_ce_p),

	.A(addr[3]),
	.DI(cpu_dout),
	.DO(gs_dout),
	.CS_n(~nM1 | nIORQ | ~gs_sel),
	.WR_n(nWR),
	.RD_n(nRD),

	.MEM_ADDR(gs_mem_addr),
	.MEM_DI(gs_mem_din),
	.MEM_DO(gs_mem_dout | gs_mem_mask),
	.MEM_RD(gs_mem_rd),
	.MEM_WR(gs_mem_wr),
	.MEM_WAIT(~gs_mem_ready),

	.OUTL(gs_l),
	.OUTR(gs_r)
);

sigma_delta_dac #(14) dac_l
(
	.CLK(clk_sys),
	.RESET(reset),
	.DACin({~gs_l[14], gs_l[13:0]} + {2'b00, psg_ch_a, 5'd0} + {3'b000, psg_ch_b, 4'd0} + {2'b00, ear_out, mic_out, tape_in, 10'd0}),
	.DACout(AUDIO_L)
);

sigma_delta_dac #(14) dac_r
(
	.CLK(clk_sys),
	.RESET(reset),
	.DACin({~gs_r[14], gs_r[13:0]} + {2'b00, psg_ch_c, 5'd0} + {3'b000, psg_ch_b, 4'd0} + {2'b00, ear_out, mic_out, tape_in, 10'd0}),
	.DACout(AUDIO_R)
);


////////////////////   VIDEO   ///////////////////
(* maxfan = 10 *) wire        ce_cpu_sn;
(* maxfan = 10 *) wire        ce_cpu_sp;
wire [14:0] vram_addr;
wire  [7:0] vram_dout;
wire  [7:0] port_ff;
wire        ulap_sel;
wire  [7:0] ulap_dout;

reg mZX, m128;
always_comb begin
	case(status[9:8])
		      0: {mZX, m128} <= 2'b10;
		      1: {mZX, m128} <= 2'b11;
		default: {mZX, m128} <= 2'b00;
	endcase
end

wire [1:0] scale = status[16:15];
wire [2:0] Rx, Gx, Bx;
wire       HSync, VSync, HBlank;
wire       ulap_ena, ulap_mono, mode512;
wire       ulap_avail = ~status[14] & ~trdos_en;
wire       tmx_avail = ~status[13] & ~trdos_en;
wire       snow_ena = &turbo & ~plus3;
ULA ULA(.*, .din(cpu_dout), .page_ram(page_ram[2:0]));

video_mixer #(.LINE_LENGTH(896), .HALF_DEPTH(1)) video_mixer
(
	.*,
	.ce_pix(ce_7mp | ce_7mn),
	.ce_pix_actual(ce_7mp | (mode512 & ce_7mn)),
	.hq2x(scale == 1),
	.scanlines(scandoubler_disable ? 2'b00 : {scale==3, scale==2}),

	.line_start(0),
	.ypbpr_full(1),

	.R(Rx),
	.G(Gx),
	.B(Bx),
	.mono(ulap_ena & ulap_mono)
);

////////////////////   HID   ////////////////////
wire [11:1] Fn;
wire  [2:0] mod;
wire  [4:0] key_data;
keyboard kbd( .* );

reg         mouse_sel;
wire  [7:0] mouse_data;
mouse mouse( .*, .reset(cold_reset), .addr(addr[10:8]), .sel(), .dout(mouse_data));

always @(posedge clk_sys) begin
	reg old_status = 0;
	old_status <= ps2_mouse[24];

	if(joy0[5:0]) mouse_sel <= 0;
	if(old_status != ps2_mouse[24]) mouse_sel <= 1;
end


//////////////////   MF128   ///////////////////
reg         mf128_mem;
reg         mf128_en; // enable MF128 page-in from NMI till reset (or soft off)
wire        mf128_port = ~addr[6] & addr[5] & addr[4] & addr[1];
// read paging registers saved in MF3 (7f3f, 1f3f)
wire        mf3_port = mf128_port & ~addr[7] & (addr[12:8] == 'h1f) & plus3 & mf128_en;

always @(posedge clk_sys) begin

	if(reset) {mf128_mem, mf128_en} <= 0;
	else if(~old_rd & io_rd) begin
		//page in/out for port IN
		if(mf128_port) mf128_mem <= (addr[7] ^ plus3) & mf128_en;
	end else if(~old_wr & io_wr) begin
		//Soft hide
		if(mf128_port) mf128_en <= addr[7] & mf128_en;
	end

	if(~old_m1 & m1 & mod[0] & (addr == 'h66)) {mf128_mem, mf128_en} <= 2'b11;
end

//////////////////   MMC   //////////////////
wire        mmc_sel;
wire  [7:0] mmc_dout;

wire        spi_ss;
wire        spi_clk;
wire        spi_di;
wire        spi_do;

divmmc divmmc
(
    .*,
    .enable(1),
    .mode(status[18:17]), //00-off, 01-divmmc, 10-zxmmc
    .din(cpu_dout),
    .dout(mmc_dout),
    .active_io(mmc_sel)
);

sd_card sd_card
(
    .*,
    .img_mounted(img_mounted[0]), //first slot for SD-card emulation
    .sd_busy(sd_busy_mmc),
    .sd_rd(sd_rd_mmc),
    .sd_wr(sd_wr_mmc),
    .sd_lba(sd_lba_mmc),
    .sd_buff_din(sd_buff_din_mmc),
    .allow_sdhc(1),
    .sd_cs(spi_ss),
    .sd_sck(spi_clk),
    .sd_sdi(spi_do),
    .sd_sdo(spi_di)
);

///////////////////   FDC   ///////////////////
reg         plusd_en;
reg         plusd_mem;
wire        plusd_ena = plusd_stealth ? plusd_mem : plusd_en;
wire        fdd_sel2 = plusd_ena & &addr[7:5] & ~addr[2] & &addr[1:0];

reg         trdos_en;
wire  [7:0] wd_dout;
wire        fdd_rd;
reg         fdd_ready;
reg         fdd_drive1;
reg         fdd_side;
reg         fdd_reset;
wire        fdd_intrq;
wire        fdd_drq;
wire        fdd_sel  = trdos_en & addr[2] & addr[1];
wire  [7:0] wdc_dout = (addr[7] & ~plusd_en) ? {fdd_intrq, fdd_drq, 6'h3F} : wd_dout;

reg         plus3_fdd_ready;
wire        plus3_fdd = ~addr[1] & addr[13] & ~addr[14] & ~addr[15] & plus3 & ~page_disable;
wire [7:0]  u765_dout;

wire  [7:0] fdd_dout = plus3_fdd ? u765_dout : wdc_dout;

//
// current +D implementation notes:
// 1) all +D ports (except page out port) are disabled if +D memory isn't paged in.
// 2) only possible way to page in is through hooks at h08, h3A, h66 addresses.
//
// This may break compatibility with some apps written specifically for +D using 
// direct port access (badly written apps), but won't introduce
// incompatibilities with +D unaware apps.
//
wire        plusd_stealth = 1;

// read video page.
// available for MF128 and PlusD(patched).
wire        portBF = mf128_port & addr[7] & (mf128_mem | plusd_mem);

always @(posedge clk_sys) begin
	reg old_mounted;

	if(cold_reset) {plus3_fdd_ready, fdd_ready, plusd_en} <= 0;
	if(reset)      {plusd_mem, trdos_en} <= 0;

	old_mounted <= img_mounted[1];
	if(~old_mounted & img_mounted[1]) begin
	   //Only TRDs on +3
		fdd_ready <= (!ioctl_index[7:6] & plus3) | ~plus3;
		plusd_en  <= |ioctl_index[7:6] & ~plus3;
		//DSK only for +3
		plus3_fdd_ready <= plus3 & (ioctl_index[7:6] == 2);
	end

	psg_reset <= 0;

	if(plusd_en) begin
		trdos_en <= 0;
		if(~old_wr & io_wr  & (addr[7:0] == 'hEF) & plusd_ena) {fdd_side, fdd_drive1} <= {cpu_dout[7], cpu_dout[1:0] != 2};
		if(~old_wr & io_wr  & (addr[7:0] == 'hE7)) plusd_mem <= 0;
		if(~old_rd & io_rd  & (addr[7:0] == 'hE7) & ~plusd_stealth) plusd_mem <= 1;
		if(~old_m1 & m1 & ((addr == 'h08) | (addr == 'h3A) | (~mod[0] & (addr == 'h66)))) {psg_reset,plusd_mem} <= {(addr == 'h66), 1'b1};
	end else begin
		plusd_mem <= 0;
		if(~old_wr & io_wr & fdd_sel & addr[7]) {fdd_side, fdd_reset, fdd_drive1} <= {~cpu_dout[4], ~cpu_dout[2], !cpu_dout[1:0]};
		if(m1 && ~old_m1) begin
			if(addr[15:14]) trdos_en <= 0;
				else if((addr[13:8] == 'h3D) & active_48_rom) trdos_en <= 1;
				//else if(~mod[0] & (addr == 'h66)) trdos_en <= 1;
		end
	end
end

wd1793 #(1,0) fdd
(
	.clk_sys(clk_sys),
	.ce(ce_wd1793),
	.reset((fdd_reset & ~plusd_en) | reset),
	.io_en((fdd_sel2 | (fdd_sel & ~addr[7])) & ~nIORQ & nM1),
	.rd(~nRD),
	.wr(~nWR),
	.addr(plusd_en ? addr[4:3] : addr[6:5]),
	.din(cpu_dout),
	.dout(wd_dout),
	.drq(fdd_drq),
	.intrq(fdd_intrq),

	.img_mounted(img_mounted[1]),
	.img_size(img_size),
	.sd_lba(sd_lba_wd),
	.sd_rd(sd_rd_wd),
	.sd_wr(sd_wr_wd),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din_wd),
	.sd_buff_wr(sd_buff_wr),

	.wp(0),

	.size_code(plusd_en ? 3'd4 : 3'd1),
	.layout(ioctl_index[7:6] == 1),
	.side(fdd_side),
	.ready(fdd_drive1 & fdd_ready),

	.input_active(0),
	.input_addr(0),
	.input_data(0),
	.input_wr(0),
	.buff_din(0)
);

u765 #(20'd1800,1) u765
(
	.clk_sys(clk_sys),
	.ce(ce_u765),
	.reset(reset),
	.a0(addr[12]),
	.ready(plus3_fdd_ready),
	.motor(motor_plus3),
	.available(2'b01),
	.fast(1),
	.nRD(~plus3_fdd | nIORQ | ~nM1 | nRD),
	.nWR(~plus3_fdd | nIORQ | ~nM1 | nWR),
	.din(cpu_dout),
	.dout(u765_dout),

	.img_mounted(img_mounted[1]),
	.img_size(img_size),
	.img_wp(0),
	.sd_lba(sd_lba_plus3),
	.sd_rd(sd_rd_plus3),
	.sd_wr(sd_wr_plus3),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din_plus3),
	.sd_buff_wr(sd_buff_wr)
);

///////////////////   TAPE   ///////////////////
wire [24:0] tape_addr = 25'h400000 + tape_addr_raw;
wire [24:0] tape_addr_raw;
wire        tape_req;
wire        tape_dout_en;
wire        tape_turbo;
wire  [7:0] tape_dout;
wire        tape_led;
wire        tape_active;
wire        tape_loaded;
wire        tape_in;
wire        tape_vin;

smart_tape tape
(
	.*,
	.reset(reset & ~Fn[10]),
	.ce(ce_tape),

	.turbo(tape_turbo),
	.mode48k(page_disable),
	.pause(Fn[1]),
	.prev(Fn[2]),
	.next(Fn[3]),
	.audio_out(tape_vin),
	.led(tape_led),
	.active(tape_active),
	.available(tape_loaded),
	.req_hdr((reg_DE == 'h11) & !reg_A),

	.buff_rd_en(~nRFSH),
	.buff_rd(tape_req),
	.buff_addr(tape_addr_raw),
	.buff_din(ram_dout),

	.ioctl_download(ioctl_download & (ioctl_index[4:0] == 2)),
	.tape_size(ioctl_addr - 25'h400000 + 1'b1),
	.tape_mode(ioctl_index[7:6]),

	.m1(~nM1 & ~nMREQ),
	.rom_en(active_48_rom),
	.dout_en(tape_dout_en),
	.dout(tape_dout)
);

reg tape_loaded_reg = 0;
always @(posedge clk_sys) begin
	int timeout = 0;
	
	if(tape_loaded) begin
		tape_loaded_reg <= 1;
		timeout <= 100000000;
	end else begin
		if(timeout) begin
			timeout <= timeout - 1;
		end else begin
			tape_loaded_reg <= 0;
		end
	end
end

assign UART_TX = 1;
assign tape_in = tape_loaded_reg ? tape_vin : ~UART_RX;


endmodule
