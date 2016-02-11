

module ym2149(
   input            CLK,		 // PSG Clock
   input            RESET,	    // Chip RESET (set all Registers to '0', active hi)
   input            BDIR,	    // Bus Direction (0 - read , 1 - write)
   input            CS,		    // Chip Select (active hi)
   input            BC,		    // Bus control
   input      [7:0] DI,	       // Data In
   output     [7:0] DO,	       // Data Out
   output reg [7:0] CHANNEL_A, // PSG Output channel A
   output reg [7:0] CHANNEL_B, // PSG Output channel B
   output reg [7:0] CHANNEL_C, // PSG Output channel C

   input            SEL,
   input            MODE
);
   
//  signals
reg [3:0]  cnt_div;
reg        noise_div;
reg        ena_div;
reg        ena_div_noise;
reg [16:0] poly17;
   
// registers
reg [3:0]  addr;
   
reg [7:0]  ymreg[0:15];
reg        env_reset;
   
reg [4:0]  noise_gen_cnt;
wire       noise_gen_op;
reg [11:0] tone_gen_cnt[1:3];
reg [3:1]  tone_gen_op;
   
reg [15:0] env_gen_cnt;
reg        env_ena;
reg        env_hold;
reg        env_inc;
reg [4:0]  env_vol;
   
reg [4:0]  A;
reg [4:0]  B;
reg [4:0]  C;

wire [7:0] volTableAy[16] = 
       '{8'h00, 8'h03, 8'h04, 8'h06, 
		   8'h0a, 8'h0f, 8'h15, 8'h22, 
		   8'h28, 8'h41, 8'h5b, 8'h72, 
		   8'h90, 8'hb5, 8'hd7, 8'hff
		 };
		 
wire [7:0] volTableYm[32] = 
		'{8'h00, 8'h01, 8'h01, 8'h02, 
		  8'h02, 8'h03, 8'h03, 8'h04, 
		  8'h06, 8'h07, 8'h09, 8'h0a, 
		  8'h0c, 8'h0e, 8'h11, 8'h13, 
		  8'h17, 8'h1b, 8'h20, 8'h25, 
		  8'h2c, 8'h35, 8'h3e, 8'h47, 
		  8'h54, 8'h66, 8'h77, 8'h88, 
		  8'ha1, 8'hc0, 8'he0, 8'hff
		};
   
always @(posedge RESET, posedge BDIR) begin
	if (RESET) begin
		ymreg[0]  <= 0;
		ymreg[1]  <= 0;
		ymreg[2]  <= 0;
		ymreg[3]  <= 0;
		ymreg[4]  <= 0;
		ymreg[5]  <= 0;
		ymreg[6]  <= 0;
		ymreg[7]  <= 255;
		ymreg[8]  <= 0;
		ymreg[9]  <= 0;
		ymreg[10] <= 0;
		ymreg[11] <= 0;
		ymreg[12] <= 0;
		ymreg[13] <= 0;
		ymreg[14] <= 0;
		ymreg[15] <= 0;
		addr <= 0;
	end else begin
		if (BC) addr <= DI[3:0];
		else begin 
			ymreg[addr] <= DI;
			env_reset <= (addr == 13);
		end
	end
end

// Read from AY
assign DO =	(addr ==  0) ? ymreg[0]  : 
				(addr ==  1) ? {4'b0000, ymreg[1][3:0]} : 
				(addr ==  2) ? ymreg[2]  : 
				(addr ==  3) ? {4'b0000, ymreg[3][3:0]} : 
				(addr ==  4) ? ymreg[4]  : 
				(addr ==  5) ? {4'b0000, ymreg[5][3:0]} : 
				(addr ==  6) ? {3'b000,  ymreg[6][4:0]} : 
				(addr ==  7) ? ymreg[7]  : 
				(addr ==  8) ? {3'b000,  ymreg[8][4:0]} : 
				(addr ==  9) ? {3'b000,  ymreg[9][4:0]} : 
				(addr == 10) ? {3'b000,  ymreg[10][4:0]} : 
				(addr == 11) ? ymreg[11] : 
				(addr == 12) ? ymreg[12] : 
				(addr == 13) ? {4'b0000, ymreg[13][3:0]} : 
				(addr == 14) ? (ymreg[7][6] ? ymreg[14] : 8'd0) : (ymreg[7][7] ? ymreg[15] : 8'd0);

//  p_divider
always @(posedge CLK) begin
	ena_div <= 1'b0;
	ena_div_noise <= 1'b0;
	if (cnt_div == 4'b0000) begin
		cnt_div <= {SEL, 3'b111};
		ena_div <= 1'b1;
            
		noise_div <= (~noise_div);
		if (noise_div) ena_div_noise <= 1'b1;
	end else begin
		cnt_div <= cnt_div - 1'b1;
	end
end
   
//  p_noise_gen
always @(posedge CLK) begin
	reg [4:0] noise_gen_comp;
	reg       poly17_zero;
      
	if (ymreg[6][4:0] == 5'b00000) noise_gen_comp = 5'b00000;
		else noise_gen_comp = (ymreg[6][4:0]) - 1'd1;
         
	poly17_zero = 1'b0;
	if (poly17 == 17'b00000000000000000) poly17_zero = 1'b1;

	if (ena_div_noise) begin
		if (noise_gen_cnt >= noise_gen_comp) begin
			noise_gen_cnt <= 5'b00000;
			poly17 <= {(poly17[0] ^ poly17[2] ^ poly17_zero), poly17[16:1]};
		end else begin
			noise_gen_cnt <= noise_gen_cnt + 1'd1;
		end
	end
end

assign noise_gen_op = poly17[0];
   
//p_tone_gens
always @(posedge CLK) begin
	reg [11:0]      tone_gen_freq[1:3];
	reg [11:0]      tone_gen_comp[1:3];
	integer         i;
      
	// looks like real chips count up - we need to get the Exact behaviour ..
	tone_gen_freq[1] = {ymreg[1][3:0], ymreg[0]};
	tone_gen_freq[2] = {ymreg[3][3:0], ymreg[2]};
	tone_gen_freq[3] = {ymreg[5][3:0], ymreg[4]};
         
	// period 0 = period 1
	for (i = 1; i <= 3; i = i + 1) begin
		if (tone_gen_freq[i] == 12'h000) tone_gen_comp[i] = 12'h000;
			else tone_gen_comp[i] = ((tone_gen_freq[i]) - 1'd1);
	end
	
	for (i = 1; i <= 3; i = i + 1) begin
		if (ena_div == 1'b1) begin
			if (tone_gen_cnt[i] >= tone_gen_comp[i]) begin
				tone_gen_cnt[i] <= 12'h000;
				tone_gen_op[i] <= (~tone_gen_op[i]);
			end else begin
				tone_gen_cnt[i] <= ((tone_gen_cnt[i]) + 1'd1);
			end
		end
	end
end
   
//p_envelope_freq
always @(posedge CLK) begin
	reg [15:0]      env_gen_freq;
	reg [15:0]      env_gen_comp;
      
	env_gen_freq = {ymreg[12], ymreg[11]};
	// envelope freqs 1 and 0 are the same.
	if (env_gen_freq == 16'h0000) env_gen_comp = 16'h0000;
		else env_gen_comp = (env_gen_freq - 1'd1);
         
	env_ena <= 1'b0;
	if (ena_div == 1'b1) begin
		if (env_gen_cnt >= env_gen_comp) begin
			env_gen_cnt <= 16'h0000;
			env_ena <= 1'b1;
		end else begin
			env_gen_cnt <= (env_gen_cnt + 1'd1);
		end
	end
end
   
//p_envelope_shape       : process(env_reset, CLK)
always @(posedge CLK) begin
	reg is_bot;
	reg is_bot_p1;
	reg is_top_m1;
	reg is_top;
      // envelope shapes
      // C AtAlH
      // 0 0 x x  \___
      //
      // 0 1 x x  /___
      //
      // 1 0 0 0  \\\\
      //
      // 1 0 0 1  \___
      //
      // 1 0 1 0  \/\/
      //           ___
      // 1 0 1 1  \
      //
      // 1 1 0 0  ////
      //           ___
      // 1 1 0 1  /
      //
      // 1 1 1 0  /\/\
      //
      // 1 1 1 1  /___
      
	if (env_reset == 1'b1) begin
		// load initial state
		if (ymreg[13][2] == 1'b0) begin		// attack
			env_vol <= 5'b11111;
			env_inc <= 1'b0;		// -1
		end else begin
			env_vol <= 5'b00000;
			env_inc <= 1'b1;		// +1
		end
		env_hold <= 1'b0;
	end else begin
            
		is_bot = (env_vol == 5'b00000);
		is_bot_p1 = (env_vol == 5'b00001);
		is_top_m1 = (env_vol == 5'b11110);
		is_top = (env_vol == 5'b11111);
            
		if (env_ena) begin
			if (!env_hold) begin
				if (env_inc) env_vol <= (env_vol + 5'b00001);
					else env_vol <= (env_vol + 5'b11111);
			end
                  
			// envelope shape control.
			if (ymreg[13][3] == 1'b0) begin
				if(!env_inc) begin	// down
					if (is_bot_p1) env_hold <= 1'b1;
				end else if (is_top) env_hold <= 1'b1;
			end else if (ymreg[13][0]) begin		// hold = 1
				if(!env_inc) begin	// down
					if (ymreg[13][1]) begin		// alt
						if (is_bot) env_hold <= 1'b1;
					end else if (is_bot_p1) env_hold <= 1'b1;
				end else if (ymreg[13][1]) begin	// alt
					if (is_top) env_hold <= 1'b1;
				end else if (is_top_m1) env_hold <= 1'b1;
			end else if (ymreg[13][1]) begin		// alternate
				if (env_inc == 1'b0) begin		// down
					if (is_bot_p1) env_hold <= 1'b1;
					if (is_bot) begin
						env_hold <= 1'b0;
						env_inc <= 1'b1;
					end
				end else begin
					if (is_top_m1) env_hold <= 1'b1;
					if (is_top) begin
						env_hold <= 1'b0;
						env_inc <= 1'b0;
					end
				end
			end
		end
	end
end
   

//p_chan_mixer_table     : process
always @(posedge CLK) begin
	reg [2:0]       chan_mixed;

	chan_mixed[0] = (ymreg[7][0] | tone_gen_op[1]) & (ymreg[7][3] | noise_gen_op);
	chan_mixed[1] = (ymreg[7][1] | tone_gen_op[2]) & (ymreg[7][4] | noise_gen_op);
	chan_mixed[2] = (ymreg[7][2] | tone_gen_op[3]) & (ymreg[7][5] | noise_gen_op);
            
	A <= 5'b00000;
	B <= 5'b00000;
	C <= 5'b00000;
            
	if (chan_mixed[0]) begin
		if (!ymreg[8][4]) A <= {ymreg[8][3:0], 1'b1};
			else A <= env_vol[4:0];
	end
            
	if (chan_mixed[1]) begin
		if (!ymreg[9][4]) B <= {ymreg[9][3:0], 1'b1};
			else B <= env_vol[4:0];
	end
            
	if (chan_mixed[2]) begin
		if (!ymreg[10][4]) C <= {ymreg[10][3:0], 1'b1};
			else C <= env_vol[4:0];
	end
end
   
always @(posedge CLK) begin
	if(RESET) begin
		CHANNEL_A <= 8'h00;
		CHANNEL_B <= 8'h00;
		CHANNEL_C <= 8'h00;
	end else if (!MODE) begin
		CHANNEL_A <= volTableYm[A];
		CHANNEL_B <= volTableYm[B];
		CHANNEL_C <= volTableYm[C];
	end else begin
		CHANNEL_A <= volTableAy[A[4:1]];
		CHANNEL_B <= volTableAy[B[4:1]];
		CHANNEL_C <= volTableAy[C[4:1]];
	end
end
   
endmodule
