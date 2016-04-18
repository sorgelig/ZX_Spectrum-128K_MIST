//
// tape.v
//
// tape implementation for the spectrum core for the MiST board
// http://code.google.com/p/mist-board/
//
// Copyright (c) 2014 Till Harbaum <till@harbaum.org>
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
// This reads a CSW1 file as described here:
// http://ramsoft.bbk.org.omegahg.com/csw.html#CSW1FORMAT
//
////////////////////////////////////////////////////////////////////
//
// TAP format addition and turbo loading. Copyright (c) 2016 Sorgelig.
//


module tape 
(
	input         reset,
	input         clk,

	input         std_load,
	input         std_wait,
	output reg    std_ready,

	input         start,
	input         pause,
	input         prev,
	input         next,
	output reg    active,

	input         ready,
	input         tap_mode,
	input  [24:0] size,

	output reg    audio_out,

	input         rd_en,
	output        rd,
	output [24:0] addr,
	input   [7:0] din,
	output  [7:0] dout
);

localparam  CLOCK = 32'd3500000;

assign rd   = rd_req & rd_en;
assign addr = size - read_cnt;
assign dout = data;

reg  [24:0] read_cnt;
reg         read_ready;
reg   [7:0] data;

reg         rd_req;
reg   [7:0] saved_data;
always @(negedge rd_en) saved_data <= din;
always @(posedge rd_en) rd_req <= ~read_ready;

always @(posedge clk) begin
	reg old_pause, old_prev, old_next, old_ready, old_en;

	reg [24:0] blk_list[32];
	reg        play_pause;
	reg [15:0] blocksz;
	reg  [5:0] hdrsz;
	reg [15:0] pilot;
	reg [12:0] tick;
	reg  [7:0] state;
	reg [31:0] bitcnt;
	reg [31:0] timeout;
	reg [15:0] freq;
	reg  [2:0] reload32;
	reg [31:0] clk_play_cnt;
	reg        blk_type;
	reg  [7:0] din_r;
	reg        skip;
	reg        auto_blk;
	reg  [4:0] blk_num;

	old_ready <= ready;
	active <= !play_pause && read_cnt;

	if(reset | ~ready) begin
		read_cnt <= 0;
		read_ready <= 1;
		play_pause <= 1;
		hdrsz <= 0;
		state <= 0;
		reload32 <= 0;
		bitcnt <= 1;
		blk_type <= 0;
		skip <= 0;
		auto_blk <= 0;
		blk_list <= '{default:0};
		blk_num <= 0;
	end else begin

		old_en <= rd_en;
		if(!read_ready) begin
			if(old_en & ~rd_en & rd_req) begin
				din_r <= saved_data;
				read_ready <= 1;
			end
		end

		if(start & ~auto_blk) play_pause <= 0;

		old_pause <= pause;
		if(pause & ~old_pause & ~std_load) begin
			play_pause <= ~play_pause;
			auto_blk <= ~play_pause;
		end

		if(ready & ~old_ready) begin
			read_cnt <= size;
			blk_list[0] <= size;
		end

		if(tap_mode) begin
			if(hdrsz && read_ready) begin
				read_ready <= 0;
				if(hdrsz == 2) blocksz[7:0] <= din_r;
					else blocksz[15:8] <= din_r;
				hdrsz <= hdrsz - 1'b1;
				read_cnt <= read_cnt - 1'b1;
			end

			if(!play_pause & (read_cnt || state)) begin
				if(tick) begin
					tick <= tick - 1'b1;
					if(tick == 1) audio_out <= ~audio_out;
				end else begin
					case(state)
						0: begin
								hdrsz <= 2;
								read_ready <= 0;
								pilot <= std_load ? 16'd20 : 16'd3220;
								timeout <= 3500000;
								state <= state + 1'b1;
							end
						1: begin
								if(skip) begin
									if(!hdrsz && read_ready) begin
										blk_type <= din_r[7];
										state <= 4;
									end
								end else begin
									if(pilot) begin
										tick <= 2168;
										pilot <= pilot - 1'b1;
									end else begin
										blk_type <= din_r[7];
										if(~din_r[7] & ~std_load) pilot <= 4844;
										state <= state + 1'b1;
									end
								end
							end
						2: begin
								if(pilot) begin
									tick <= 2168;
									pilot <= pilot - 1'b1;
								end else begin
									tick <= 667;
									state <= state + 1'b1;
								end
							end
						3: begin
								tick <= 735;
								state <= state + 1'b1;
							end
						4: begin
								if(blocksz) begin
									if(read_ready) begin
										read_ready <= 0;
										data <= din_r;
										read_cnt <= read_cnt - 1'b1;
										bitcnt <= 8;
										if(skip) begin
											blocksz <= blocksz - 1'b1;
											timeout <= 0;
										end else begin
											state <= state + 1'b1;
											if(std_load) state <= 7;
										end
									end
								end else begin
									if(!read_cnt || !timeout) begin
										if(blk_type && read_cnt) begin
											blk_num <= blk_num + 1'b1;
											blk_list[blk_num + 1'b1] <= read_cnt;
											play_pause <= ~skip;
											auto_blk <= 0;
											skip <= 0;
										end
										blk_type <= 0;
										state <= 0;
									end else begin
										timeout <= timeout - 1'b1;
									end
								end
							end
						5: begin
								if(bitcnt) begin
									if(data[7]) tick <= 1710;
										else tick <= 855;
									state <= state + 1'b1;
								end else begin
									blocksz <= blocksz - 1'b1;
									state <= state - 1'b1;
								end
							end
						6: begin
								if(data[7]) tick <= 1710;
									else tick <= 855;
								data <= {data[6:0], 1'b0};
								bitcnt <= bitcnt - 1'b1;
								state <= state - 1'b1;
							end
						7: begin
								if(std_wait) begin
									std_ready <= 1;
									state <= state + 1'b1;
								end
							end
						8: begin
								if(!std_wait) begin
									std_ready <= 0;
									blocksz <= blocksz - 1'b1;
									state <= 4;
								end
							end
						default:;
					endcase
				end
			end

			old_prev <= prev;
			if(prev & ~old_prev & ~std_load) begin 
				play_pause <= 0;
				auto_blk <= 0;
				if((state>3) || !blk_num) read_cnt <= blk_list[blk_num];
				else begin 
					blk_num <= blk_num - 1'b1;
					read_cnt <= blk_list[blk_num - 1'b1];
				end
				state <= 0;
				tick <= 0;
			end

			old_next <= next;
			if(next & ~old_next & ~std_load) begin 
				play_pause <= 0;
				auto_blk <= 0;
				skip <= 1;
				tick <= 0;
			end

		end else begin
			if(~old_ready & ready) begin
				hdrsz <= 32;
				read_ready <= 0;
			end

			if(hdrsz && read_ready) begin
				if(hdrsz == 7) freq[ 7:0] <= din_r;
				if(hdrsz == 6) freq[15:8] <= din_r;
				read_ready  <= 0;
				read_cnt <= read_cnt - 1'd1;
				hdrsz <= hdrsz - 1'd1;
			end

			if(!hdrsz && read_cnt && !play_pause) begin
				if((bitcnt <= 1) || (reload32 != 0)) begin

					if(read_ready) begin
						if(reload32 != 0) begin
							bitcnt <= {din_r, bitcnt[31:8]};
							reload32 <= reload32 - 1'd1;
						end else begin
							if(din_r != 0) bitcnt <= {24'd0, din_r};
								else reload32 <= 4;

							audio_out <= ~audio_out;
						end

						read_ready <= 0;
						read_cnt <= read_cnt - 1'd1;
					end
				end else begin
					clk_play_cnt <= clk_play_cnt + freq;
					if(clk_play_cnt > CLOCK) begin	
						clk_play_cnt <= clk_play_cnt - CLOCK;
						bitcnt <= bitcnt - 1'd1;
					end
				end
			end
		end
	end
end

endmodule

//////////////////////////////////////////////////////////////////////////

module smart_tape
(
	input         reset,
	input         clk,

	output reg    turbo,
	input         pause,
	input         prev,
	input         next,
	output        audio_out,
	output        activity,

	input         rd_en,
	output        rd,
	output [24:0] addr,
	input   [7:0] din,

	input         ioctl_download,
	input  [24:0] ioctl_size,
	input         tap_mode,

	input  [15:0] cpu_addr,
	input         cpu_m1,
	input         rom_en,
	output        dout_en,
	output  [7:0] dout
);

assign dout_en = tape_ld1 | tape_ld2;
assign dout = tape_ld2 ? 8'h0 : tape_arr[cpu_addr - 16'h5CA];
assign activity = act_cnt[20] ? act_cnt[19:12] > act_cnt[7:0] : act_cnt[19:12] <= act_cnt[7:0];

reg [7:0] tape_arr[14] = '{'h18, 'hFE, 'h2E, 'hFF, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};

reg  byte_wait;
reg  wait_for_tape;
reg  tone_wait;
wire tape_ld1 = ((cpu_addr >= 'h5CA) & (cpu_addr < 'h5D8) & rom_en & turbo);
wire tape_ld2 = ((cpu_addr >= 'h56C) & (cpu_addr < 'h58F) & rom_en & turbo);

always @(posedge cpu_m1) begin
	tone_wait <= rom_en & (cpu_addr == 16'h5ED);
	if((cpu_addr == 16'h556) & rom_en) {wait_for_tape, turbo} <= {1'b1, tape_allow_turbo & mode & (addr < size)};
	if((cpu_addr < 16'h53F) | (cpu_addr >= 16'h605) | ~rom_en) {wait_for_tape, turbo} <= 2'b00;

	if(tape_ld1 & (cpu_addr < 'h5CC)) begin
		byte_wait <= 1;
		tape_arr[3] <= tape_dout;
		if(byte_ready) tape_arr[1] <= 0;
	end else begin
		byte_wait <= 0;
	end
	if(!tape_ld1) tape_arr[1] <= 'hFE;
end

reg [24:0] size;
reg        tape_ready;
reg        tape_allow_turbo;
reg        mode;
always @(posedge clk, posedge reset) begin
	reg old_download;

	if(reset) begin
		mode <= 0;
		tape_ready <= 0;
		old_download  <= 0;
		tape_allow_turbo <= 0;
		size <= 0;
	end else begin
		old_download <= ioctl_download;
		if(old_download & !ioctl_download) begin
			size <= ioctl_size;
			tape_ready <= 1;
			tape_allow_turbo <= ~wait_for_tape;
			mode <= tap_mode;
		end
		if(ioctl_download) tape_ready <= 0;
	end
end

wire       active;
wire       byte_ready;
wire [7:0] tape_dout;
tape tape
(
	.clk(clk),
	.reset(reset),

	.audio_out(audio_out),
	.pause(pause),
	.prev(prev),
	.next(next),
	.active(active),

	.ready(tape_ready),
	.tap_mode(mode),
	.size(size),

	.std_load(turbo),
	.std_wait(byte_wait),
	.std_ready(byte_ready),

	.start(tone_wait | turbo),
	.rd_en(rd_en),
	.rd(rd),
	.addr(addr),
	.din(din),
	.dout(tape_dout)
);

reg [20:0] act_cnt;
always @(posedge clk) if(active || ~((addr<size) ^ act_cnt[20]) || act_cnt[19:0]) act_cnt <= act_cnt + 1'd1;

endmodule
