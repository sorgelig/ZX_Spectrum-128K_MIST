
module ay8910(
   input            CLK,		 // PSG Clock
   input            EN,		    // Chip enable
   input            RESET,	    // Chip RESET (set all Registers to '0', active hi)
   input            BDIR,	    // Bus Direction (0 - read , 1 - write)
   input            CS,		    // Chip Select (active hi)
   input            BC,		    // Bus control
   input      [7:0] DI,	       // Data In
   output     [7:0] DO,	       // Data Out
   output reg [7:0] CHANNEL_A, // PSG Output channel A
   output reg [7:0] CHANNEL_B, // PSG Output channel B
   output reg [7:0] CHANNEL_C  // PSG Output channel C
);
   
   
reg [3:0]    ClockDiv;		
   
// AY Registers
reg [11:0] Period_A;		    // Channel A Tone Period (R1:R0)
reg [11:0] Period_B;		    // Channel B Tone Period (R3:R2)
reg [11:0] Period_C;		    // Channel C Tone Period (R5:R4)
reg [4:0]  Period_N;		    // Noise Period (R6)
reg [7:0]  Enable;		    // Enable (R7)
reg [4:0]  Volume_A;		    // Channel A Amplitude (R10)
reg [4:0]  Volume_B;		    // Channel B Amplitude (R11)
reg [4:0]  Volume_C;		    // Channel C Amplitude (R12)
reg [15:0] Period_E;		    // Envelope Period (R14:R13)
reg [3:0]  Shape;		       // Envelope Shape/Cycle (R15)
reg [3:0]  Address;		    // Selected Register
reg [7:0]  PortA;
reg [7:0]  PortB;
   
wire Continue  = Shape[3];	 // Envelope Control
wire Attack    = Shape[2];
wire Alternate = Shape[1];
wire Hold      = Shape[0];
   
reg        Reset_Req;		 // Envelope RESET Required
reg        Reset_Ack;		 // Envelope RESET Acknoledge
reg [3:0]  Volume_E;		    // Envelope Volume
   
reg        Freq_A;		    // Tone Generator A Output
reg        Freq_B;		    // Tone Generator B Output
reg        Freq_C;		    // Tone Generator C Output
reg        Freq_N;		    // Noise Generator Output
   
function [7:0] VolumeTable;
	input [3:0] value;
begin
	case (value)
		4'b1111 : VolumeTable = 8'b11111111;
		4'b1110 : VolumeTable = 8'b10110100;
		4'b1101 : VolumeTable = 8'b01111111;
		4'b1100 : VolumeTable = 8'b01011010;
		4'b1011 : VolumeTable = 8'b00111111;
		4'b1010 : VolumeTable = 8'b00101101;
		4'b1001 : VolumeTable = 8'b00011111;
		4'b1000 : VolumeTable = 8'b00010110;
		4'b0111 : VolumeTable = 8'b00001111;
		4'b0110 : VolumeTable = 8'b00001011;
		4'b0101 : VolumeTable = 8'b00000111;
		4'b0100 : VolumeTable = 8'b00000101;
		4'b0011 : VolumeTable = 8'b00000011;
		4'b0010 : VolumeTable = 8'b00000010;
		4'b0001 : VolumeTable = 8'b00000001;
		4'b0000 : VolumeTable = 8'b00000000;
	endcase
end
endfunction
   
// Write to AY
always @(posedge RESET or posedge BDIR) begin
	if (RESET) begin
		Address   <=  4'd0;
		Period_A  <= 12'd0;
		Period_B  <= 12'd0;
		Period_C  <= 12'd0;
		Period_N  <=  5'd0;
		Enable    <=  8'd0;
		Volume_A  <=  5'd0;
		Volume_B  <=  5'd0;
		Volume_C  <=  5'd0;
		Period_E  <= 16'd0;
		Shape     <=  4'd0;
		Reset_Req <=  1'b0;
	end else  begin
		if (CS) begin
			if (BC) Address <= DI[3:0];		// Latch Address
			else
				case (Address)		// Latch Registers
					4'b0000 : Period_A[7:0]  <= DI;
					4'b0001 : Period_A[11:8] <= DI[3:0];
					4'b0010 : Period_B[7:0]  <= DI;
					4'b0011 : Period_B[11:8] <= DI[3:0];
					4'b0100 : Period_C[7:0]  <= DI;
					4'b0101 : Period_C[11:8] <= DI[3:0];
					4'b0110 : Period_N       <= DI[4:0];
					4'b0111 : Enable         <= DI;
					4'b1000 : Volume_A       <= DI[4:0];
					4'b1001 : Volume_B       <= DI[4:0];
					4'b1010 : Volume_C       <= DI[4:0];
					4'b1011 : Period_E[7:0]  <= DI;
					4'b1100 : Period_E[15:8] <= DI;
					4'b1101 :
						begin
							Shape <= DI[3:0];
							Reset_Req <= (~Reset_Ack);		// RESET Envelope Generator
						end
					4'b1110 : PortA          <= DI;
					4'b1111 : PortB          <= DI;
				endcase
		end
	end
end 
   
// Read from AY
assign DO = ((Address == 4'b0000) && CS) ? Period_A[7:0] : 
				((Address == 4'b0001) && CS) ? {4'b0000, Period_A[11:8]} : 
				((Address == 4'b0010) && CS) ? Period_B[7:0] : 
				((Address == 4'b0011) && CS) ? {4'b0000, Period_B[11:8]} : 
				((Address == 4'b0100) && CS) ? Period_C[7:0] : 
				((Address == 4'b0101) && CS) ? {4'b0000, Period_C[11:8]} : 
				((Address == 4'b0110) && CS) ? {3'b000, Period_N} : 
				((Address == 4'b0111) && CS) ? Enable : 
				((Address == 4'b1000) && CS) ? {3'b000, Volume_A} : 
				((Address == 4'b1001) && CS) ? {3'b000, Volume_B} : 
				((Address == 4'b1010) && CS) ? {3'b000, Volume_C} : 
				((Address == 4'b1011) && CS) ? Period_E[7:0] : 
				((Address == 4'b1100) && CS) ? Period_E[15:8] : 
				((Address == 4'b1101) && CS) ? {4'b0000, Shape} : 
				((Address == 4'b1110) && CS) ? (Enable[6] ? PortA : 8'd0) : (Enable[7] ? PortB : 8'd0);
   
// Divide EN
always @(posedge RESET or posedge CLK) begin
	if (RESET) ClockDiv <= 4'd0;
	else  begin
		if (EN) ClockDiv <= ClockDiv - 4'd1;
	end
end
   
// Tone Generator
always @(posedge RESET or posedge CLK) begin
	reg [11:0] Counter_A;
	reg [11:0] Counter_B;
	reg [11:0] Counter_C;
	if (RESET) begin
		Counter_A <= 12'd0;
		Counter_B <= 12'd0;
		Counter_C <= 12'd0;
		Freq_A    <=  1'b0;
		Freq_B    <=  1'b0;
		Freq_C    <=  1'b0;
	end else  begin
		if((ClockDiv[2:0] == 3'd0) && EN) begin

			// Channel A Counter
			if (Counter_A != 12'd0)       Counter_A = Counter_A - 12'd1;
				else if (Period_A != 12'd0) Counter_A = Period_A - 12'd1;
			
			if (Counter_A == 12'd0)       Freq_A <= (~Freq_A);
            
			// Channel B Counter
			if (Counter_B != 12'd0)       Counter_B = Counter_B - 12'd1;
				else if (Period_B != 12'd0) Counter_B = Period_B - 12'd1;
            
			if (Counter_B == 12'd0)       Freq_B <= (~Freq_B);
            
			// Channel C Counter
			if (Counter_C != 12'd0)       Counter_C = Counter_C - 12'd1;
				else if (Period_C != 12'd0) Counter_C = Period_C - 12'd1;
			if (Counter_C == 12'd0)       Freq_C <= (~Freq_C);
		end 
	end 
end
   
// Noise Generator
always @(posedge RESET or posedge CLK) begin
	reg [16:0] NoiseShift;
	reg [4:0]  Counter_N;
	if (RESET) begin
		Counter_N  <= 5'd0;
		NoiseShift <= 17'd1;
	end else  begin
		if ((ClockDiv[2:0] == 3'd0) && EN) begin
			if (Counter_N != 5'd0)       Counter_N = Counter_N - 5'd1;
				else if (Period_N != 5'd0) Counter_N = Period_N - 5'd1;
			if (Counter_N == 5'd0)       NoiseShift = {(NoiseShift[0] ^ NoiseShift[2]), NoiseShift[16:1]};
			Freq_N <= NoiseShift[0];
		end 
	end 
end
   
// Envelope Generator
always @(posedge RESET or posedge CLK) begin
	reg [15:0] EnvCounter;
	reg [4:0]  EnvWave;
	integer      I;
	if (RESET) begin
		EnvCounter <= 16'd0;
		EnvWave    <= 5'b11111;
		Volume_E   <= 4'd0;
		Reset_Ack  <= 1'b0;
	end else  begin
		if ((ClockDiv == 4'd0) && EN) begin

			// Envelope Period Counter 
			if ((EnvCounter != 16'd0) && (Reset_Req == Reset_Ack)) EnvCounter = EnvCounter - 16'd1;
				else if (Period_E != 16'd0) EnvCounter = Period_E - 16'd1;
            
			// Envelope Phase Counter
			if (Reset_Req != Reset_Ack) EnvWave = 5'b11111;
				else if ((EnvCounter == 16'd0) && (EnvWave[4] || (!Hold && Continue))) EnvWave = EnvWave - 5'd1;
            
			// Envelope Amplitude Counter
			for (I = 3; I >= 0; I = I - 1) begin
				if (!EnvWave[4] && !Continue) Volume_E[I] <= 1'b0;
					else if (EnvWave[4] || !(Alternate ^ Hold)) Volume_E[I] <= EnvWave[I] ^ Attack;
						else Volume_E[I] <= EnvWave[I] ^ Attack ^ 1'b1;
			end

			Reset_Ack <= Reset_Req;
		end 
	end 
end
   
// Mixer
always @(posedge RESET or posedge CLK) begin
	if (RESET) begin
		CHANNEL_A <= 8'd0;
		CHANNEL_B <= 8'd0;
		CHANNEL_C <= 8'd0;
	end else  begin
		if (EN) begin
			if (!((Enable[0] | Freq_A) & (Enable[3] | Freq_N))) CHANNEL_A <= 8'd0;
				else if (Volume_A[4] == 1'b0) CHANNEL_A <= VolumeTable(Volume_A[3:0]);
					else CHANNEL_A <= VolumeTable(Volume_E);
            
			if (!((Enable[1] | Freq_B) & (Enable[4] | Freq_N))) CHANNEL_B <= 8'd0;
				else if (Volume_B[4] == 1'b0) CHANNEL_B <= VolumeTable(Volume_B[3:0]);
					else CHANNEL_B <= VolumeTable(Volume_E);
            
			if (!((Enable[2] | Freq_C) & (Enable[5] | Freq_N))) CHANNEL_C <= 8'd0;
				else if (Volume_C[4] == 1'b0) CHANNEL_C <= VolumeTable(Volume_C[3:0]);
					else CHANNEL_C <= VolumeTable(Volume_E);
		end
	end
end

endmodule
