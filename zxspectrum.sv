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

assign LED = ~(divmmc_sd_activity | ioctl_erasing | ioctl_download | fdd_read | tape_led);


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

reg  cpu_en;
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
	ce_psg  <= !counter[5:0];

	ce_cpu_tp <= !(counter & turbo);
	ce_cpu_tn <= !((counter & turbo) ^ turbo ^ turbo[4:1]);
end

reg [4:0] turbo, turbo_key = 5'b11111;
always @(posedge clk_sys) begin
	reg [8:4] old_Fn;
	old_Fn <= Fn[8:4];

	if(!mod) begin
		if(~old_Fn[4] & Fn[4]) turbo_key <= 5'b11111;
		if(~old_Fn[5] & Fn[5]) turbo_key <= 5'b01111;
		if(~old_Fn[6] & Fn[6]) turbo_key <= 5'b00111;
		if(~old_Fn[7] & Fn[7]) turbo_key <= 5'b00011;
		if(~old_Fn[8] & Fn[8]) turbo_key <= 5'b00001;
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
		end else if(!cpu_en && !timeout && ram_ready) begin
			cpu_en  <= 1;
		end else if(!turbo[4:2] & !ram_ready) begin // for >14MHz turbo
			cpu_en  <= 0;
		end
	end
end


//////////////////   MIST ARM I/O   ///////////////////
wire        ps2_kbd_clk;
wire        ps2_kbd_data;

wire  [7:0] joystick_0;
wire  [7:0] joystick_1;
wire  [1:0] buttons;
wire  [1:0] switches;
wire        scandoubler_disable;
wire  [7:0] status;

wire [31:0] sd_lba;
wire        sd_rd;
wire        sd_wr;
wire        sd_ack;
wire        sd_ack_conf;
wire        sd_conf;
wire        sd_sdhc;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din;
wire        sd_buff_wr;
wire        sd_mounted;

wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire        ioctl_download;
wire        ioctl_erasing;
wire  [4:0] ioctl_index;
reg         ioctl_force_erase = 0;

mist_io #(.STRLEN(130)) user_io
(
	.*,
	.conf_str
	(
        "SPECTRUM;TRD;F1,TAP;F2,CSW;O6,Fast tape load,On,Off;O4,Video type,ZX,Pent;O5,Video version,48k,128k;O7,ULA+ & Timex,Enable,Disable"
	),

	// unused
	.joystick_analog_0(),
	.joystick_analog_1(),
	.ps2_mouse_clk(),
	.ps2_mouse_data(),
	.sd_mounted()
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
wire        nBUSRQ = ~(ioctl_download | ioctl_erasing);
wire        reset  = buttons[1] | status[0] | esxRESET | cold_reset | warm_reset | test_reset;
wire        cold_reset = (mod[1] & Fn[11]) | (ioctl_download & !ioctl_index);
wire        warm_reset =  mod[2] & Fn[11];
wire        test_reset =  mod[0] & Fn[11];

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
	.NMI_n(~esxNMI),
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
	casex({nMREQ, tape_dout_en, ~nM1 | nIORQ | nRD, fdd_sel, divmmc_sel, addr[7:0]==8'h1F, addr[0], psg_enable, ulap_sel})
		'b00XXXXXXX: cpu_din = ram_dout;
		'b01XXXXXXX: cpu_din = tape_dout;
		'b1X01XXXXX: cpu_din = fdd_dout;
		'b1X001XXXX: cpu_din = divmmc_dout;
		'b1X0001XXX: cpu_din = {2'b00, joystick_0[5:0] | joystick_1[5:0]};
		'b1X000011X: cpu_din = (addr[14] ? sound_data : 8'hFF);
		'b1X0000101: cpu_din = ulap_dout;
		'b1X0000100: cpu_din = port_ff;
		'b1X00000XX: cpu_din = {1'b1, tape_in, 1'b1, key_data[4:0]};
		'b1X1XXXXXX: cpu_din = 8'hFF;
	endcase
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
	casex({dma, tape_req, fdd_read, ext_ram, addr[15:14]})
		'b1XXX_XX: ram_addr = ioctl_addr;
		'b01XX_XX: ram_addr = tape_addr;
		'b001X_XX: ram_addr = {2'd2, fdd_addr};
		'b0001_00: ram_addr = divmmc_addr;
		'b0000_00: ram_addr = {5'h17, page_rom, addr[13:0]};
		'b000X_01: ram_addr = {       3'd5,     addr[13:0]};
		'b000X_10: ram_addr = {       3'd2,     addr[13:0]};
		'b000X_11: ram_addr = {       page_ram, addr[13:0]};
	endcase

	casex({dma, tape_req})
		'b1X: ram_din = ioctl_dout;
		'b01: ram_din = 0;
		'b00: ram_din = cpu_dout;
	endcase

	casex({dma, tape_req})
		'b1X: ram_rd = 0;
		'b01: ram_rd = ~nMREQ;
		'b00: ram_rd = (fdd_read | ~nMREQ) & ~nRD;
	endcase

	casex({dma, tape_req})
		'b1X: ram_we = ioctl_wr;
		'b01: ram_we = 0;
		'b00: ram_we = (ext_ram_write | addr[15] | addr[14]) & ~nMREQ & ~nWR;
	endcase
end

sram ram
(
	.*,
	.init(~locked),
	.clk_sdram(clk_sys),
	.dout(ram_dout),
	.din (ram_din),
	.addr(ram_addr),
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

reg        test_rom;
reg  [7:0] page_reg;
wire       page_disable = page_reg[5];
wire [1:0] page_rom     = {~trdos_en & ~test_rom, page_reg[4] & ~test_rom};
wire       page_scr     = page_reg[3];
wire [2:0] page_ram     = page_reg[2:0];
wire       page_write   = ~nIORQ & ~nWR & nM1 & ~addr[15] & ~addr[1] & ~page_disable;

always @(posedge clk_sys) begin
	reg old_wr;
	old_wr <= page_write;

	if(reset) begin
		page_reg <= 0;
		test_rom <= test_reset;
	end else begin
		if(page_write & ~old_wr) page_reg <= cpu_dout;
	end
end


////////////////////  ULA PORT  ///////////////////
reg [2:0] border_color;
reg       ear_out;
reg       mic_out;

wire ula_we = ~addr[0] & ~(trdos_en | tape_turbo | nIORQ) & ~nWR & nM1;
always @(posedge clk_sys) begin
	reg old_we;
	old_we <= ula_we;

	if(ula_we & ~old_we) begin
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

ym2149 ym2149
(
	.CLK(clk_sys),
	.CE(ce_psg),
	.RESET(reset),
	.BDIR(psg_we),
	.BC(addr[14]),
	.DI(cpu_dout),
	.DO(sound_data),
	.CHANNEL_A(psg_ch_a),
	.CHANNEL_B(psg_ch_b),
	.CHANNEL_C(psg_ch_c),
	.SEL(0),
	.MODE(0)
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
wire        ulap_tmx_ena = ~(trdos_en | status[7]);
video video(.*, .din(cpu_dout), .mZX(~status[4]), .m128(status[5]));

//////////////////   KEYBOARD   //////////////////
wire [11:1] Fn;
wire  [2:0] mod;
wire  [4:0] key_data;
keyboard kbd( .* );


//////////////////   DIVMMC   //////////////////
reg   [1:0] esxdos_downloaded = 2'b00;
wire        esxdos_ready = esxdos_downloaded[~status[3]];
wire        ext_ram = divmmc_active && esxdos_ready;
wire        ext_ram_write = ext_ram && (addr[15:13] == 3'b001);

wire [24:0] divmmc_addr = {6'b000011, divmmc_mapaddr};
wire        divmmc_sd_activity;
wire        divmmc_active;
wire        divmmc_sel;
wire [18:0] divmmc_mapaddr;
wire  [7:0] divmmc_dout;

wire        spi_ss;
wire        spi_clk;
wire        spi_di;
wire        spi_do;

reg         esxRQ;
wire        esxRESET = esxRQ & ~esxdos_ready & esxdos_downloaded[0];
wire        esxNMI   = esxRQ &  esxdos_ready;
wire        btnESX   = ((Fn[11] && !mod) | joystick_0[7] | joystick_1[7]) & ~fdd_ready & ~test_rom;

always @(posedge clk_sys) begin
	esxRQ <= btnESX;
	if(esxRQ & ~btnESX) esxdos_downloaded[1] <= esxdos_downloaded[0];

	ioctl_force_erase <= cold_reset;
	if(cold_reset) esxdos_downloaded[1] <= 0;

	if(ioctl_download && !ioctl_index && (ioctl_addr == 25'h181FFF)) esxdos_downloaded[0] <= 1;
end

divmmc divmmc
(
	.*,
	.enable(~reset & esxdos_ready),
	.din(cpu_dout),
	.dout(divmmc_dout),
	.active(divmmc_active),
	.active_io(divmmc_sel),
	.mapped_addr(divmmc_mapaddr),

	.sd_activity(divmmc_sd_activity)
);

sd_card sd_card
(
	.*,
	.allow_sdhc(1),
	.spi_di(spi_do),
	.spi_do(spi_di)
);


///////////////////   FDC   ///////////////////
reg         trdos_en;
wire  [7:0] wd_dout;
wire [19:0] fdd_addr;
wire [19:0] fdd_size;
wire        fdd_rd;
reg         fdd_ready;
reg   [1:0] fdd_drive;
reg         fdd_side;
reg         fdd_reset;
wire        fdd_intrq;
wire        fdd_drq;
wire        fdd_sel  = trdos_en & addr[2] & addr[1] & ~nIORQ & nM1;
wire        fdd_read = fdd_rd & fdd_sel;
wire  [7:0] fdd_dout = addr[7] ? {fdd_intrq, fdd_drq, 6'h3F} : wd_dout;
wire        fdd_m1   = ~nM1 & ~nMREQ;

always @(posedge clk_sys) begin
	reg old_wr;
	reg old_download;
	reg old_m1;

	old_wr <= nWR;
	if(old_wr & ~nWR & fdd_sel & addr[7]) {fdd_side, fdd_reset, fdd_drive} <= {~cpu_dout[4], ~cpu_dout[2], cpu_dout[1:0]};

	old_download <= ioctl_download;
	if(cold_reset) begin
		fdd_ready <= 0;
		fdd_size  <= 0;
	end else begin
		if(!ioctl_download & old_download & (ioctl_index == 1) & ~esxdos_ready) begin
			fdd_ready <= 1;
			fdd_size  <= ioctl_addr[19:0] + 1'b1;
		end
	end

	old_m1 <= fdd_m1;
	if(reset) trdos_en <= 0;
	else begin
		if(fdd_m1 && ~old_m1) begin
			if(addr[15:14]) trdos_en <= 0;
				else if((addr[13:8] == 6'h3D) & page_rom[0] & fdd_ready) trdos_en <= 1;
		end
	end
end

wd1793 fdd
(
	.clk_sys(clk_sys),
	.ce(ce_cpu),
	.reset(fdd_reset),
	.io_en(fdd_sel & ~addr[7]),
	.rd(~nRD),
	.wr(~nWR),
	.addr(addr[6:5]),
	.din(cpu_dout),
	.dout(wd_dout),
	.drq(fdd_drq),
	.intrq(fdd_intrq),

	.buff_size(fdd_size),
	.buff_addr(fdd_addr),
	.buff_read(fdd_rd),
	.buff_din(ram_dout),

	.size_code(1),
	.side(fdd_side),
	.ready(!fdd_drive & fdd_ready)
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
reg         tape_in;

smart_tape tape
(
	.*,
	.ce(ce_cpu),

	.turbo(tape_turbo),
	.pause(Fn[1]),
	.prev(Fn[2]),
	.next(Fn[3]),
	.audio_out(tape_in),
	.led(tape_led),
	.active(tape_active),
	.req_hdr((reg_DE == 'h11) & !reg_A),

	.buff_rd_en(~nRFSH),
	.buff_rd(tape_req),
	.buff_addr(tape_addr_raw),
	.buff_din(ram_dout),

	.ioctl_download(ioctl_download & ((ioctl_index == 2) | (ioctl_index == 3))),
	.tape_size(ioctl_addr - 25'h400000 + 1'b1),
	.tape_mode(ioctl_index == 2),

	.m1(~nM1 & ~nMREQ),
	.rom_en(&page_rom),
	.dout_en(tape_dout_en),
	.dout(tape_dout)
);

endmodule
