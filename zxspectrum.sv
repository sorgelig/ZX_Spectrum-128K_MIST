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
   input         SPI_SS4,
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

assign      LED = ~(divmmc_sd_activity | ioctl_erasing | ioctl_download | fdd_read | tape_led);


//////////////////   MIST ARM I/O   ///////////////////
wire        PS2_CLK;
wire        PS2_DAT;

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
wire        sd_conf;
wire        sd_sdhc;
wire  [7:0] sd_dout;
wire        sd_dout_strobe;
wire  [7:0] sd_din;
wire        sd_din_strobe;

reg  [10:0] clk14k_div;
wire        clk_ps2 = clk14k_div[10];
always @(posedge clk_sys) clk14k_div <= clk14k_div + 1'b1;

user_io #(.STRLEN(125)) user_io
(
	.*,
	.conf_str
	(
        "SPECTRUM;TRD;F4,TAP;F1,CSW;O5,Autoload ESXDOS,No,Yes;O2,CPU Speed,3.5MHz,4MHz;O3,Video Type,ZX,Pent;O6,Video Version,48k,128k"
	),

	// ps2 keyboard emulation
	.ps2_clk(clk_ps2),				// 12-16khz provided by core
	.ps2_kbd_clk(PS2_CLK),
	.ps2_kbd_data(PS2_DAT),

	// unused
	.joystick_analog_0(),
	.joystick_analog_1(),
	.ps2_mouse_clk(),
	.ps2_mouse_data(),
	.serial_data(),
	.serial_strobe()
);

wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire        ioctl_download;
wire        ioctl_erasing;
wire  [4:0] ioctl_index;
reg         force_erase = 0;

data_io data_io
(
	.sck(SPI_SCK),
	.ss(SPI_SS2),
	.sdi(SPI_DI),

	.force_erase(force_erase),
	.downloading(ioctl_download),
	.erasing(ioctl_erasing),
	.index(ioctl_index),

	.clk(clk_sys),
	.wr(ioctl_wr),
	.addr(ioctl_addr),
	.dout(ioctl_dout)
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
wire        nHALT;
wire        nBUSACK;
wire        nINT;
wire        nWAIT	 = 1;
wire        nNMI   = esxNMI;
wire        nBUSRQ = ~(ioctl_download | ioctl_erasing);
wire        nRESET = locked & ~buttons[1] & ~status[0] & esxRESET & ~(Fn[11] && mod);

T80a cpu
(
	.RESET_n(nRESET),
	.CLK_n(clk_cpu),
	.WAIT_n(nWAIT),
	.INT_n(nINT),
	.NMI_n(nNMI),
	.BUSRQ_n(nBUSRQ),
	.M1_n(nM1),
	.MREQ_n(nMREQ),
	.IORQ_n(nIORQ),
	.RD_n(nRD),
	.WR_n(nWR),
	.RFSH_n(nRFSH),
	.HALT_n(nHALT),
	.BUSAK_n(nBUSACK),
	.A(addr),
	.DO(cpu_dout),
	.DI(cpu_din),
	.RestorePC_n(1),
	.RestorePC(0),
	.RestoreINT(0)
);

always_comb begin
	casex({nMREQ, tape_dout_en, ~nM1 | nIORQ | nRD, fdd_sel, divmmc_sel, addr[7:0]==8'h1F})
		'b00XXXX: cpu_din = ram_dout;
		'b01XXXX: cpu_din = tape_dout;
		'b1X01XX: cpu_din = fdd_dout;
		'b1X001X: cpu_din = divmmc_dout;
		'b1X0001: cpu_din = {2'b00, joystick_0[5:0] | joystick_1[5:0]};
		'b1X0000: cpu_din = ula_dout;
		'b1X1XXX: cpu_din = 8'hFF;
	endcase
end


//////////////////   MEMORY   //////////////////
wire        dma = (~nRESET | ~nBUSACK) & ~nBUSRQ;
reg  [24:0] ram_addr;
reg   [7:0] ram_din;
reg         ram_we;
reg         ram_rd;
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
		'b1X: ram_we = ioctl_wr;
		'b01: ram_we = 0;
		'b00: ram_we = (ext_ram_write | addr[15] | addr[14]) & ~nMREQ & ~nWR;
	endcase

	casex({dma, tape_req})
		'b1X: ram_rd = 0;
		'b01: ram_rd = tape_rd;
		'b00: ram_rd = (fdd_read | ~nMREQ) & ~nRD;
	endcase
end

wire  [7:0] ram_dout;
sram ram
(
	.*,
	.init(~locked),
	.clk_sdram(clk_ram),
	.dout(ram_dout),
	.din (ram_din),
	.addr(ram_addr),
	.we(ram_we),
	.rd(ram_rd)
);

wire vram_we = (ram_addr[24:16] == 1) & ram_addr[14] & ~ram_addr[13];
vram vram
(
    .clock(clk_sys),

    .wraddress({ram_addr[15], ram_addr[12:0]}),
    .data(ram_din),
    .wren(ram_we & vram_we),

    .rdaddress({page_scr, vram_addr}),
    .q(vram_dout)
);

reg         test_rom;
reg   [7:0] page_reg     = 0;
wire        page_disable = page_reg[5];
wire  [1:0] page_rom     = {~trdos_en & ~test_rom, page_reg[4] & ~test_rom};
wire        page_scr     = page_reg[3];
wire  [2:0] page_ram     = page_reg[2:0];
wire        page_write   = ~nIORQ & ~nWR & nM1 & ~addr[15] & ~addr[1] & ~page_disable;

always @ (negedge clk_cpu) begin
	if(~nRESET) begin
		page_reg <= 0;
		test_rom <= test_reset;
	end else if(page_write) begin
		page_reg <= cpu_dout;
	end
end


///////////////////   ULA   ///////////////////
wire        locked;
wire        clk_cpu;       // CPU clock of 3.5 MHz
wire        clk_ram;       // 84MHz clock for RAM 
wire        clk_sys;       // 28MHz for system synchronization 
wire        clk_ula;       // 14MHz
wire [12:0] vram_addr;
wire  [7:0] vram_dout;
wire  [7:0] ula_dout;
wire [11:1] Fn;
wire  [2:0] mod;
wire        cold_reset = mod[1] & Fn[11];
wire        test_reset = mod[0] & Fn[11];
reg         AUDIO_IN;

ula ula( .*, .nIORQ(trdos_en | tape_turbo | nIORQ), .din(cpu_dout), .dout(ula_dout), .turbo(status[2]), .mZX(~status[3]), .m128(status[6]));


//////////////////   DIVMMC   //////////////////
reg   [1:0] esxdos_downloaded = 1'b00;
wire        esxdos_ready = esxdos_downloaded[~status[5]];
wire        ext_ram = divmmc_active && esxdos_ready;
wire        ext_ram_write = ext_ram && (addr[15:13] == 3'b001);
wire [24:0] divmmc_addr = {6'b000011, divmmc_mapaddr};

wire        esxRESET = ~(esxRQ & ~esxdos_ready & esxdos_downloaded[0]) & !initRESET;
wire        esxNMI   = ~(esxRQ &  esxdos_ready);
reg         esxRQ    = 0;

always @(posedge clk_ps2) begin
	reg sRST1 = 0, sRST2 = 0;

	sRST1 <= (Fn[11] && !mod) | joystick_0[7] | joystick_1[7];
	sRST2 <= sRST1;

	if(sRST2 & ~sRST1 & ~fdd_ready) esxRQ <= 1;
		else esxRQ <= 0;
end

// wait for ESXDOS ROM loading 
integer initRESET = 32000000;
always @(posedge clk_sys) if(initRESET) initRESET <= initRESET - 1;

always @(negedge esxRQ, posedge cold_reset) begin
	if(cold_reset) esxdos_downloaded[1] <= 0;
		else esxdos_downloaded[1] <= esxdos_downloaded[0];
end

wire        divmmc_sd_activity;
wire        divmmc_active;
wire        divmmc_sel;
wire [18:0] divmmc_mapaddr;
wire  [7:0] divmmc_dout;

divmmc divmmc
(
	.*,
	.clk(clk_sys),

	.enabled(esxdos_ready),
	.din(cpu_dout),
	.dout(divmmc_dout),

	.active(divmmc_active),
	.active_io(divmmc_sel),
	.mapped_addr(divmmc_mapaddr),

	.sd_activity(divmmc_sd_activity)
);

always @(posedge ioctl_wr) if(ioctl_addr == 25'h181fff) esxdos_downloaded[0] <= 1;
always @(posedge clk_sys) force_erase <= cold_reset;


///////////////////   FDC   ///////////////////
reg         trdos_en = 0;
wire  [7:0] wd_dout;
wire [19:0] fdd_addr;
wire [19:0] fdd_size;
wire        fdd_rd;
reg         fdd_ready = 0;
reg   [1:0] fdd_drive;
reg         fdd_side;
reg         fdd_reset;
wire        fdd_intrq;
wire        fdd_drq;
wire        fdd_sel  = trdos_en & addr[2] & addr[1] & ~nIORQ & nM1;
wire        fdd_read = fdd_rd & fdd_sel;
wire  [7:0] fdd_dout = addr[7] ? {fdd_intrq, fdd_drq, 6'h3F} : wd_dout;

wd1793 fdd
(
	.clk(clk_cpu),
	.reset(~fdd_reset),
	.ce(fdd_sel & ~addr[7]),
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

always @(negedge ioctl_download, posedge cold_reset) begin
	if(cold_reset) begin
		fdd_ready <= 0;
		fdd_size  <= 0;
	end else begin
		if((ioctl_index == 1) & ~esxdos_ready) begin
			fdd_ready <= 1;
			fdd_size  <= ioctl_addr[19:0];
		end
	end
end

wire m_pos = ~nM1 & ~nMREQ;
always @(posedge m_pos, negedge nRESET) begin
	if(!nRESET) begin
		trdos_en  <= 0;
	end else begin
		if(addr[15:14]) trdos_en <= 0;
			else if((addr[13:8] == 6'h3D) & page_rom[0] & fdd_ready) trdos_en <= 1;
	end
end

always @(negedge nWR) if(fdd_sel & addr[7]) {fdd_side, fdd_reset, fdd_drive} <= {~cpu_dout[4], cpu_dout[2], cpu_dout[1:0]};


///////////////////   TAPE   ///////////////////
wire [24:0] tape_addr = 25'h400000 + tape_addr_raw;
wire        tape_rd;
wire        tape_req;
wire        tape_dout_en;
wire        tape_turbo;
wire  [7:0] tape_dout;
wire        tape_led;

wire [24:0] tape_addr_raw;
smart_tape tape
(
	.reset(~nRESET),
	.clk(clk_sys),

	.turbo(tape_turbo),
	.pause(Fn[1]),
	.audio_out(AUDIO_IN),
	.activity(tape_led),

	.rd_en(~nRFSH),
	.rd_req(tape_req),
	.rd(tape_rd),
	.addr(tape_addr_raw),
	.din(ram_dout),

	.dout_en(tape_dout_en),
	.dout(tape_dout),

	.ioctl_download(ioctl_download & ((ioctl_index == 2) | (ioctl_index == 3))),
	.ioctl_size(ioctl_addr - 25'h400000),
	.tap_mode(ioctl_index == 2),

	.cpu_addr(addr),
	.cpu_m1(~nM1 & ~nMREQ),
	.rom_en(&page_rom)
);

endmodule
