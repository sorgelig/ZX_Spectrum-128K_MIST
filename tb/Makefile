OBJ_DIR=obj_dir
VERILATOR_DIR=/usr/local/share/verilator/include
#VERILATOR_DIR=/usr/share/verilator/include
VERILATOR_BIN=/usr/local/bin/verilator
#VERILATOR_BIN=/usr/bin/verilator
#VERILATOR_DIR=${HOME}/verilator/include
#VERILATOR_BIN=${HOME}/verilator/bin/verilator
HDL_FILES = ula_test.v cpu.v ula_async.sv ../ula.sv

all: ula_tb

${OBJ_DIR}/Vula_tb.cpp: ${HDL_FILES}
	${VERILATOR_BIN} --trace --top-module ula_test -cc ${HDL_FILES}

ula_tb: ${OBJ_DIR}/Vula_tb.cpp ula_tb.cpp
	g++ -I $(OBJ_DIR) -I$(VERILATOR_DIR) $(VERILATOR_DIR)/verilated.cpp $(VERILATOR_DIR)/verilated_vcd_c.cpp ula_tb.cpp  $(OBJ_DIR)/Vula_test__Trace.cpp $(OBJ_DIR)/Vula_test__Trace__Slow.cpp $(OBJ_DIR)/Vula_test.cpp $(OBJ_DIR)/Vula_test__Syms.cpp -DOPT=-DVL_DEBUG -o ula_tb

video: video.png

video.png: video.rgb
	rm -f video.png
	ffmpeg -vcodec rawvideo -f rawvideo -pix_fmt rgb444 -s 448x312 -i video.rgb -f image2 -vcodec png video.png
	display video.png
