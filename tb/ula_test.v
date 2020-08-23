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
reg         clk_7;
reg   [2:0] clk_div;

always @(posedge clk_sys) begin
	clk_div <= clk_div + 1'd1;
	ce_7mp <= clk_div == 0;
	ce_7mn <= clk_div == 4;

	if (ce_7mp) clk_7 <= 1;
	if (ce_7mn) clk_7 <= 0;
end

wire        out_sel = 0; // 0 - sync, 1 - async model
assign      HSync = out_sel ? HSync_async : HSync_sync;
assign      VSync = out_sel ? VSync_async : VSync_sync;
assign      Rx = out_sel ? Rx_async : Rx_sync;
assign      Gx = out_sel ? Gx_async : Gx_sync;
assign      Bx = out_sel ? Bx_async : Bx_sync;
assign      vram_addr = out_sel ? {1'b0, vram_addr_async} : vram_addr_sync;

wire        ce_cpu_sp, ce_cpu_sn;
wire [15:0] cpu_addr;
wire  [7:0] cpu_din;
wire  [7:0] cpu_dout;
wire        nMREQ;
wire        nIORQ;
wire        nRFSH;
wire        nRD;
wire        nWR;
wire        nINT;


/* verilator lint_off MULTIDRIVEN */
CPU CPU (
	.reset(reset),
	.clk_pos(clk_sys),
	.clk_neg(clk_sys),
	.ce_n(ce_cpu_sn),
	.ce_p(ce_cpu_sp),
	.cpu_addr(cpu_addr),
	.cpu_din(cpu_din),
	.cpu_dout(cpu_dout),
	.nMREQ(nMREQ),
	.nIORQ(nIORQ),
	.nINT(nINT),
	.nRD(nRD),
	.nWR(nWR),
	.nM1(),
	.nRFSH()
);
/* verilator lint_on MULTIDRIVEN */

wire        HSync_sync;
wire        VSync_sync;
wire  [2:0] Rx_sync;
wire  [2:0] Gx_sync;
wire  [2:0] Bx_sync;
wire [14:0] vram_addr_sync;

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
	.nRD(nRD),
	.nWR(nWR),
	.nINT(nINT),
	.nPortRD(),
	.nPortWR(),

	.vram_addr(vram_addr_sync),
	.vram_dout(vram_dout),
	.port_ff(port_ff),

	.ulap_avail(ulap_avail),
	.ulap_sel(),
	.ulap_dout(),
	.ulap_ena(),
	.ulap_mono(),

	.tmx_avail(tmx_avail),
	.mode512(),

	.snow_ena(1'b1),
	.mZX(mZX),
	.m128(m128),
	.page_scr(page_scr),
	.page_ram(page_ram),
	.border_color(border_color),

	.HSync(HSync_sync),
	.VSync(VSync_sync),
	.HBlank(HBlank),
	.Rx(Rx_sync),
	.Gx(Gx_sync),
	.Bx(Bx_sync)
);

/* verilator lint_off MULTIDRIVEN */
/* verilator lint_off UNOPTFLAT */
wire        cpuclk;
wire [15:0] cpu_addr_a;
wire  [7:0] cpu_dout_a;
wire        nMREQ_a, nIORQ_a, nRD_a, nWR_a;

CPU CPU_ASYNC (
	.reset(reset),
	.clk_pos(cpuclk & ~reset),
	.clk_neg(~cpuclk & ~reset),
	.ce_n(1),
	.ce_p(1),
	.cpu_addr(cpu_addr_a),
	.cpu_din(cpu_din),
	.cpu_dout(cpu_dout_a),
	.nMREQ(nMREQ_a),
	.nIORQ(nIORQ_a),
	.nINT(nINT),
	.nRD(nRD_a),
	.nWR(nWR_a),
	.nM1(),
	.nRFSH()
);

wire        HSync_async;
wire        VSync_async;
wire  [2:0] Rx_async;
wire  [2:0] Gx_async;
wire  [2:0] Bx_async;
wire [13:0] vram_addr_async;

/* verilator lint_on UNOPTFLAT */
/* verilator lint_on MULTIDRIVEN */

ULA_ASYNC ULA_ASYNC (
	.reset(reset),
	.clk_7(clk_7),
	.cpuclk(cpuclk),

	.addr(cpu_addr_a),
	.din(cpu_din),
	.nMREQ(nMREQ_a),
	.nIORQ(nIORQ_a),
	.nRD(nRD_a),
	.nWR(nWR_a),
	.nINT(),

	.RAS_N(),
	.CAS_N(),
	.vram_addr(vram_addr_async),
	.vram_dout(vram_dout),
	.port_ff(),

	.mZX(mZX),
	.m128(m128),
	.page_scr(page_scr),
	.page_ram(page_ram),
	.border_color(border_color),

	.HSync(HSync_async),
	.VSync(VSync_async),
	.HBlank(),
	.Rx(Rx_async),
	.Gx(Gx_async),
	.Bx(Bx_async)
);

endmodule
