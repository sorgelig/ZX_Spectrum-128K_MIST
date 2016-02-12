# ZX Spectrum 128K for [MIST Board](https://github.com/mist-devel/mist-board/wiki)

Some verilog models from Till Harbaum [Spectrum](https://github.com/mist-devel/mist-board/tree/master/cores/spectrum) core were used in this project.

### Features:
- Fully functional ZX Spectrum 48K, 128K and Pentagon 128 with correct CPU and Video timings
- DivMMC with [ESXDOS](http://www.esxdos.org/) (TAP, TRD, SNA files)
- Original Tape loading through OSD (CSW files)

### Installation:
Copy the *.rbf file at the root of the SD card. You can rename the file to core.rbf if you want the MiST to load it automatically at startup.
Copy [spectrum.rom](https://github.com/sorgelig/ZX_Spectrum-128K_MIST/tree/master/releases/spectrum.rom) file to the root of SD card.

For PAL mode (RGBS output) you need to put [mist.ini](https://github.com/sorgelig/ZX_Spectrum-128K_MIST/tree/master/releases/mist.ini) file to the root of SD card. Set the option **scandoubler_disable** for desired video output.

For ESXDOS functionality you need to put SYS and BIN folders from [esxdos085.zip](http://www.esxdos.org/files/esxdos085.zip) to the root of SD card.
First press of F11 key will load and initialize ESXDOS, subsequent presses will open ESXDOS manager.

Press F12 to access OSD menu, 
F11 for ESXDOS, Ctrl+F11 for warm reset, Alt+F11 for cold reset.

### Download precompiled binaries and system ROMs:
Go to [releases](https://github.com/sorgelig/ZX_Spectrum-128K_MIST/tree/master/releases) folder.
