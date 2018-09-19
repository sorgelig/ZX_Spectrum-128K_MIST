// divmmc

//
// Total refactoring. Made module synchroneous. (Sorgelig)
//

module divmmc
(
    input         clk_sys,
    input   [1:0] mode,

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
    output        active_io,

	// SD/MMC SPI
    output reg    spi_ss,
    output        spi_clk,
    input         spi_di,
    output        spi_do
);

assign    active_io   = port_io;

wire      io_we = ~nIORQ & ~nWR & nM1;
wire      io_rd = ~nIORQ & ~nRD & nM1;

wire      port_cs = ((mode == 2'b01) && (addr[7:0] == 8'hE7)) ||
                    ((mode == 2'b10) && (addr[7:0] == 8'h1F));
wire      port_io = ((mode == 2'b01) && (addr[7:0] == 8'hEB)) ||
                    ((mode == 2'b10) && (addr[7:0] == 8'h3F));

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

		if(io_we & ~old_we) begin
            if (port_cs) spi_ss <= din[0];                          // SPI enable
            if (port_io) tx_strobe <= 1'b1;                         // SPI write
		end

		// SPI read
		if(io_rd & ~old_rd & port_io) rx_strobe <= 1;

	end else begin
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
