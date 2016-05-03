// divmmc

//
// Total refactoring. Made module synchroneous. (Sorgelig)
//


module divmmc
(
	input         clk_sys,

	// CPU interface
	input         nWR,
	input         nRD,
	input         nMREQ,
	input         nIORQ,
	input         nM1,
	input  [15:0] addr,
	input   [7:0] din,
	output  [7:0] dout,

	// control
	input         enable,
	output        active,
	output        active_io,
	output [18:0] mapped_addr,

	// SD/MMC SPI
	output reg    spi_ss,
	output        spi_clk,
   input         spi_di,
   output        spi_do,

	// SD card access ssignal for LED
	output        sd_activity
);

assign    mapped_addr = {((addr[13]) ? {2'b01, sram_page} : 6'b000000), addr[12:0]};
assign    active      = memactive | conmem;
assign    active_io   = active & (addr[7:0] == 8'hEB);
assign    sd_activity = ~spi_ss;

reg [3:0] sram_page;
reg       conmem;
reg       memactive;

wire      io_we = ~nIORQ & ~nWR & nM1;
wire      io_rd = ~nIORQ & ~nRD & nM1;
wire      m1    = ~nMREQ & ~nM1;

reg       tx_strobe;
reg       rx_strobe;

always @(posedge clk_sys) begin
	reg old_we, old_rd, old_m1;
	reg m1_trigger;

	rx_strobe <= 0;
	tx_strobe <= 0;

	if(enable) begin

		old_we <= io_we;
		old_rd <= io_rd;

		if(active) begin
			if(io_we & ~old_we) begin
				case(addr[7:0])
					'hE3: {conmem, sram_page} <= {din[7], din[3:0]}; // divmmc memctl
					'hE7: spi_ss <= din[0];                          // SPI enable
					'hEB: tx_strobe <= 1'b1;                         // SPI write
					default:;
				endcase
			end

			// SPI read
			if(io_rd & ~old_rd & (addr[7:0] == 8'hEB)) rx_strobe <= 1;
		end

		old_m1 <= m1;
		if(m1 & ~old_m1) begin
			casex(addr)
				16'h0000, 16'h0008, 16'h0038, 16'h0066, 16'h04C6, 16'h0562: 
					m1_trigger <= 1;                  // activate automapper after this cycle
				16'h3DXX: 
					{memactive, m1_trigger} <= 2'b11; // activate automapper immediately
				16'b0001111111111XXX:                // 1FF8...1FFF
					m1_trigger <= 0;                  // deactivate automapper after this cycle
				default: ;
			endcase
		end
		if(~m1) memactive <= m1_trigger;

	end else begin
		m1_trigger <= 0;
		memactive  <= 0;
		conmem     <= 0;
		sram_page  <= 0;
		spi_ss     <= 1;
	end
end

spi spi
(
   .clk_sys(clk_sys),
   .tx(tx_strobe),
   .rx(rx_strobe),
   .din(din),
   .dout(dout),

   .spi_clk(spi_clk),
   .spi_di(spi_di),
   .spi_do(spi_do)
);

endmodule

module spi
(
	input        clk_sys,

	input        tx,        // Byte ready to be transmitted
	input        rx,        // request to read one byte
	input  [7:0] din,
	output [7:0] dout,

	output       spi_clk,
	input        spi_di,
	output       spi_do
);

assign    spi_clk = counter[0];
assign    spi_do  = io_byte[7]; // data is shifted up during transfer
assign    dout    = data;

reg [4:0] counter = 5'b10000;  // tx/rx counter is idle
reg [7:0] io_byte, data;

always @(negedge clk_sys) begin
	if(counter[4]) begin
		if(rx | tx) begin
			counter <= 0;
			data <= io_byte;
			io_byte <= tx ? din : 8'hff;
		end
	end else begin
		if(spi_clk) io_byte <= { io_byte[6:0], spi_di };
		counter <= counter + 2'd1;
	end
end

endmodule
