// ZX Spectrum for Altera DE1
//
// Copyright (c) 2009-2011 Mike Stirling
//
// All rights reserved
//
// Redistribution and use in source and synthezised forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// * Redistributions of source code must retain the above copyright notice,
//   this list of conditions and the following disclaimer.
//
// * Redistributions in synthesized form must reproduce the above copyright
//   notice, this list of conditions and the following disclaimer in the
//   documentation and/or other materials provided with the distribution.
//
// * Neither the name of the author nor the names of other contributors may
//   be used to endorse or promote products derived from this software without
//   specific prior written agreement from the author.
//
// * License is granted for non-commercial use only.  A fee may not be charged
//   for redistributions as source code or in synthesized/hardware form without 
//   specific prior written agreement from the author.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
// THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//

module video2(
    // Video clock (14 MHz)
    input            CLK,
    input            nRESET,
    
    // Mode
    input            scandoubler_disable,
    
    // Memory interface
    output    [12:0] vram_address,
    input      [7:0] vram_data,
    
    // IO interface
    input      [2:0] border,
    
    // Video outputs
    output reg [5:0] VGA_R,
    output reg [5:0] VGA_G,
    output reg [5:0] VGA_B,
    output           VGA_VS,
    output           VGA_HS,
    output           VGA_VS_OSD,
    output           VGA_HS_OSD,
    
    // Interrupt to CPU (asserted for 32 T-states, 64 ticks)
    output reg       vs_nintr = 1
);

    reg [9:0] pixels = 0;
    reg [7:0] attr = 0;
    
    // additional buffer used in non-VGA mode (TV) to store the pixels/attr a little
    // bit ahead of time to not interfere with cpu ram access
    reg [7:0] pixels_tv;
    reg [7:0] attr_tv;
    
    // Video logic runs at 14 MHz so hcounter has an additonal LSb which is
    // skipped if running in VGA scan-doubled mode.  The value of this
    // extra bit is 1/2 for the purposes of timing calculations bit 1 is
    // assumed to have a value of 1.
    reg [9:0] hcounter = 0;
    // vcounter has an extra LSb as well except this is skipped if running
    // in PAL mode.  By not skipping it in VGA mode we get the required
    // double-scanning of each line.  This extra bit has a value 1/2 as well.
    reg [9:0] vcounter = 0;
    reg [4:0] flashcounter = 0;
    reg       vblanking = 0;
    reg       hblanking = 0;
    reg       hpicture = 0;
    wire      vpicture;
    wire      picture;
    wire      blanking;

    reg       hsync = 0;
    reg       vsync = 0;

    wire      red;
    wire      green;
    wire      blue;
    wire      bright;
    wire      dot;

    // The first 256 pixels of each line are valid picture
    assign picture = hpicture & vpicture;
    assign blanking = hblanking | vblanking;
    
    // Output syncs
    // drive VSYNC to 1 in PAL mode for Minimig VGA cable
    assign VGA_VS = (!scandoubler_disable) ? (~vsync) : 1'b1;
    assign VGA_HS = (!scandoubler_disable) ? (~hsync) : (~(vsync ^ hsync));

    assign VGA_VS_OSD = (~vsync);
    assign VGA_HS_OSD = (~hsync);
    
    // Determine the pixel colour
    assign dot = pixels[9] ^ (flashcounter[4] && attr[7]);		// Combine delayed pixel with FLASH attr and clock state
    assign red = ((picture == 1'b1) && (dot == 1'b1)) ? attr[1] : 
                 ((picture == 1'b1) && (dot == 1'b0)) ? attr[4] : 
                 (blanking == 1'b0) ? border[1] : 
                 1'b0;
    assign green = ((picture == 1'b1) && (dot == 1'b1)) ? attr[2] : 
                   ((picture == 1'b1) && (dot == 1'b0)) ? attr[5] : 
                   (blanking == 1'b0) ? border[2] : 
                   1'b0;
    assign blue = ((picture == 1'b1) && (dot == 1'b1)) ? attr[0] : 
                  ((picture == 1'b1) && (dot == 1'b0)) ? attr[3] : 
                  (blanking == 1'b0) ? border[0] : 
                  1'b0;
    assign bright = (picture == 1'b1) ? attr[6] : 
                    1'b0;
    
    // Re-register video output to DACs to clean up edges
    always @(posedge CLK) begin
        // Output video to DACs
        VGA_R <= {red,   red,   bright & red,   bright & red,   bright & red,   bright & red  };
        VGA_G <= {green, green, bright & green, bright & green, bright & green, bright & green};
        VGA_B <= {blue,  blue,  bright & blue,  bright & blue,  bright & blue,  bright & blue };
	 end

    // This is what the contention model is supposed to look like.
    // We may need to emulate this to ensure proper compatibility.
    //
    // At vcounter = 0 and hcounter = 0 we are at
    // 14336*T since the falling edge of the vsync.
    // This is where we start contending RAM access.
    // The contention pattern repeats every 8 T states, with
    // CPU clock held during the first 6 of every 8 T states
    // (where one T state is two ticks of the horizontal counter).
    // Two screen bytes are fetched consecutively, display first
    // followed by attribute.  The cycle looks like this:
    // hcounter[3..1] = 000 Fetch data 1  nWAIT = 0
    //                  001 Fetch attr 1          0
    //                  010 Fetch data 2          0
    //                  011 Fetch attr 2          0
    //                  100                       1
    //                  101                       1
    //                  110                       0
    //                  111                       0

    // What we actually do is the following, interleaved with CPU RAM access
    // so that we don't need any contention:
    // hcounter[2..0] = 000 Fetch data (LOAD)
    //					001 Fetch data (STORE)
    //					010 Fetch attr (LOAD)
    //					011 Fetch attr (STORE)
    //					100 Idle
    //					101 Idle
    //					110 Idle
    //					111 Idle
    // The load/store pairs take place over two clock enables.  In VGA mode
    // there is one picture/attribute pair fetch per CPU clock enable.  In PAL
    // mode every other tick is ignored, so the picture/attribute fetches occur
    // on alternate CPU clocks.  At no time must a CPU cycle be allowed to split
    // a LOAD/STORE pair, as the bus routing logic will disconnect the memory from
    // the CPU during this time.

    // RAM address is generated continuously from the counter values
    // Pixel fetch takes place when hcounter(2) = 0, attribute when = 1
    assign vram_address[12:0] = ((!scandoubler_disable && (hcounter[2] == 1'b0)) || (scandoubler_disable && (hcounter[1] == 1'b0))) ? 
	                             {vcounter[8:7], vcounter[3:1], vcounter[6:4], hcounter[8:4]} : 
                                {3'b110, vcounter[8:7], vcounter[6:4], hcounter[8:4]};
    
    // First 192 lines are picture
    assign vpicture = (~(vcounter[9] || (vcounter[8] && vcounter[7])));

    always @(posedge CLK) begin
            // Most functions are only performed when hcounter(0) is clear.
            // This is the 'half' bit inserted to allow for scan-doubled VGA output.
            // In VGA mode the counter will be stepped through the even values only,
            // so the rest of the logic remains the same.
            if ((vpicture == 1'b1) && (hcounter[0] == 1'b1)) begin
                // Pump pixel shift register - this is two pixels longer
                // than a byte to delay the pixels back into alignment with
                // the attribute byte, stored two ticks later
                pixels[9:1] <= pixels[8:0];

                // in TV mode everything happens a little slower. Fetch data ahead of
                // time to have the same memory timing as VGA
                if ((hcounter[9] == 1'b0) && (hcounter[3] == 1'b0)) begin
                    if (hcounter[2] == 1'b0) begin
                        if (hcounter[1] == 1'b0) pixels_tv <= vram_data;
									else attr_tv <= vram_data;
                    end
                end

                if ((hcounter[9] == 1'b0) && (hcounter[3] == 1'b0)) begin
                    // Handle the fetch cycle
                    // 3210
                    // 0000 PICTURE LOAD
                    // 0010 PICTURE STORE
                    // 0100 ATTR LOAD
                    // 0110 ATTR STORE				
                    if (hcounter[1] == 1'b1) begin
                        // STORE
                        if (hcounter[2] == 1'b0) begin
                            // PICTURE
                            if (!scandoubler_disable) pixels[7:0] <= vram_data;
										else pixels[7:0] <= pixels_tv;
                        end else begin
                            // ATTR
                            if (!scandoubler_disable) attr <= vram_data;
										else attr <= attr_tv;
							   end
                    end
                end

                // Delay horizontal picture enable until the end of the first fetch cycle
                // This also allows for the re-registration of the outputs
                if ((hcounter[9] == 1'b0) && (hcounter[2:1] == 2'b11)) hpicture <= 1'b1;
                if ((hcounter[9] == 1'b1) && (hcounter[2:1] == 2'b11)) hpicture <= 1'b0;
            end

            // Step the horizontal counter and check for wrap
            if (!scandoubler_disable) begin
                // Counter wraps after 894 in VGA mode
                if (hcounter == 10'b1101111111) begin
                    hcounter <= 10'b0000000000;
                    // Increment vertical counter by ones for VGA so that
                    // lines are double-scanned
                    vcounter <= vcounter + 1'b1;
                end else begin
                    // Increment horizontal counter
                    // Even values only for VGA mode
                    hcounter <= hcounter + 2'b10;
                end
                hcounter[0] <= 1'b1;
            end else begin
                // Counter wraps after 895 in PAL mode
                if (hcounter == 10'b1101111111) begin
                    hcounter <= 10'b0000000000;
                    // Increment vertical counter by even values for PAL
                    vcounter <= vcounter + 2'b10;
                    vcounter[0] <= 1'b0;
                end else begin
                    // Increment horizontal counter
                    // All values for PAL mode
                    hcounter <= hcounter + 1'b1;
					 end
            end
            //------------------
            // HORIZONTAL
            //------------------
            
            // Each line comprises the following:
            // 256 pixels of active image
            // 48 pixels right border
            // 24 pixels front porch
            // 32 pixels sync
            // 40 pixels back porch
            // 48 pixels left border

            // Generate timing signals during inactive region
            // (when hcounter(9) = 1)
            case (hcounter[9:4])
                // Blanking starts at 304
                6'b100110 : hblanking <= 1'b1;
                // Sync starts at 328
                6'b101001 : hsync <= 1'b1;
                // Sync ends at 360
                6'b101101 : hsync <= 1'b0;
                // Blanking ends at 400
                6'b110010 : hblanking <= 1'b0;
            endcase

            // Clear interrupt after 32T
            if (hcounter[7] == 1'b1) vs_nintr <= 1'b1;
            
            //--------------
            // VERTICAL
            //--------------

            case (vcounter[9:3])
                7'b0111110 : begin
                        // Start of blanking and vsync(line 248)
                        vblanking <= 1'b1;
                        vsync <= 1'b1;
                        // Assert vsync interrupt
                        vs_nintr <= 1'b0;
                    end
                // End of vsync after 4 lines (line 252)
                7'b0111111 : vsync <= 1'b0;

                // End of blanking and start of top border (line 256)
                // Should be line 264 but this is simpler and doesn't really make
                // any difference
                7'b1000000 : vblanking <= 1'b0;
            endcase

            // Wrap vertical counter at line 312-1,
            // Top counter value is 623 for VGA, 622 for PAL
            if (vcounter[9:1] == 9'b100110111) begin
                if ((!scandoubler_disable && (vcounter[0] == 1'b1) && (hcounter == 10'b1101111111)) || (scandoubler_disable && (hcounter == 10'b1101111111))) begin
                    // Start of picture area
                    vcounter <= 10'b0000000000;
                    // Increment the flash counter once per frame
                    flashcounter <= flashcounter + 1'b1;
                end
            end
    end
endmodule
