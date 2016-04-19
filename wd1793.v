`default_nettype none

// ====================================================================
//                        VECTOR-06C FPGA REPLICA
//
//             Copyright (C) 2007,2008 Viacheslav Slavinsky
//
// This core is distributed under modified BSD license. 
// For complete licensing information see LICENSE.TXT.
// -------------------------------------------------------------------- 
//
// An open implementation of Vector-06C home computer
//
// Author: Viacheslav Slavinsky, http://sensi.org/~svo
// 
// Design File: wd1793.v
//
// This module approximates the inner workings of a WD1793 floppy disk
// controller to some minimal extent. Track read/write operations
// are not supported, other ops are mimicked only barely enough.
//
// --------------------------------------------------------------------
//
// Modified version by Sorgelig to work with image in RAM
//
//

module wd1793
(
	input        clk,			 // clock: e.g. 3MHz
	input        reset,	 	 // async reset
	input        ce,
	input        rd,			 // i/o read
	input        wr,			 // i/o write
	input  [1:0] addr,		 // i/o port addr
	input  [7:0] din,		    // i/o data in
	output [7:0] dout,		 // i/o data out
	output       drq,        // DMA request
	output       intrq,
	output       busy,

	// Sector buffer access signals
	input [19:0] buff_size,	 // buffer RAM size (currently not used)
	output[19:0] buff_addr,	 // buffer RAM address
	output       buff_read,	 // buffer RAM read enable
	output       buff_write, // buffer RAM write enable (not tested yet)
	input  [7:0] buff_din,   // buffer RAM data input
	output [7:0] buff_dout,  // buffer RAM data output

	input  [1:0] size_code,  // sector size code
	input        side,
	input        ready       // =1 - disk is present
);

// Possible track configs:
// 0: 26 x 128  = 3.3KB
// 1: 16 x 256  = 4.0KB
// 2:  9 x 512  = 4.5KB
// 3:  5 x 1024 = 5.0KB

assign dout  = q;
assign drq   = s_drq;
assign busy  = s_busy;
assign intrq = s_intrq;

assign buff_addr  = buff_a;
assign buff_read  = ((addr == A_DATA) && buff_rd);
assign buff_write = ((addr == A_DATA) && buff_wr);
assign buff_dout  = din;

reg   [7:0] sectors_per_track;
reg  [10:0] sector_size;
reg   [9:0] byte_addr;
reg  [19:0] buff_a;

wire  [7:0] dts = {disk_track[6:0], side};
always @* begin
	case(size_code)
		0: buff_a = {{1'b0, dts, 4'b0000} + {dts, 3'b000} + {dts, 1'b0} + wdstat_sector - 1'd1, byte_addr[6:0]};
		1: buff_a = {{dts, 4'b0000}       + wdstat_sector - 1'd1, byte_addr[7:0]};
		2: buff_a = {{dts, 3'b000}  + dts + wdstat_sector - 1'd1, byte_addr[8:0]};
		3: buff_a = {{dts, 2'b00}   + dts + wdstat_sector - 1'd1, byte_addr[9:0]};
	endcase
	case(size_code)
		0: sectors_per_track = 26;
		1: sectors_per_track = 16;
		2: sectors_per_track = 9;
		3: sectors_per_track = 5;
	endcase
	case(size_code)
		0: sector_size = 128;
		1: sector_size = 256;
		2: sector_size = 512;
		3: sector_size = 1024;
	endcase
end

// Register addresses				
parameter A_COMMAND	      = 0;
parameter A_STATUS	      = 0;
parameter A_TRACK 	      = 1;
parameter A_SECTOR	      = 2;
parameter A_DATA		      = 3;

// States
parameter STATE_READY 		= 0;	/* Initial, idle, sector data read */
parameter STATE_WAIT_READ	= 1;	/* wait until read operation completes -> STATE_READ_2/STATE_READY */
parameter STATE_WAIT			= 2;	/* NOP operation wait -> STATE_READY */
parameter STATE_ABORT		= 3;	/* Abort current command ($D0) -> STATE_READY */
parameter STATE_READ_2   	= 4;	/* Buffer-to-host: wait before asserting DRQ -> STATE_READ_3 */
parameter STATE_READ_3		= 5;	/* Buffer-to-host: load data into reg, assert DRQ -> STATE_READY */
parameter STATE_WAIT_WRITE	= 6;	/* wait until write operation completes -> STATE_READY */
parameter STATE_READ_1		= 7;	/* Buffer-to-host: increment data pointer, decrement byte count -> STATE_READ_2*/
parameter STATE_WRITE_1		= 8;	/* Host-to-buffer: wr = 1 -> STATE_WRITE_2 */
parameter STATE_WRITE_2		= 9;	/* Host-to-buffer: wr = 0, next addr -> STATE_WRITESECT/STATE_WAIT_WRITE */
parameter STATE_WRITESECT	= 10; /* Host-to-buffer: wait data from host -> STATE_WRITE_1 */
parameter STATE_READSECT	= 11; /* Buffer-to-host */
parameter STATE_WAIT_2		= 12;
parameter STATE_ENDCOMMAND	= 14; /* All commands end here -> STATE_ENDCOMMAND2 */

// State variables
reg   [7:0] wdstat_track;
reg   [7:0] wdstat_sector;
reg   [7:0] wdstat_datareg;
reg   [7:0] wdstat_command;			// command register
reg			wdstat_pending;			// command loaded, pending execution
reg 			wdstat_stepdirection;	// last step direction
reg			wdstat_multisector;		// indicates multisector mode

reg   [7:0] disk_track;					// "real" heads position
reg  [10:0]	data_rdlength;				// this many bytes to transfer during read/write ops
reg   [3:0] state;

// common status bits
reg			s_readonly = 0, s_crcerr;
reg			s_headloaded, s_seekerr, s_index;  // mode 1
reg			s_lostdata, s_wrfault; 			     // mode 2,3

// Command mode 0/1 for status register
reg 			cmd_mode;

// DRQ/BUSY are always going together
reg	[1:0]	s_drq_busy;
wire			s_drq  = s_drq_busy[1];
wire			s_busy = s_drq_busy[0];
reg         s_intrq;

// Status register
wire  [7:0] wdstat_status = cmd_mode == 0 ? 	
	{~ready, s_readonly, s_headloaded, s_seekerr, s_crcerr, !disk_track, s_index, s_busy | wdstat_pending} :
	{~ready, s_readonly, s_wrfault,    s_seekerr, s_crcerr, s_lostdata,  s_drq,   s_busy | wdstat_pending};
	
// Watchdog	
reg	      watchdog_set;
wire	      watchdog_bark;
watchdog	dogbert(.clk(clk), .cock(watchdog_set), .q(watchdog_bark));

reg   [7:0] read_addr[6];
reg   [7:0] q;
always @* begin
	case (addr)
		A_TRACK:  q = wdstat_track;
		A_SECTOR: q = wdstat_sector;
		A_STATUS: q = wdstat_status;
		A_DATA:	 q = (state == STATE_READY) ? wdstat_datareg : buff_rd ? buff_din : read_addr[byte_addr[2:0]];
	endcase
end

reg         buff_rd;
reg         buff_wr;

// Reusable expressions
wire 	    	wStepDir   = wdstat_command[6] ? wdstat_command[5] : wdstat_stepdirection;
wire  [7:0] wNextTrack = wStepDir ? disk_track - 8'd1 : disk_track + 8'd1;
wire [10:0]	wRdLengthMinus1 = data_rdlength - 1'b1;
wire [10:0]	wBuffAddrPlus1  = byte_addr + 1'b1;

wire        rde = rd & ce;
wire        wre = wr & ce;
always @(posedge clk or posedge reset) begin
	reg old_wr, old_rd;

	reg [2:0] cur_addr;
	reg       read_data;
	reg       write_data;
	reg       read_type;
	integer   wait_time;
	reg [3:0] read_timer;
	reg [9:0] seektimer;

	if(reset) begin
		read_data <= 0;
		write_data <= 0;
		wdstat_multisector <= 0;
		wdstat_stepdirection <= 0;
		disk_track <= 0;
		wdstat_track <= 0;
		wdstat_sector <= 0;
		data_rdlength <= 0;
		byte_addr <=0;
		{buff_rd,buff_wr} <= 0;
		wdstat_multisector <= 0;
		state <= STATE_READY;
		cmd_mode <= 0;
		{s_headloaded, s_seekerr, s_crcerr, s_intrq, s_index} <= 0;
		{s_wrfault, s_lostdata} <= 0;
		s_drq_busy <= 0;
		wdstat_pending <= 0;
		watchdog_set <= 0;
		seektimer <= 10'h3FF;
	end else begin
		old_wr <=wre;
		old_rd <=rde;

		if((!old_rd && rde) || (!old_wr && wre)) cur_addr <= addr;

		//Register read operations
		if(old_rd && !rde && (cur_addr == A_STATUS)) {s_intrq, s_index} <= 0;

		//end of data reading
		if(old_rd && !rde && (cur_addr == A_DATA)) read_data <=1;

		//end of data writing
		if(old_wr && !wre && (cur_addr == A_DATA)) write_data <=1;

		/* Register write operations */
		if (!old_wr & wre) begin
			case (addr)
				A_COMMAND:
					begin
						s_intrq <= 0;
						if(din[7:4] == 'hD) begin
							// interrupt
							cmd_mode <= 0;

							if (state != STATE_READY) state <= STATE_ABORT;
								else {s_wrfault,s_seekerr,s_crcerr,s_lostdata} <= 0;

						end else begin
							if(!wdstat_pending) begin
								wdstat_command <= din;
								wdstat_pending <= 1;
							end
						end
					end

				A_TRACK:  if (!s_busy) wdstat_track <= din;
				A_SECTOR: if (!s_busy) wdstat_sector <= din;
				A_DATA:   wdstat_datareg <= din;
			endcase
		end

		//////////////////////////////////////////////////////////////////
		// Generic state machine is described below, but some important //
		// transitions are defined within the read/write section.       //
		//////////////////////////////////////////////////////////////////

		/* Data transfer: buffer to host. Read stage 1: increment address */
		case (state) 

		/* Idle state or buffer to host transfer */
		STATE_READY:
			begin
				// handle command
				if (wdstat_pending) begin
					wdstat_pending <= 0;
					cmd_mode <= wdstat_command[7];		// keep cmd_mode for wdstat_status
					
					case (wdstat_command[7:4]) 
					4'h0: 	// RESTORE
						begin
							// head load as specified, index, track0
							s_headloaded <= wdstat_command[3];
							s_index <= 1;
							wdstat_track <= 0;
							disk_track <= 0;

							// some programs like it when FDC gets busy for a while
							s_drq_busy <= 2'b01;
							state <= STATE_WAIT;
						end
					4'h1:	// SEEK
						begin
							// set real track to datareg
							disk_track <= wdstat_datareg; 
							s_headloaded <= wdstat_command[3];
							s_index <= 1;
							
							// get busy 
							s_drq_busy <= 2'b01;
							state <= STATE_WAIT;
						end
					4'h2,	// STEP
					4'h3,	// STEP & UPDATE
					4'h4,	// STEP-IN
					4'h5,	// STEP-IN & UPDATE
					4'h6,	// STEP-OUT
					4'h7:	// STEP-OUT & UPDATE
						begin
							// if direction is specified, store it for the next time
							if (wdstat_command[6] == 1) wdstat_stepdirection <= wdstat_command[5]; // 0: forward/in
							
							// perform step 
							disk_track <= wNextTrack;
									
							// update TRACK register too if asked to
							if (wdstat_command[4]) wdstat_track <= wNextTrack;
								
							s_headloaded <= wdstat_command[3];
							s_index <= 1;

							// some programs like it when FDC gets busy for a while
							s_drq_busy <= 2'b01;
							state <= STATE_WAIT;
						end
					4'h8, 4'h9: // READ SECTORS
						// seek data
						// 4: m:	0: one sector, 1: until the track ends
						// 3: S: 	SIDE
						// 2: E:	some 15ms delay
						// 1: C:	check side matching?
						// 0: 0
						begin
							// side is specified in the secondary control register ($1C)
							s_drq_busy <= 2'b01;
							{s_wrfault,s_seekerr,s_crcerr,s_lostdata} <= 0;
							
							wdstat_multisector <= wdstat_command[4];
							data_rdlength <= sector_size;
							state <= STATE_WAIT_READ;
							read_type <=1;
						end
					4'hA, 4'hB: // WRITE SECTORS
						begin
							s_drq_busy <= 2'b11;
							{s_wrfault,s_seekerr,s_crcerr,s_lostdata} <= 0;
							wdstat_multisector <= wdstat_command[4];
							
							data_rdlength <= sector_size;
							byte_addr <= 0;
							write_data <= 0;
							buff_wr <= 1;

							state <= STATE_WRITESECT;
						end								
					4'hC:	// READ ADDRESS
						begin
							// track, side, sector, sector size code, 2-byte checksum (crc?)
							s_drq_busy <= 2'b01;
							{s_wrfault,s_seekerr,s_crcerr,s_lostdata} <= 0;

							wdstat_multisector <= 0;
							state <= STATE_WAIT_READ;
							data_rdlength <= 6;
							read_type <= 0;

							read_addr[0] <= disk_track;
							read_addr[1] <= {7'b0, side};
							read_addr[2] <= wdstat_sector;
							read_addr[3] <= size_code;
							read_addr[4] <= 0;
							read_addr[5] <= 0;
						end
					4'hE,	// READ TRACK
					4'hF:	// WRITE TRACK
						begin
							{s_wrfault,s_seekerr,s_crcerr,s_lostdata} <= 0;
							if(wdstat_command[4]) s_wrfault <= 1; // read-only
							s_drq_busy <= 2'b01;
							state <= STATE_WAIT;
						end
					default:s_drq_busy <= 2'b00;
					endcase
				end
			end

		STATE_WAIT_READ:
			begin
				if (!ready) begin
					// FAIL
					s_seekerr <= 1;
					s_crcerr <= 1;
					state <= STATE_ENDCOMMAND;
				end else begin
					seektimer <= seektimer - 1'b1;
					if(!seektimer) begin
						if(wdstat_multisector && (wdstat_sector > sectors_per_track)) begin
							if(wdstat_multisector) s_seekerr <= 1;
							wdstat_multisector <= 0;
							state <= STATE_ENDCOMMAND;
						end else begin
							buff_rd <= read_type;
							byte_addr <= 0;
							state <= STATE_READ_2;
						end
					end
				end
			end
		STATE_READ_1:
			begin
				// increment data pointer, decrement byte count
				byte_addr <= wBuffAddrPlus1[9:0];
				data_rdlength <= wRdLengthMinus1[9:0];
				state <= STATE_READ_2;
			end
		STATE_READ_2:
			begin
				watchdog_set <= 1;
				read_timer <= 4'b1111;
				state <= STATE_READ_3;
				s_drq_busy <= 2'b01;
			end
		STATE_READ_3:
			begin
				if (read_timer != 0) 
					read_timer <= read_timer - 1'b1;
				else begin
					read_data <= 0;
					watchdog_set <= 0;
					s_lostdata <= 0;
					s_drq_busy <= 2'b11;
					state <= STATE_READSECT;
				end
			end
		STATE_READSECT:
			begin
				// lose data if not requested in time
				//if (s_drq && watchdog_bark) begin
				//	s_lostdata <= 1'b1;
				//	s_drq_busy <= 2'b01;
				//	state <= data_rdlength != 0 ? STATE_READ_1 : STATE_ABORT;
				//end

				if (watchdog_bark || (read_data && s_drq)) begin
					// reset drq until next byte is read, nothing is lost
					s_drq_busy <= 2'b01;
					s_lostdata <= watchdog_bark;
					
					if (wRdLengthMinus1 == 0) begin
						// either read the next sector, or stop if this is track end
						if (wdstat_multisector) begin
							wdstat_sector <= wdstat_sector + 1'b1;
							data_rdlength <= sector_size;
							state <= STATE_WAIT_READ;
						end else begin
							if(wdstat_multisector) s_seekerr <= 1;
							wdstat_multisector <= 0;
							state <= STATE_ENDCOMMAND;
						end
					end else begin
						// everything is okay, fetch next byte
						state <= STATE_READ_1;
					end
				end
			end

		STATE_WAIT_WRITE:
			begin
				if (!ready) begin
					s_wrfault <= 1;
					state <= STATE_ENDCOMMAND;
				end else begin
					if (wdstat_multisector && wdstat_sector < sectors_per_track) begin
						wdstat_sector <= wdstat_sector + 1'b1;
						s_drq_busy <= 2'b11;
						data_rdlength <= sector_size;
						byte_addr <= 0;
						state <= STATE_WRITESECT;
					end else begin
						wdstat_multisector <= 0;
						state <= STATE_ENDCOMMAND;
					end
				end
			end
		STATE_WRITESECT:
			begin
				if (write_data) begin
					s_drq_busy <= 2'b01;			// busy, clear drq
					s_lostdata <= 0;
					state <= STATE_WRITE_2;
					write_data <= 0;
				end
			end
		STATE_WRITE_2:
			begin
				// increment data pointer, decrement byte count
				byte_addr <= wBuffAddrPlus1[9:0];
				data_rdlength <= wRdLengthMinus1;
								
				if (wRdLengthMinus1 == 0) begin
					// Flush data --
					state <= STATE_WAIT_WRITE;
				end else begin
					s_drq_busy <= 2'b11;		// request next byte
					state <= STATE_WRITESECT;
				end				
			end

		// Abort current operation ($D0)
		STATE_ABORT:
			begin
				data_rdlength <= 0;
				wdstat_pending <= 0;
				state <= STATE_ENDCOMMAND;
			end

		STATE_WAIT:
			begin
				wait_time = 4000;
				state <= STATE_WAIT_2;
			end
		STATE_WAIT_2:
			begin
				if(wait_time) wait_time <= wait_time - 1;
					else state <= STATE_ENDCOMMAND;
			end

		// End any command.
		STATE_ENDCOMMAND:
			begin
				{buff_rd,buff_wr} <= 0;
				state <= STATE_READY;
				s_drq_busy <= 2'b00;
				seektimer <= 10'h3FF;
				s_intrq <= 1;
			end
		endcase
	end
end
endmodule


// start ticking when cock goes down
module watchdog
(
	input  clk, 
	input  cock,
	output q
);

parameter TIME = 16'd2048; // 2048 seems to work better than expected 100 (32us).. why?
assign q = (timer == 0);

reg [15:0] timer;
always @(posedge clk) begin
	if (cock) begin
		timer <= TIME;
	end else begin
		if (timer != 0) timer <= timer - 1'b1;
	end
end

endmodule
