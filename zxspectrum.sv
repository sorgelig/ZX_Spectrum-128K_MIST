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
	"S,TRDIMGDSKMGT,Load Disk;",
	"F,TAPCSW,Load Tape;",
	"O6,Fast tape load,On,Off;",
	"O89,Video timings,ULA-48,ULA-128,Pentagon;",
	"OFG,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%;",
	"OAC,Memory,Standard 128K,Pentagon 512K,Profi 1024K,Standard 48K;",
	"ODE,Features,ULA+ & Timex,ULA+,Timex,None;",
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
reg  ce_28m;

reg  pause;
reg  cpu_en = 1;
reg  ce_cpu_tp;
reg  ce_cpu_tn;

wire ce_cpu_p = cpu_en & cpu_p;
wire ce_cpu_n = cpu_en & cpu_n;
wire ce_cpu   = cpu_en & ce_cpu_tp;

wire cpu_p = ~&turbo ? ce_cpu_tp : ce_cpu_sp;
wire cpu_n = ~&turbo ? ce_cpu_tn : ce_cpu_sn;

always @(negedge clk_sys) begin
	reg [5:0] counter = 0;

	counter <=  counter + 1'd1;

	ce_28m  <= !counter[1:0];
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
		if(~old_Fn[4] & Fn[4]) turbo_key <= 5'b11111;
		if(~old_Fn[5] & Fn[5]) turbo_key <= 5'b01111;
		if(~old_Fn[6] & Fn[6]) turbo_key <= 5'b00111;
		if(~old_Fn[7] & Fn[7]) turbo_key <= 5'b00011;
		if(~old_Fn[8] & Fn[8]) turbo_key <= 5'b00001;
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
		end else if(!turbo[4:2] & !ram_ready) begin // SDRAM wait for 28MHz/56MHz turbo
			cpu_en  <= 0;
		end else if(!turbo[4:3] & !ram_ready & tape_active) begin // SDRAM wait for TAPE load on 14MHz
			cpu_en  <= 0;
		end else if(cpu_en & pause) begin
			cpu_en  <= 0;
		end
	end
end


//////////////////   MIST ARM I/O   ///////////////////
wire        ps2_kbd_clk;
wire        ps2_kbd_data;
wire        ps2_mouse_clk;
wire        ps2_mouse_data;

wire  [7:0] joystick_0;
wire  [7:0] joystick_1;
wire  [1:0] buttons;
wire  [1:0] switches;
wire        scandoubler_disable;
wire        ypbpr;
wire [31:0] status;

wire [31:0] sd_lba;
wire        sd_rd;
wire        sd_wr;
wire        sd_ack;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din;
wire        sd_buff_wr;
wire        img_mounted;
wire [31:0] img_size;

wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire        ioctl_download;
wire  [7:0] ioctl_index;

mist_io #(.STRLEN(($size(CONF_STR)>>3)+5)) mist_io
(
	.*,
	.conf_str({CONF_STR, plusd_en ? CONF_PLUSD : CONF_BDI}),
	.sd_conf(0),
	.sd_sdhc(1),
	.sd_ack_conf(),

	// unused
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
wire        reset  = buttons[1] | status[0] | cold_reset | warm_reset | shdw_reset;

wire        cold_reset =((mod[2:1] == 1) & Fn[11]) | init_reset;
wire        warm_reset = (mod[2:1] == 2) & Fn[11];
wire        shdw_reset = (mod[2:1] == 3) & Fn[11];

wire        io_wr = ~nIORQ & ~nWR & nM1;
wire        io_rd = ~nIORQ & ~nRD & nM1;
wire        m1    = ~nM1 & ~nMREQ;

wire[207:0]	cpu_reg;  // IY, HL', DE', BC', IX, HL, DE, BC, PC, SP, R, I, F', A', F, A
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
	casex({nMREQ, tape_dout_en, ~nM1 | nIORQ | nRD, fdd_sel | fdd_sel2, addr[5:0]==8'h1F, portBF, addr[0], psg_enable, ulap_sel})
		'b00XXXXXXX: cpu_din = ram_dout;
		'b01XXXXXXX: cpu_din = tape_dout;
		'b1X01XXXXX: cpu_din = fdd_dout;
		'b1X001XXXX: cpu_din = mouse_sel ? mouse_data : {2'b00, joystick_0[5:0]};
		'b1X0001XXX: cpu_din = {page_scr_copy, 7'b1111111};
		'b1X000011X: cpu_din = (addr[14] ? sound_data : 8'hFF);
		'b1X0000101: cpu_din = ulap_dout;
		'b1X0000100: cpu_din = port_ff;
		'b1X00000XX: cpu_din = {1'b1, ~tape_in, 1'b1, key_data[4:0] & ({5{addr[12]}} | ~{joystick_1[1:0], joystick_1[2], joystick_1[3], joystick_1[4]})};
		'b1X1XXXXXX: cpu_din = 8'hFF;
	endcase
end

reg init_reset = 1;
always @(posedge clk_sys) begin
	reg old_download;
	old_download <= ioctl_download;
	if(old_download & ~ioctl_download) init_reset <= 0;
end

reg NMI;
always @(posedge clk_sys) begin
	reg old_F11;

	old_F11 <= Fn[11];

	if(reset | ~Fn[11] | (m1 & (addr == 'h66))) NMI <= 0;
	else if(~old_F11 & Fn[11] & (mod[2:1] == 0)) NMI <= 1;
end


//////////////////   MEMORY   //////////////////
wire        dma = (reset | ~nBUSACK) & ~nBUSRQ;
reg  [24:0] ram_addr;
reg   [7:0] ram_din;
reg         ram_we;
reg         ram_rd;
wire  [7:0] ram_dout;
wire        ram_ready;

always_comb begin
	casex({dma, tape_req, plusd_mem, mf128_mem, addr[15:14]})
		'b1XXX_XX: ram_addr = ioctl_addr;
		'b01XX_XX: ram_addr = tape_addr;
		'b001X_00: ram_addr = {5'h18, 2'b00,    addr[13:0]};
		'b0001_00: ram_addr = {5'h18, 2'b01,    addr[13:0]};
		'b0000_00: ram_addr = {5'h17, page_rom, addr[13:0]};
		'b00XX_01: ram_addr = {       3'd5,     addr[13:0]};
		'b00XX_10: ram_addr = {       3'd2,     addr[13:0]};
		'b00XX_11: ram_addr = {       page_ram, addr[13:0]};
	endcase

	casex({dma, tape_req})
		'b1X: ram_din = ioctl_dout;
		'b01: ram_din = 0;
		'b00: ram_din = cpu_dout;
	endcase

	casex({dma, tape_req})
		'b1X: ram_rd = 0;
		'b01: ram_rd = ~nMREQ;
		'b00: ram_rd = ~nMREQ & ~nRD;
	endcase

	casex({dma, tape_req})
		'b1X: ram_we = ioctl_wr;
		'b01: ram_we = 0;
		'b00: ram_we = (addr[15] | addr[14] | ((plusd_mem | mf128_mem) & addr[13])) & ~nMREQ & ~nWR;
	endcase
end

sram ram
(
	.*,
	.init(~locked),
	.clk(clk_sys),
	.dout(ram_dout),
	.din (ram_din),
	.addr(ram_addr),
	.wtbt(0),
	.we(ram_we),
	.rd(ram_rd),
	.ready(ram_ready)
);

wire vram_we = (ram_addr[24:16] == 1) & ram_addr[14];
vram vram
(
    .clock(clk_sys),

    .wraddress({ram_addr[15], ram_addr[13:0]}),
    .data(ram_din),
    .wren(ram_we & vram_we),

    .rdaddress(vram_addr),
    .q(vram_dout)
);

reg        zx48;
reg        p512;
reg        pf1024;
reg        page_scr_copy;
reg        shadow_rom;
reg  [7:0] page_reg;
wire       page_disable = zx48 | page_reg[5];
wire       page_scr     = page_reg[3];
wire [5:0] page_ram     = {page_128k, page_reg[2:0]};
wire       page_write   = ~addr[15] & ~addr[1] & ~page_disable;
reg  [2:0] page_128k;

reg  [1:0] page_rom;
always_comb begin
	casex({shadow_rom, trdos_en, zx48 | page_reg[4]})
		'b1XX: page_rom <= 0;
		'b01X: page_rom <= 1;
		'b000: page_rom <= 2;
		'b001: page_rom <= 3;
	endcase
end

always @(posedge clk_sys) begin
	reg old_wr, old_m1;
	old_wr <= io_wr;
	old_m1 <= m1;

	if(reset) begin
		page_scr_copy <= 0;
		page_reg   <= 0;
		page_128k  <= 0;
		shadow_rom <= shdw_reset & ~plusd_en;
		p512  <= (status[12:10] == 1);
		pf1024<= (status[12:10] == 2);
		zx48  <= (status[12:10] == 3);
	end else begin
		if(m1 && ~old_m1 && addr[15:14]) shadow_rom <= 0;
		if(m1 && ~old_m1 && ~plusd_en && ~mod[0] && (addr == 'h66)) shadow_rom <= 1;

		if(io_wr & ~old_wr) begin
			if(page_write) begin
				page_reg  <= cpu_dout;
				if(p512)  page_128k[1:0] <= cpu_dout[7:6];
				if(~plusd_mem) page_scr_copy <= page_reg[3];
			end
			if(pf1024 & (addr == 'hDFFD)) page_128k <= cpu_dout[2:0];
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

ym2149 ym2149
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

sigma_delta_dac #(9) dac_l
(
	.CLK(clk_sys),
	.RESET(reset),
	.DACin({1'b0, psg_ch_a, 1'b0} + {2'b00, psg_ch_b} + {2'b00, ear_out, mic_out, tape_in, 5'b00000}),
	.DACout(AUDIO_L)
);

sigma_delta_dac #(9) dac_r
(
	.CLK(clk_sys),
	.RESET(reset),
	.DACin({1'b0, psg_ch_c, 1'b0} + {2'b00, psg_ch_b} + {2'b00, ear_out, mic_out, tape_in, 5'b00000}),
	.DACout(AUDIO_R)
);


////////////////////   VIDEO   ///////////////////
wire        ce_cpu_sn;
wire        ce_cpu_sp;
wire [14:0] vram_addr;
wire  [7:0] vram_dout;
wire  [7:0] port_ff;
wire        ulap_sel;
wire  [7:0] ulap_dout;
wire  [1:0] ulap_tmx_ena = {~status[13], ~status[14]} & {~trdos_en, ~trdos_en};

reg mZX, m128;
always_comb begin
	case(status[9:8])
		      0: {mZX, m128} <= 2'b10;
		      1: {mZX, m128} <= 2'b11;
		default: {mZX, m128} <= 2'b00;
	endcase
end

video video(.*, .din(cpu_dout), .page_ram(page_ram[2:0]), .scale(status[16:15]));


////////////////////   HID   ////////////////////
wire [11:1] Fn;
wire  [2:0] mod;
wire  [4:0] key_data;
keyboard kbd( .* );

reg         mouse_sel;
wire  [7:0] mouse_data;
mouse mouse( .*, .reset(cold_reset), .addr(addr[10:8]), .sel(), .dout(mouse_data));

always @(posedge clk_sys) begin
	if(joystick_0[5:0]) mouse_sel <= 0;
	if(~ps2_mouse_clk) mouse_sel <= 1;
end


//////////////////   MF128   ///////////////////
reg         mf128_mem;
reg         mf128_en; // enable MF128 page-in from NMI till reset

always @(posedge clk_sys) begin
	reg old_m1, old_rd;

	old_rd <= io_rd;
	if(reset) {mf128_mem, mf128_en} <= 0;
	else if(~old_rd & io_rd) begin
		if((addr[7:0] == 'hBF) & mf128_en) mf128_mem <= 1;
		if(addr[7:0] == 'h3F) mf128_mem <= 0;
	end

	old_m1 <= m1;
	if(~old_m1 & m1 & mod[0] & (addr == 'h66)) {mf128_mem, mf128_en} <= 2'b11;
end


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
wire  [7:0] fdd_dout = (addr[7] & ~plusd_en) ? {fdd_intrq, fdd_drq, 6'h3F} : wd_dout;

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
wire        portBF = (addr[7:0] == 'hBF) & (mf128_mem | plusd_mem);

always @(posedge clk_sys) begin
	reg old_wr, old_rd;
	reg old_mounted;
	reg old_m1;

	if(cold_reset) {fdd_ready, plusd_en} <= 0;
	if(reset)      {plusd_mem, trdos_en} <= 0;

	old_mounted <= img_mounted;
	if(~old_mounted & img_mounted) begin
		fdd_ready <= 1;
		plusd_en  <= |ioctl_index[7:6];
	end

	old_rd <= io_rd;
	old_wr <= io_wr;
	old_m1 <= m1;
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
				else if((addr[13:8] == 'h3D) & page_rom[0]) trdos_en <= 1;
				//else if(~mod[0] & (addr == 'h66)) trdos_en <= 1;
		end
	end
end

wd1793 #(1) fdd
(
	.clk_sys(clk_sys),
	.ce(ce_cpu),
	.reset((fdd_reset & ~plusd_en) | reset),
	.io_en((fdd_sel2 | (fdd_sel & ~addr[7])) & ~nIORQ & nM1),
	.rd(~nRD),
	.wr(~nWR),
	.addr(plusd_en ? addr[4:3] : addr[6:5]),
	.din(cpu_dout),
	.dout(wd_dout),
	.drq(fdd_drq),
	.intrq(fdd_intrq),

	.img_mounted(img_mounted),
	.img_size(img_size),
	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
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


///////////////////   TAPE   ///////////////////
wire [24:0] tape_addr = 25'h400000 + tape_addr_raw;
wire [24:0] tape_addr_raw;
wire        tape_req;
wire        tape_dout_en;
wire  [7:0] tape_dout;
wire        tape_led;
wire        tape_active;
wire        tape_loaded;
wire        tape_in;
wire        tape_vin;

smart_tape tape
(
	.*,
	.ce(ce_cpu),

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
	.tape_mode(!ioctl_index[7:6]),

	.m1(~nM1 & ~nMREQ),
	.rom_en(&page_rom),
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
