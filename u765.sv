// ====================================================================
//
//  NEC u765 FDC
//
//  Copyright (C) 2017 Gyorgy Szombathelyi <gyurco@freemail.hu>
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

//TODO:
//better SpeedLock support
//sk, mt flags for READ
//WRITE commands
//READ TRACK command
//SCAN commands
//FORMAT (but this would require squeezing/expanding the image file)

module u765
(
	input        clk_sys,     // sys clock
	input        reset,	     // async reset
	input        a0,
	input        nRD,          // i/o read
	input        nWR,          // i/o write
	input  [7:0] din,         // i/o data in
	output [7:0] dout,        // i/o data out

	input        img_mounted, // signaling that new image has been mounted
	input [31:0] img_size,    // size of image in bytes
	output[31:0] sd_lba,
	output reg   sd_rd,
	output reg   sd_wr,
	input        sd_ack,
	input  [8:0] sd_buff_addr,
	input  [7:0] sd_buff_dout,
	output [7:0] sd_buff_din,
	input        sd_buff_wr
);

parameter COMMAND_TIMEOUT = 26'd35000000;

parameter UPD765_MAIN_D0B = 0;
parameter UPD765_MAIN_D1B = 1;
parameter UPD765_MAIN_D2B = 2;
parameter UPD765_MAIN_D3B = 3;
parameter UPD765_MAIN_CB = 4;
parameter UPD765_MAIN_EXM = 5;
parameter UPD765_MAIN_DIO = 6;
parameter UPD765_MAIN_RQM = 7;

parameter UPD765_ST3_US0 = 0;
parameter UPD765_ST3_US1 = 1;
parameter UPD765_ST3_HD = 2;
parameter UPD765_ST3_TS = 3;
parameter UPD765_ST3_T0 = 4;
parameter UPD765_ST3_RDY = 5;
parameter UPD765_ST3_WP = 6;
parameter UPD765_ST3_FT = 7;

parameter UPD765_SD_BUFF_TRACKINFO = 1'd0;
parameter UPD765_SD_BUFF_SECTOR = 1'd1;

typedef enum
{
 COMMAND_IDLE,

 COMMAND_READ_DELETED_DATA,
 COMMAND_READ_DATA,
 COMMAND_READ_DATA_EXEC0,
 COMMAND_READ_DATA_EXEC1,
 COMMAND_READ_DATA_EXEC2,
 COMMAND_READ_DATA_EXEC3,
 COMMAND_READ_DATA_EXEC4,
 COMMAND_READ_DATA_EXEC5,
 COMMAND_READ_DATA_EXEC6,
 COMMAND_READ_DATA_EXEC7,

 COMMAND_WRITE_DELETED_DATA,
 COMMAND_WRITE_DATA,
 COMMAND_WRITE_DATA_EXEC,

 COMMAND_READ_TRACK,
 COMMAND_READ_TRACK_EXEC,

 COMMAND_READ_ID,
 COMMAND_READ_ID_EXEC0,
 COMMAND_READ_ID_EXEC1,

 COMMAND_FORMAT_TRACK,
 COMMAND_FORMAT_TRACK1,
 COMMAND_FORMAT_TRACK2,
 COMMAND_FORMAT_TRACK3,
 COMMAND_FORMAT_TRACK4,
 COMMAND_FORMAT_TRACK5,
 COMMAND_FORMAT_TRACK6,
 COMMAND_FORMAT_TRACK7,
 COMMAND_FORMAT_TRACK8,

 COMMAND_SCAN_EQUAL,
 COMMAND_SCAN_LOW_OR_EQUAL,
 COMMAND_SCAN_HIGH_OR_EQUAL,

 COMMAND_RECALIBRATE,

 COMMAND_SENSE_INTERRUPT_STATUS,
 COMMAND_SENSE_INTERRUPT_STATUS1,
 COMMAND_SENSE_INTERRUPT_STATUS2,

 COMMAND_SPECIFY,
 COMMAND_SPECIFY_WR,

 COMMAND_SENSE_DRIVE_STATUS,
 COMMAND_SENSE_DRIVE_STATUS_RD,

 COMMAND_SEEK,
 COMMAND_SEEK_EXEC,

 COMMAND_SETUP,

 COMMAND_READ_RESULTS,

 COMMAND_INVALID,
 COMMAND_INVALID1
} state_t;

reg [19:0] image_size;
reg image_ready = 0;
reg [7:0] image_tracks;
reg [7:0] image_track_size;
reg [7:0] image_sides;
reg [7:0] image_track_offsets_addr = 0;
reg image_track_offsets_wr;
reg [15:0] image_track_offsets_out, image_track_offsets_in;
reg image_edsk; //DSK - 0, EDSK - 1

//buffers in RAM
logic [15:0] image_track_offsets[0:255]; //offset of tracks * 256
logic [7:0] sd_buff_sector[0:511]; // buffer for a sector from the image
logic [7:0] sd_buff_trackinfo[0:511]; //buffer for trackinfo from the image

reg [7:0] buff_data_in;
reg [8:0] buff_addr;
wire sd_buff_type;

wire rd = nWR & ~nRD;
wire wr = ~nWR & nRD;

always @(negedge clk_sys) begin
   //RAM read handlers
	image_track_offsets_in <= image_track_offsets[image_track_offsets_addr];
	buff_data_in <= sd_buff_type ? sd_buff_sector[buff_addr] : sd_buff_trackinfo[buff_addr];
end

always @(posedge clk_sys) begin
	reg old_wr, old_rd;
	reg [31:0] seek_pos;
	reg [7:0] sector_c, sector_h, sector_r, sector_n;
	reg [7:0] sector_st1, sector_st2, total_sectors;
	reg [15:0] sector_size;
	reg [7:0] current_sector;
	reg [14:0] bytes_to_read;
	reg [2:0] substate;
	reg [1:0] image_scan_state = 0;
	reg old_mounted;
	reg [15:0] track_offset;
	reg [5:0] ack;
	reg sd_busy;
	reg [26:0] timeout;
	reg rw_deleted;
	reg [7:0] m_status;  //main status register
	reg [7:0] status[4]; //st0-3
	reg [5:0] state, command;
	reg [7:0] ncn; //new cylinder number
	reg [7:0] pcn; //present cylinder number
   reg ds0;
	reg hds;
	reg [7:0] c;
	reg [7:0] h;
	reg [7:0] r;
	reg [7:0] n;
	reg [7:0] eot;
	reg [7:0] gpl;
	reg [7:0] dtl;
	reg [7:0] sc;
	reg [7:0] d;

	reg mt;
	reg mfm;
	reg sk;
	reg int_state;

	old_wr <= wr;
	old_rd <= rd;

	//RAM write handler for image_track_offsets
	if (image_track_offsets_wr) begin
		image_track_offsets[image_track_offsets_addr] <= image_track_offsets_out;
		image_track_offsets_wr <= 0;
	end

	//RAM write handler for sd_buff
	ack <= {ack[4:0], sd_ack};
	if(ack[5:4] == 'b01) {sd_rd,sd_wr} <= 0;
	if(ack[5:4] == 'b10) sd_busy <= 0;
	if (sd_buff_wr & sd_ack) begin
		if (sd_buff_type)
			sd_buff_sector[sd_buff_addr] <= sd_buff_dout;
		else
			sd_buff_trackinfo[sd_buff_addr] <= sd_buff_dout;
	end

	//new image mounted
	old_mounted <= img_mounted;
	if(old_mounted & ~img_mounted) begin
		image_size <= img_size[19:0];
		image_scan_state<=1;
		image_ready<=0;
		pcn<=0;
		ncn<=0;
		c<=0;
		h<=0;
		r<=0;
		n<=0;
		int_state<=0;
	end

   //Process the image file
	case (image_scan_state)
		0: ;//no new image
		1: //read the first 512 byte
			if (~sd_busy) begin
				sd_buff_type <= UPD765_SD_BUFF_SECTOR;
				sd_rd<=1;
				sd_lba<=0;
				sd_busy<=1;
				track_offset<=16'h1; //offset 100h
				image_track_offsets_addr <= 0;
				buff_addr<=0;
				image_scan_state<=2;
			end
		2: //process the header
			if (~sd_busy) begin
				if (buff_addr == 0) begin
					if (buff_data_in == "E")
						image_edsk <= 1;
					else if (buff_data_in == "M")
						image_edsk <= 0;
					else begin
						image_ready <= 0;
						image_scan_state <= 0;
						status[3][UPD765_ST3_WP] <= 1;
					end
				end else if (buff_addr == 9'h30) image_tracks <= buff_data_in;
				else if (buff_addr == 9'h31) image_sides <= buff_data_in;
				else if (buff_addr == 9'h33) image_track_size <= buff_data_in;
				else if (buff_addr >= 9'h34) begin
					if (image_track_offsets_addr != image_tracks << (image_sides - 1)) begin
						image_track_offsets_wr <= 1;
						if (image_edsk) begin
							image_track_offsets_out <= buff_data_in ? track_offset : 16'd0;
							track_offset <= track_offset + buff_data_in;
						end else begin
							image_track_offsets_out <= track_offset;
							track_offset <= track_offset + image_track_size;
						end
						image_scan_state <= 3;
					end else begin
						image_ready <= 1;
						image_scan_state <= 0;
						status[3][UPD765_ST3_WP] <= 0;
					end
				end
				buff_addr <= buff_addr + 1'd1;
			end
		3: begin
				image_track_offsets_addr <= image_track_offsets_addr + 1'd1;
				image_scan_state <= 2;
			end
	endcase

	//the FDC
   if (reset) begin
		m_status <= 8'h80;
		state <= COMMAND_IDLE;
		status[0] <= 0;
		status[1] <= 0;
		status[2] <= 0;
		status[3] <= 8'h50;
		{ds0, ncn, pcn, c, h, r, n} <= 0;
		int_state<=0;
		{image_ready, image_scan_state} <= 0;
		{ack, sd_wr, sd_rd, sd_busy} <= 0;
		image_track_offsets_wr <= 0;
	end else begin
		case(state)
			COMMAND_IDLE:
			begin
				m_status[UPD765_MAIN_CB] <= 0;
				m_status[UPD765_MAIN_DIO] <= 0;
				m_status[UPD765_MAIN_RQM] <= 1;

				if (~old_wr & wr & a0) begin
					mt <= din[7];
					mfm <= din[6];
					sk <= din[5];
					substate <= 0;
					casex (din[7:0])
						8'bXXX00110: state <= COMMAND_READ_DATA;
						8'bXXX01100: state <= COMMAND_READ_DELETED_DATA;
						8'bXX000101: state <= COMMAND_WRITE_DATA;
						8'bXX001001: state <= COMMAND_WRITE_DELETED_DATA;
						8'b0XX00010: state <= COMMAND_READ_TRACK;
						8'b0X001010: state <= COMMAND_READ_ID;
						8'b0X001101: state <= COMMAND_FORMAT_TRACK;
						8'bXXX10001: state <= COMMAND_SCAN_EQUAL;
						8'bXXX11001: state <= COMMAND_SCAN_LOW_OR_EQUAL;
						8'bXXX11101: state <= COMMAND_SCAN_HIGH_OR_EQUAL;
						8'b00000111: state <= COMMAND_RECALIBRATE;
						8'b00001000: state <= COMMAND_SENSE_INTERRUPT_STATUS;
						8'b00000011: state <= COMMAND_SPECIFY;
						8'b00000100: state <= COMMAND_SENSE_DRIVE_STATUS;
						8'b00001111: state <= COMMAND_SEEK;
						default: state <= COMMAND_INVALID;
					endcase
				end else if(~old_rd & rd & a0) begin
					dout <= 8'hff;
				end
			end

			COMMAND_SENSE_INTERRUPT_STATUS:
			if (int_state) begin
				int_state <= 0;
				m_status[UPD765_MAIN_DIO] <= 1;
				m_status[UPD765_MAIN_CB] <= 1;
				state <= COMMAND_SENSE_INTERRUPT_STATUS1;
			end else begin
				state <= COMMAND_INVALID;
			end
			COMMAND_SENSE_INTERRUPT_STATUS1:
			if (~old_rd & rd & a0) begin
				dout <= status[0];
				state <= COMMAND_SENSE_INTERRUPT_STATUS2;
			end
			COMMAND_SENSE_INTERRUPT_STATUS2:
			if (~old_rd & rd & a0) begin
				dout <= pcn;
				state <= COMMAND_IDLE;
			end

			COMMAND_SENSE_DRIVE_STATUS:
			begin
				int_state <= 0;
				if (~old_wr & wr & a0) begin
					state <= COMMAND_SENSE_DRIVE_STATUS_RD;
					m_status[UPD765_MAIN_DIO] <= 1;
					ds0 <= din[0];
				end
			end
			COMMAND_SENSE_DRIVE_STATUS_RD:
			if (~old_rd & rd & a0) begin
				dout <= ds0 ? 8'h1 : status[3];
				state <= COMMAND_IDLE;
			end

			COMMAND_SPECIFY:
			begin
				m_status[UPD765_MAIN_CB] <= 1;
				int_state <= 0;
				if (~old_wr & wr & a0) begin
					state <= COMMAND_SPECIFY_WR;
				end
			end
			COMMAND_SPECIFY_WR:
			if (~old_wr & wr & a0) begin
				state <= COMMAND_IDLE;
			end

			COMMAND_RECALIBRATE:
			begin
				if (~old_wr & wr & a0) begin
					state <= COMMAND_IDLE;
					ncn <= 0;
					pcn <= 0;
					status[0] <= 8'h20;
					status[3][UPD765_ST3_T0] <= 1;
					int_state <= 1;
				end else begin
					int_state <= 0;
				end
			end

			COMMAND_SEEK:
			begin
				int_state <= 0;
				m_status[UPD765_MAIN_CB] <= 1;
				if (~old_wr & wr & a0) begin
					hds <= din[2];
					state <= COMMAND_SEEK_EXEC;
				end
			end

			COMMAND_SEEK_EXEC:
			if (~old_wr & wr & a0) begin
				if ((image_ready && din<image_tracks) || !din) begin
					ncn <= din;
					pcn <= din;
					int_state <= 1;
					status[0] <= 8'h20;
					status[3][UPD765_ST3_T0] <= !din;
				end else begin
					//Seek error
					int_state <= 1;
					status[0] <= 8'hE8;
				end
				state <= COMMAND_IDLE;
			end

			COMMAND_READ_ID:
			begin
				int_state<=0;
				m_status[UPD765_MAIN_CB] <= 1;
				if (~old_wr & wr & a0) begin
				   hds <= din[2];
					image_track_offsets_addr <= (pcn << (image_sides - 1)) + din[2];
					state <= COMMAND_READ_ID_EXEC0;
					m_status[UPD765_MAIN_RQM] <= 0;
				end
			end

         COMMAND_READ_ID_EXEC0:
			if (image_ready && image_track_offsets_in) begin
				//load the TrackInfo
				sd_buff_type <= UPD765_SD_BUFF_TRACKINFO;
				sd_rd <= 1;
				sd_lba <= image_track_offsets_in[15:1];
				buff_addr <= {image_track_offsets_in[0], 8'h18};
				sd_busy <= 1;
				state <= COMMAND_READ_ID_EXEC1;
			end else begin
				status[0] <= 8'h40;
				status[1] <= 8'b101;
				status[2] <= 0;
				state <= COMMAND_READ_RESULTS;
			end

			COMMAND_READ_ID_EXEC1:
			if (~sd_busy) begin
				if (buff_addr[7:0] == 8'h18) sector_c <= buff_data_in;
				else if (buff_addr[7:0] == 8'h19) sector_h <= buff_data_in;
				else if (buff_addr[7:0] == 8'h1A) sector_r <= buff_data_in;
				else if (buff_addr[7:0] == 8'h1B) begin
					sector_n <= buff_data_in;
					status[0] <= 0;
					status[1] <= 0;
					status[2] <= 0;
					state <= COMMAND_READ_RESULTS;
				end
				buff_addr <= buff_addr + 1'd1;
			end

			COMMAND_READ_DATA:
			begin
				int_state <= 0;
				m_status[UPD765_MAIN_CB] <= 1;
				if (~old_wr & wr & a0) begin
				   hds <= din[2];
					command <= COMMAND_READ_DATA_EXEC0;
					state <= COMMAND_SETUP;
					rw_deleted <= 0;
				end
			end

			COMMAND_READ_DELETED_DATA:
			begin
				int_state<=0;
				m_status[UPD765_MAIN_CB] <= 1;
				if (~old_wr & wr & a0) begin
				   hds <= din[2];
					command<=COMMAND_READ_DATA_EXEC0;
					state<=COMMAND_SETUP;
					rw_deleted <= 1;
				end
			end

			COMMAND_READ_DATA_EXEC0:
			if (image_ready) begin
				m_status[UPD765_MAIN_RQM] <= 0;
				m_status[UPD765_MAIN_EXM] <= 1;
				m_status[UPD765_MAIN_DIO] <= 1;
				// Read from the track stored at the last seek
				// even if different one is given in the command
				image_track_offsets_addr <= (pcn << (image_sides - 1)) + hds;
				state <= COMMAND_READ_DATA_EXEC1;
			end else begin
				state <= COMMAND_READ_RESULTS;
			end


			COMMAND_READ_DATA_EXEC1:
			if (~sd_busy) begin
				//read TrackInfo into RAM
				sd_buff_type <= UPD765_SD_BUFF_TRACKINFO;
				sd_rd <= 1;
				sd_lba <= image_track_offsets_in[15:1];
				sd_busy <= 1;
				state <= COMMAND_READ_DATA_EXEC2;
			end

			COMMAND_READ_DATA_EXEC2:
			if (~sd_busy) begin
				current_sector <= 1;
				sd_buff_type <= UPD765_SD_BUFF_TRACKINFO;
				seek_pos <= {image_track_offsets_in+1'd1,8'd0}; //TrackInfo+256bytes
				buff_addr <= {image_track_offsets_in[0], 8'h14}; //sector size
				state <= COMMAND_READ_DATA_EXEC3;
			end

			COMMAND_READ_DATA_EXEC3:
			if (~sd_busy) begin
				if (buff_addr[7:0] == 8'h14) begin
					if (!image_edsk) sector_size <= 8'h80 << buff_data_in[2:0];
					buff_addr[7:0] <= 8'h15; //number of sectors
				end else	if (buff_addr[7:0] == 8'h15) begin
					total_sectors <= buff_data_in;
					buff_addr[7:0] <= 8'h18; //sector info list
				end else if (current_sector > total_sectors) begin
					//sector not found
					m_status[UPD765_MAIN_EXM] <= 0;
					state <= COMMAND_READ_RESULTS;
					status[0] <= 64;
					status[1] <= 4;
					status[2] <= 0;
				end else begin
					//process sector info list
					case (buff_addr[2:0])
						0: sector_c <= buff_data_in;
						1: sector_h <= buff_data_in;
						2: sector_r <= buff_data_in;
						3: sector_n <= buff_data_in;
						4: sector_st1 <= buff_data_in;
						5: sector_st2 <= buff_data_in;
						6: if (image_edsk) sector_size[7:0] <= buff_data_in;
						7: begin
								if (image_edsk) sector_size[15:8] <= buff_data_in;
									state <= COMMAND_READ_DATA_EXEC4;
								end
					endcase
						buff_addr <= buff_addr + 1'd1;
					end
			end

			COMMAND_READ_DATA_EXEC4:
			if (sector_c != c) begin
				m_status[UPD765_MAIN_EXM] <= 0;
				state <= COMMAND_READ_RESULTS;
				status[0] <= 64;
				status[1] <= 4;
				status[2] <= 2; //bad cylinder
			end else if (sector_r == r && sector_h == h && sector_n == n) begin
				//sector found in the sector info list
				if (sector_n == 6) bytes_to_read <= 6144;
				else if (!sector_n) bytes_to_read = dtl;
				else bytes_to_read <= 8'h80 << sector_n[2:0];
				timeout <= COMMAND_TIMEOUT;
				state <= COMMAND_READ_DATA_EXEC5;
			end else begin
				//try the next sector in the sectorinfo list
				current_sector <= current_sector + 1'd1;
				seek_pos <= seek_pos + sector_size;
				state <= COMMAND_READ_DATA_EXEC3;
			end

			COMMAND_READ_DATA_EXEC5:
			if (~sd_busy) begin
				//Read the sector to the RAM
				sd_buff_type <= UPD765_SD_BUFF_SECTOR;
				sd_rd <= 1;
				sd_lba <= seek_pos[31:9];
				sd_busy <= 1;
				buff_addr <= seek_pos[8:0];
				state <= COMMAND_READ_DATA_EXEC6;
			end

			COMMAND_READ_DATA_EXEC6:
			if (!bytes_to_read) begin
				//end of the current sector
				m_status[UPD765_MAIN_RQM] <= 0;
				state <= COMMAND_READ_DATA_EXEC7;
			end else if (!timeout) begin
				m_status[UPD765_MAIN_EXM] <= 0;
				state <= COMMAND_READ_RESULTS;
				status[0] <= 64;
				status[1] <= { sector_st1[7:5], !timeout, sector_st1[3:0] };
				status[2] <= sector_st2;
			end else begin
				m_status[UPD765_MAIN_RQM] <= ~sd_busy;
				if (!sd_busy) begin
					if (~old_rd & rd & a0) begin
						if (&buff_addr) begin
							//sector continues on the next LBA
							state <= COMMAND_READ_DATA_EXEC5;
						end
						//Speedlock: randomize 'weak' sectors last bytes
						dout <= (sector_st1[5] & sector_st2[5] & !bytes_to_read[14:2]) ? 
									timeout[7:0] :
									buff_data_in;
						buff_addr <= buff_addr + 1'd1;
						bytes_to_read <= bytes_to_read - 1'd1;
						seek_pos <= seek_pos + 1'd1;
						timeout <= COMMAND_TIMEOUT;
					end else begin
						timeout <= timeout - 1'd1;
					end
				end
			end

			COMMAND_READ_DATA_EXEC7:
			if	((sector_st1[5] & sector_st2[5]) | (rw_deleted ^ sector_st2[6])) begin
		      //deleted mark or crc error
				m_status[UPD765_MAIN_EXM] <= 0;
				state <= COMMAND_READ_RESULTS;
				status[0] <= 64;
				status[1] <= sector_st1;
				status[2] <= rw_deleted ? 8'h40 : sector_st2;
			end else	if (sector_r == eot) begin
				//end of cylinder
				m_status[UPD765_MAIN_EXM] <= 0;
				state <= COMMAND_READ_RESULTS;
				status[0] <= 64;
				status[1] <= 128;
				status[2] <= 0;
			end else begin
				//read the next sector (multi-sector transfer)
				r <= r + 1'd1;
				state <= COMMAND_READ_DATA_EXEC2;
			end

			COMMAND_READ_TRACK:
			begin
				int_state <= 0;
				m_status[UPD765_MAIN_CB] <= 1;
				if (~old_wr & wr & a0) begin
					command <= COMMAND_READ_TRACK_EXEC;
					state <= COMMAND_SETUP;
				end
			end
			COMMAND_READ_TRACK_EXEC:
			begin
				state <= COMMAND_READ_RESULTS;
			end

			COMMAND_WRITE_DELETED_DATA:
			begin
				int_state <= 0;
				if (~old_wr & wr & a0) begin
					rw_deleted <= 1;
					command <= COMMAND_WRITE_DATA_EXEC;
					state <= COMMAND_SETUP;
				end
			end

			COMMAND_WRITE_DATA:
			begin
				int_state <= 0;
				m_status[UPD765_MAIN_CB] <= 1;
				if (~old_wr & wr & a0) begin
					rw_deleted <= 0;
					command <= COMMAND_WRITE_DATA_EXEC;
					state <= COMMAND_SETUP;
				end
			end

			COMMAND_WRITE_DATA_EXEC:
			begin
				state <= COMMAND_READ_RESULTS;
			end

			COMMAND_FORMAT_TRACK:
			begin
				int_state <= 0;
				m_status[UPD765_MAIN_CB] <= 1;
				state <= COMMAND_FORMAT_TRACK1;
			end
			COMMAND_FORMAT_TRACK1: //doesn't modify the media
			if (~old_wr & wr & a0) begin
				n <= din;
				state <= COMMAND_FORMAT_TRACK2;
			end
			COMMAND_FORMAT_TRACK2:
			if (~old_wr & wr & a0) begin
				sc <= din;
				state <= COMMAND_FORMAT_TRACK3;
			end
			COMMAND_FORMAT_TRACK3:
			if (~old_wr & wr & a0) begin
				gpl <= din;
				state <= COMMAND_FORMAT_TRACK4;
			end
			COMMAND_FORMAT_TRACK4:
			if (~old_wr & wr & a0) begin
				d <= din;
				state <= COMMAND_FORMAT_TRACK5;
			end
			COMMAND_FORMAT_TRACK5:
			if (!sc) begin
				state <= COMMAND_READ_RESULTS;
			end else	if (~old_wr & wr & a0) begin
				c <= din;
				state <= COMMAND_FORMAT_TRACK6;
			end
			COMMAND_FORMAT_TRACK6:
			if (~old_wr & wr & a0) begin
				h <= din;
				state <= COMMAND_FORMAT_TRACK7;
			end
			COMMAND_FORMAT_TRACK7:
			if (~old_wr & wr & a0) begin
				r <= din;
				state <= COMMAND_FORMAT_TRACK8;
			end
			COMMAND_FORMAT_TRACK8:
			if (~old_wr & wr & a0) begin
				n <= din;
				sc <= sc - 1'd1;
				r <= r + 1'd1;
				state <= COMMAND_FORMAT_TRACK5;
			end

			COMMAND_SCAN_EQUAL:
			begin
				int_state <= 0;
				if (~old_wr & wr & a0) begin
					state <= COMMAND_IDLE;
				end
			end

			COMMAND_SCAN_HIGH_OR_EQUAL:
			begin
				int_state <= 0;
				if (~old_wr & wr & a0) begin
					state <= COMMAND_IDLE;
				end
			end

			COMMAND_SCAN_LOW_OR_EQUAL:
			begin
				int_state <= 0;
				if (~old_wr & wr & a0) begin
					state <= COMMAND_IDLE;
				end
			end

			COMMAND_SETUP:
			if (!old_wr & wr & a0) begin
				case (substate)
					0: begin
							c <= din;
							substate <= 1;
						end
					1:	begin
							h <= din;
							substate <= 2;
						end
					2: begin
							r <= din;
							substate <= 3;
						end
					3: begin
							n <= din;
							substate <= 4;
						end
					4: begin
							eot <= din;
							substate <= 5;
						end
					5:	begin
							gpl <= din;
							substate <= 6;
						end
					6: begin
							dtl <= din;
							state <= command;
							substate <= 0;
						end
					7: ;//not happen
				endcase
			end

			COMMAND_READ_RESULTS:
			begin
				m_status[UPD765_MAIN_RQM] <= 1;
				m_status[UPD765_MAIN_DIO] <= 1;
				if (~old_rd & rd & a0) begin
					case (substate)
						0: begin
								dout <= status[0];
								substate <= 1;
							end
						1: begin
								dout <= status[1];
								substate <= 2;
							end
						2: begin
								dout <= status[2];
								substate <= 3;
							end
						3: begin
								dout <= sector_c;
								substate <= 4;
							end
						4: begin
								dout <= sector_h;
								substate <= 5;
							end
						5: begin
								dout <= sector_r;
								substate <= 6;
							end
						6: begin
								dout <= sector_n;
								state <= COMMAND_IDLE;
							end
						7: ;//not happen
					endcase
				end
			end

			COMMAND_INVALID:
			begin
				int_state <= 0;
				m_status[UPD765_MAIN_DIO] <= 1;
				status[0] <= 8'h80;
				state <= COMMAND_INVALID1;
			end
			COMMAND_INVALID1:
			if (~old_rd & rd & a0) begin
				state <= COMMAND_IDLE;
				dout <= status[0];
			end

		endcase //status

		if (~old_rd & rd & ~a0) begin //read main status register
			dout <= m_status;
		end
	end
end

endmodule