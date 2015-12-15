// divmmc

module divmmc (
	input        	clk,
	input        	nRESET,

	// Bus interface
	input          enabled,
	input  [15:0] 	A,
	input          nWR,
	input          nRD,
	input          nMREQ,
	input          nIORQ,
	input          nM1,
	input  [7:0]  	din,
	output [7:0]  	dout,
	
	// memory state
	output         active,
	output [18:0]  mapped_addr,
	
	output [31:0]  sd_lba,
	output         sd_rd,
	output         sd_wr,
	input			   sd_ack,
	output		   sd_conf,
	output		   sd_sdhc,
	
	output [7:0]	sd_din,
	input 		   sd_din_strobe,
	input  [7:0]   sd_dout,
	input 		   sd_dout_strobe,
	
	output         sd_activity,

	output         access,
	output         sd_transmit
);

reg [3:0] sram_page = 4'd0;
//reg       mapram = 1'b0;
reg       conmem = 1'b0;

reg reg_access;
assign access = reg_access;

wire io_we = !nIORQ &&  nRD && !nWR &&  nM1;
wire io_rd = !nIORQ && !nRD &&  nWR &&  nM1;
wire op_rd = !nMREQ && !nRD &&  nWR && !nM1;

assign mapped_addr = {((A[13]) ? {2'b01, sram_page} : 6'b000000), A[12:0]};

reg m1_trigger;
reg memactive = 1'b0;
assign active = (memactive || conmem);
assign sd_activity = sd_cs;

always @(posedge clk) begin

	if(!nRESET || !enabled) begin

		m1_trigger <= 1'b0;
		memactive <= 1'b0;
		conmem <= 1'b0;
		sram_page <= 4'd0;
		sd_cs <= 1'b1;
		
	end else begin

		spi_rx_strobe <= 1'b0;
		spi_tx_strobe <= 1'b0;
			
		reg_access = 1'b0;
		//if((a[7:4] == 4'hE) && a[0] && (nIORQ==0) && (nM1==1)) reg_access <= 1'b1;

		if(io_we && (A[7:0] == 8'hE3)) begin 
			sram_page <= din[3:0];
			conmem <= din[7];
			//if(din[6]) mapram <= 1'b1; // can reset only by cycling power (core reload)
		end

		if(io_we && (A[7:0] == 8'hE7)) sd_cs <= din[0];

		// SPI read
		if(io_rd && (A[7:0] == 8'hEB)) begin
			spi_rx_strobe <= 1'b1;
			reg_access <= 1'b1;
		end

		// SPI write
		if(io_we && (A[7:0] == 8'hEB)) begin
			spi_tx_strobe <= 1'b1;
			reg_access <= 1'b1;
		end

		if(op_rd) begin
			if((A==16'h0000) || (A==16'h0008) || (A==16'h0038) || (A==16'h0066) || (A==16'h04C6) || (A==16'h0562)) begin
				// activate automapper after this cycle
				m1_trigger <= 1'b1;
			end else if (A[15:8]==8'h3D) begin
				// activate automapper immediately
				memactive <= 1'b1;
				m1_trigger <= 1'b1;
			end else if({A[15:3],3'd0} == 16'h1ff8) begin
				// deactivate automapper after this cycle
				m1_trigger <= 1'b0;
			end
		end

		if (nM1==1) memactive <= m1_trigger;

	end
end

reg spi_tx_strobe;
reg spi_rx_strobe;

spi sdspi(
   .clk(clk),
   .tx_strobe(spi_tx_strobe),
   .rx_strobe(spi_rx_strobe),
   .din(din),
   .dout(dout),
   
   .spi_clk(sd_sck),
   .spi_di(sd_miso),
   .spi_do(sd_mosi),
	.transmit(sd_transmit)
);

reg   sd_cs;
wire  sd_sck;
wire  sd_mosi;
wire  sd_miso;

sd_card sd_card(
	.io_lba(sd_lba),
	.io_rd(sd_rd),
	.io_wr(sd_wr),
	.io_ack(sd_ack),
	.io_conf(sd_conf),
	.io_sdhc(sd_sdhc),
	.io_din(sd_dout),
	.io_din_strobe(sd_dout_strobe),
	.io_dout(sd_din),
	.io_dout_strobe(sd_din_strobe),
 
	.allow_sdhc(1'b1),  // esxdos supports SDHC

	.sd_cs(sd_cs),
	.sd_sck(sd_sck),
	.sd_sdi(sd_mosi),
	.sd_sdo(sd_miso)
);


endmodule
