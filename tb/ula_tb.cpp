#include <stdlib.h>
#include <iostream>
#include <fstream>
#include <iomanip>
#include "Vula_test.h"
#include "verilated.h"
#include "verilated_vcd_c.h"


static Vula_test *tb;
static VerilatedVcdC *trace;
static int tickcount;
static int phase;

static unsigned char ram[16*1024];

void initram() {
	FILE *file=fopen("test.scr", "rb");
	fread(&ram, 16, 1024, file);
	fclose(file);
}

void tick(int c) {

	tb->clk_sys = c;
	tb->eval();
	trace->dump(tickcount++);

	// VRAM read
	if (c) tb->vram_dout = ram[tb->vram_addr];
}

int main(int argc, char **argv) {

	int frames = 0;
	int hsync,vsync;

	// Initialize Verilators variables
	Verilated::commandArgs(argc, argv);
//	Verilated::debug(1);
	Verilated::traceEverOn(true);
	trace = new VerilatedVcdC;
	tickcount = 0;
	phase = 0;

	// Initialize RAM
	initram();

	// Create an instance of our module under test
	tb = new Vula_test;
	tb->trace(trace, 99);
	trace->open("ula.vcd");

	tick(1);
	tick(0);
	tb->reset = 1;
	tb->mZX = 1;
	tb->m128 = 0;
	tb->border_color = 1;
	tick(1);
	tick(0);

	tb->reset = 0;

	FILE *file=fopen("video.rgb", "wb");
	unsigned short rgb;

	while(frames<3) {
		vsync = tb->VSync;
		hsync = tb->HSync;
		tick(1);
		tick(0);

		if (!tb->VSync && vsync) {
			frames++;
//			write_crtc(3,128+2+frames);
		}
		if (frames == 2 && tb->ce_vid) {
			if (tb->VSync) rgb = 0x00f0;
			else if (tb->HSync) rgb = 0x0f00;
			else rgb = tb->Rx*256 + tb->Gx*16 + tb->Bx;
			fwrite(&rgb, 1, sizeof(rgb), file);
		};
	};

	fclose(file);
	trace->close();
}
