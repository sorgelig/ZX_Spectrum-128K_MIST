// Copyright (C) 1991-2013 Altera Corporation
// Your use of Altera Corporation's design tools, logic functions 
// and other software and tools, and its AMPP partner logic 
// functions, and any output files from any of the foregoing 
// (including device programming or simulation files), and any 
// associated documentation or information are expressly subject 
// to the terms and conditions of the Altera Program License 
// Subscription Agreement, Altera MegaCore Function License 
// Agreement, or other applicable license agreement, including, 
// without limitation, that your use is for the sole purpose of 
// programming logic devices manufactured by Altera and sold by 
// Altera or its authorized distributors.  Please refer to the 
// applicable agreement for further details.

// PROGRAM		"Quartus II 64-Bit"
// VERSION		"Version 13.0.1 Build 232 06/12/2013 Service Pack 1 SJ Web Edition"
// CREATED		"Sun Nov 16 16:56:05 2014"

module address_pins(
	clk,
	bus_ab_pin_we,
	address,
	abus
);


input wire	clk;
input wire	bus_ab_pin_we;
input wire	[15:0] address;
output wire	[15:0] abus;

wire	SYNTHESIZED_WIRE_0;
reg	[15:0] DFFE_apin_latch;





always@(posedge SYNTHESIZED_WIRE_0)
begin
if (bus_ab_pin_we)
	begin
	DFFE_apin_latch[15:0] <= address[15:0];
	end
end

assign	abus = DFFE_apin_latch;

assign	SYNTHESIZED_WIRE_0 =  ~clk;


endmodule
