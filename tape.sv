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
	input         clk_sys,
	input         ce,

	input         std_load,
	input         std_wait,
	output reg    std_ready,

	input         start,
	input         pause,
	input         prev,
	input         next,
	output reg    active,
	output reg    available,
	input         req_hdr,

	input         tap_mode,
	input  [24:0] tape_size,
	input         tape_ready,

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
reg         read_done;
reg   [7:0] data;
reg         rd_req;
reg  [24:0] size;

always @(posedge clk_sys) begin
	reg old_pause, old_prev, old_next, old_ready, old_rden;

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
	reg        old_start;

	old_rden <= rd_en;

	if(old_rden & ~rd_en) begin
		if(rd_req) begin
			if(~read_done) begin
				din_r <= din;
				read_done <= 1;
			end
			rd_req <= 0;
		end else begin
			rd_req <= ~read_done;
		end
	end

	active <= !play_pause && read_cnt;
	available <= (read_cnt != 0);

	old_ready <= tape_ready;
	if(tape_ready & ~old_ready) begin
		read_cnt <= tape_size;
		size <= tape_size;
		blk_list[0] <= tape_size;
		if(!tap_mode && tape_size) begin
			hdrsz <= 32;
			read_done <= 0;
		end
	end

	if(~tape_ready) begin
		read_cnt <= 0;
		read_done <= 1;
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
		rd_req <= 0;
		old_start <= 0;
	end else if(ce) begin

		old_start <= start;
		if(start & ~auto_blk) play_pause <= 0;

		old_pause <= pause;
		if(pause & ~old_pause & ~std_load) begin
			play_pause <= ~play_pause;
			auto_blk <= ~play_pause;
		end

		if(tap_mode) begin

			// TAP file

			if(hdrsz && read_done) begin
				read_done <= 0;
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
								read_done <= 0;
								pilot <= std_load ? 16'd20 : 16'd3220;
								timeout <= 3500000;
								state <= state + 1'b1;
							end
						1: begin
								if(skip) begin
									if(!hdrsz && read_done) begin
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
										if(req_hdr & (din_r != 0)) begin
											state <= 4;
											skip  <=1;
										end
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
									if(read_done) begin
										read_done <= 0;
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

			// CSW file
			if(old_start & ~start) play_pause <= 1;

			if(hdrsz && read_done) begin
				if(hdrsz == 7) freq[ 7:0] <= din_r;
				if(hdrsz == 6) freq[15:8] <= din_r;
				read_done  <= 0;
				read_cnt <= read_cnt - 1'd1;
				hdrsz <= hdrsz - 1'd1;
			end

			if(!hdrsz && read_cnt && !play_pause) begin
				if((bitcnt <= 1) || (reload32 != 0)) begin

					if(read_done) begin
						if(reload32 != 0) begin
							bitcnt <= {din_r, bitcnt[31:8]};
							reload32 <= reload32 - 1'd1;
						end else begin
							if(din_r != 0) bitcnt <= {24'd0, din_r};
								else reload32 <= 4;

							audio_out <= ~audio_out;
						end

						read_done <= 0;
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
	input         clk_sys,
	input         ce,

	output reg    turbo,
	input         pause,
	input         prev,
	input         next,
	input         req_hdr,
	output        audio_out,
	output        led,
	output        active,

	input         buff_rd_en,
	output        buff_rd,
	output [24:0] buff_addr,
	input   [7:0] buff_din,

	input         ioctl_download,
	input  [24:0] ioctl_size,
	input         tap_mode,

	input  [15:0] addr,
	input         m1,
	input         rom_en,
	output        dout_en,
	output  [7:0] dout
);

assign dout_en = tape_ld1 | tape_ld2;
assign dout = tape_ld2 ? 8'h0 : tape_arr[addr - 16'h5CA];
assign led  = act_cnt[24] ? act_cnt[23:16] > act_cnt[7:0] : act_cnt[23:16] <= act_cnt[7:0];

reg [7:0] tape_arr[14] = '{'h18, 'hFE, 'h2E, 'hFF, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};

reg  byte_wait;
reg  wait_for_tape;
reg  tone_wait;
reg  hdr;
wire tape_ld1 = ((addr >= 'h5CA) & (addr < 'h5D8) & rom_en & turbo);
wire tape_ld2 = ((addr >= 'h56C) & (addr < 'h58F) & rom_en & turbo);

always @(posedge clk_sys) begin
	reg old_m1;

	old_m1 <= m1;
	if(m1 & ~old_m1) begin
		if(rom_en & (addr == 16'h5ED)) tone_wait <= 1;
		if((addr == 16'h556) & rom_en) {wait_for_tape, turbo, hdr} <= {1'b1, tape_allow_turbo & mode & available, req_hdr};
		if((addr < 16'h53F) | (addr >= 16'h605) | ~rom_en) {wait_for_tape, turbo, hdr, tone_wait} <= 0;

		if(tape_ld1 & (addr < 'h5CC)) begin
			byte_wait <= 1;
			tape_arr[3] <= tape_dout;
			if(byte_ready) tape_arr[1] <= 0;
		end else begin
			byte_wait <= 0;
		end
		if(!tape_ld1) tape_arr[1] <= 'hFE;
	end
	
	if(reset) {wait_for_tape, turbo, hdr, tone_wait} <= 0;
end

reg        tape_ready;
reg        tape_allow_turbo;
reg        mode;
always @(posedge clk_sys) begin
	reg old_download;
	old_download <= ioctl_download;

	if(reset | ioctl_download) begin
		mode <= 0;
		tape_ready <= 0;
		tape_allow_turbo <= 0;
	end else if(old_download & ~ioctl_download) begin
		tape_ready <= 1;
		tape_allow_turbo <= ~wait_for_tape;
		mode <= tap_mode;
	end
end

wire       byte_ready;
wire [7:0] tape_dout;
wire       available;
tape tape
(
	.clk_sys(clk_sys),
	.ce(ce),

	.audio_out(audio_out),
	.pause(pause),
	.prev(prev),
	.next(next),
	.active(active),
	.available(available),
	.req_hdr(hdr),

	.tap_mode(mode),
	.tape_ready(tape_ready),
	.tape_size(ioctl_size),

	.std_load(turbo),
	.std_wait(byte_wait),
	.std_ready(byte_ready),

	.start(tone_wait | turbo),
	.rd_en(buff_rd_en),
	.rd(buff_rd),
	.addr(buff_addr),
	.din(buff_din),
	.dout(tape_dout)
);

reg [24:0] act_cnt;
always @(posedge clk_sys) if(active || ~(available ^ act_cnt[24]) || act_cnt[23:0]) act_cnt <= act_cnt + 1'd1;

endmodule
