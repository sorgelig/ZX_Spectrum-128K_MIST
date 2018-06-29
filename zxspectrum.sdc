#************************************************************
# THIS IS A WIZARD-GENERATED FILE.                           
#
# Version 13.1.4 Build 182 03/12/2014 SJ Full Version
#
#************************************************************

# Copyright (C) 1991-2014 Altera Corporation
# Your use of Altera Corporation's design tools, logic functions 
# and other software and tools, and its AMPP partner logic 
# functions, and any output files from any of the foregoing 
# (including device programming or simulation files), and any 
# associated documentation or information are expressly subject 
# to the terms and conditions of the Altera Program License 
# Subscription Agreement, Altera MegaCore Function License 
# Agreement, or other applicable license agreement, including, 
# without limitation, that your use is for the sole purpose of 
# programming logic devices manufactured by Altera and sold by 
# Altera or its authorized distributors.  Please refer to the 
# applicable agreement for further details.



# Clock constraints

create_clock -name "CLOCK_27" -period 37.037 [get_ports {CLOCK_27}]
create_clock -name {SPI_SCK}  -period 41.666 -waveform { 20.8 41.666 } [get_ports {SPI_SCK}]

# Automatically constrain PLL and other generated clocks
derive_pll_clocks -create_base_clocks

# Automatically calculate clock uncertainty to jitter and other effects.
derive_clock_uncertainty

# Clock groups
set_clock_groups -asynchronous -group [get_clocks {SPI_SCK}] -group [get_clocks {pll|altpll_component|auto_generated|pll1|clk[0]}]

# SDRAM delays
set_input_delay -clock [get_clocks {pll|altpll_component|auto_generated|pll1|clk[0]}] -max 6.4 [get_ports SDRAM_DQ[*]]
set_input_delay -clock [get_clocks {pll|altpll_component|auto_generated|pll1|clk[0]}] -min 3.2 [get_ports SDRAM_DQ[*]]

set_output_delay -clock [get_clocks {pll|altpll_component|auto_generated|pll1|clk[0]}] -max 1.5 [get_ports {SDRAM_D* SDRAM_A* SDRAM_BA* SDRAM_n* SDRAM_CKE}]
set_output_delay -clock [get_clocks {pll|altpll_component|auto_generated|pll1|clk[0]}] -min -0.8 [get_ports {SDRAM_D* SDRAM_A* SDRAM_BA* SDRAM_n* SDRAM_CKE}]

# Effective clock is only half of the system clock, so allow 2 clock cycles for the paths in the T80 cpu
set_multicycle_path -from {T80pa:cpu|T80:u0|*} -setup 2
set_multicycle_path -from {T80pa:cpu|T80:u0|*} -hold 2

# The CE is only active in every 2 clocks, so allow 2 clock cycles
set_multicycle_path -to {smart_tape:tape|tape:tape|addr[*]} -setup 2
set_multicycle_path -to {smart_tape:tape|tape:tape|addr[*]} -hold 2
set_multicycle_path -to {smart_tape:tape|tape:tape|read_cnt[*]} -setup 2
set_multicycle_path -to {smart_tape:tape|tape:tape|read_cnt[*]} -hold 2
set_multicycle_path -to {smart_tape:tape|tape:tape|blocksz[*]} -setup 2
set_multicycle_path -to {smart_tape:tape|tape:tape|blocksz[*]} -hold 2
set_multicycle_path -to {smart_tape:tape|tape:tape|timeout[*]} -setup 2
set_multicycle_path -to {smart_tape:tape|tape:tape|timeout[*]} -hold 2
set_multicycle_path -to {smart_tape:tape|tape:tape|pilot[*]} -setup 2
set_multicycle_path -to {smart_tape:tape|tape:tape|pilot[*]} -hold 2
set_multicycle_path -to {smart_tape:tape|tape:tape|tick[*]} -setup 2
set_multicycle_path -to {smart_tape:tape|tape:tape|tick[*]} -hold 2
set_multicycle_path -to {smart_tape:tape|tape:tape|blk_list[*]} -setup 2
set_multicycle_path -to {smart_tape:tape|tape:tape|blk_list[*]} -hold 2
set_multicycle_path -to {smart_tape:tape|tape:tape|bitcnt[*]} -setup 2
set_multicycle_path -to {smart_tape:tape|tape:tape|bitcnt[*]} -hold 2

# The effective clock fo the AY chips are 112/1.75=64 cycles, so allow at least 2 cycles for the paths
set_multicycle_path -to {turbosound:turbosound|ym2149:*} -setup 2
set_multicycle_path -to {turbosound:turbosound|ym2149:*} -hold 2

set_multicycle_path -from {wd1793:fdd|wd1793_dpram:sbuf|*} -setup 2
set_multicycle_path -from {wd1793:fdd|wd1793_dpram:sbuf|*} -hold 2

set_multicycle_path -from {wd1793:fdd|altsyncram:edsk_rtl_0|*} -setup 2
set_multicycle_path -from {wd1793:fdd|altsyncram:edsk_rtl_0|*} -hold 2

set_multicycle_path -to {wd1793:fdd|state[*]} -setup 2
set_multicycle_path -to {wd1793:fdd|state[*]} -hold 2
set_multicycle_path -to {wd1793:fdd|wait_time[*]} -setup 2
set_multicycle_path -to {wd1793:fdd|wait_time[*]} -hold 2

set_multicycle_path -from {u765:u765|u765_dpram:sbuf|*} -setup 2
set_multicycle_path -from {u765:u765|u765_dpram:sbuf|*} -hold 2

set_multicycle_path -from {u765:u765|altsyncram:image_track_offsets_rtl_0|*} -setup 2
set_multicycle_path -from {u765:u765|altsyncram:image_track_offsets_rtl_0|*} -hold 2

set_multicycle_path -to {u765:u765|seek_pos[*]} -setup 2
set_multicycle_path -to {u765:u765|seek_pos[*]} -hold 2
set_multicycle_path -to {u765:u765|state[*]} -setup 2
set_multicycle_path -to {u765:u765|state[*]} -hold 2
set_multicycle_path -to {u765:u765|status[*]} -setup 2
set_multicycle_path -to {u765:u765|status[*]} -hold 2
set_multicycle_path -to {u765:u765|image_track_offsets_addr[*]} -setup 2
set_multicycle_path -to {u765:u765|image_track_offsets_addr[*]} -hold 2
set_multicycle_path -to {u765:u765|buff_addr[*]} -setup 2
set_multicycle_path -to {u765:u765|buff_addr[*]} -hold 2

# False paths

# Don't bother optimizing Hq2x and sigma_delta_dac
set_false_path -to {video:video|video_mixer:video_mixer|scandoubler:scandoubler|Hq2x:Hq2x|*}
set_false_path -to {sigma_delta_dac:*}

set_false_path -to [get_ports {VGA_*}]
set_false_path -to [get_ports {AUDIO_L}]
set_false_path -to [get_ports {AUDIO_R}]
set_false_path -to [get_ports {LED}]
set_false_path -from [get_ports {UART_RX}]