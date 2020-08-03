module ula_test (

	input         reset,
	input         clk_sys,	// master clock
	output        ce_vid,

	// VRAM interfacing
	output [14:0] vram_addr,
	input   [7:0] vram_dout,
	output  [7:0] port_ff,

	// ULA+
	input         ulap_avail,

	// Timex mode
	input         tmx_avail,

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

assign ce_vid = ce_7mp;

reg         ce_7mp, ce_7mn;
reg   [2:0] clk_div;

always @(posedge clk_sys) begin
	clk_div <= clk_div + 1'd1;
	ce_7mp <= clk_div == 0;
	ce_7mn <= clk_div == 4;
end

wire        ce_cpu_sp, ce_cpu_sn;
wire [15:0] cpu_addr;
wire  [7:0] cpu_din;
wire  [7:0] cpu_dout;
wire        nMREQ;
wire        nIORQ;
wire        nRFSH;
wire        nWR;
wire        nINT;

ULA ULA (
	.reset(reset),
	.clk_sys(clk_sys),
	.ce_7mp(ce_7mp),
	.ce_7mn(ce_7mn),
	.ce_cpu_sp(ce_cpu_sp),
	.ce_cpu_sn(ce_cpu_sn),

	.addr(cpu_addr),
	.din(cpu_din),
	.nMREQ(nMREQ),
	.nIORQ(nIORQ),
	.nRFSH(nRFSH),
	.nWR(nWR),
	.nINT(nINT),

	.vram_addr(vram_addr),
	.vram_dout(vram_dout),
	.port_ff(port_ff),

	.ulap_avail(ulap_avail),
	.ulap_sel(),
	.ulap_dout(),
	.ulap_ena(),
	.ulap_mono(),

	.tmx_avail(tmx_avail),
	.mode512(),

	.mZX(mZX),
	.m128(m128),
	.page_scr(page_scr),
	.page_ram(page_ram),
	.border_color(border_color),

	.HSync(HSync),
	.VSync(VSync),
	.HBlank(HBlank),
	.Rx(Rx),
	.Gx(Gx),
	.Bx(Bx)
);

endmodule
