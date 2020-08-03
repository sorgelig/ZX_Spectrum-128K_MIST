//Fake CPU
/* verilator lint_off MULTIDRIVEN */

module CPU (
	input         reset,
	input         clk_neg,
	input         clk_pos,
	input         ce_n,
	input         ce_p,
	output [15:0] cpu_addr,
	output  [7:0] cpu_dout,
	input   [7:0] cpu_din,
	output reg    nMREQ,
	output reg    nIORQ,
	input         nINT,
	output reg    nRD,
	output reg    nWR,
	output reg    nM1,
	output reg    nRFSH
);

reg [2:0] MCycle, MCycles;
reg [2:0] TState, TStates;

reg [15:0] A;

assign cpu_addr = A;

always @(posedge clk_pos, posedge reset) begin
	if (reset) begin
		MCycle <= 5;
		MCycles <= 5;
		TState <= 1;
		TStates <= 4;
		A <= 16'h0000;
		nMREQ <= 1;
		nIORQ <= 1;
		nRD <= 1;
		nWR <= 1;
		nM1 <= 0;
		nRFSH <= 1;
	end else if (ce_p)  begin

		if (TState == TStates) begin
			TState <= 1;
			if (MCycle == MCycles)
				MCycle <= 1;
			else
				MCycle <= MCycle + 1'd1;
		end else begin
			TState <= TState + 1'd1;
		end

		case (MCycle)
		1: // contented M1
			case (TState)
				2: begin {nMREQ, nRD, nM1} <= 3'b111; nRFSH <= 0; A<=16'h6000; end
				4: begin nRFSH <= 1; A<=16'hFFFF; TStates <= 6; end
			default: ;
			endcase

		2:
			case (TState)
			6: begin A<=16'h00FE; TStates <= 4; end
			default: ;
			endcase

		3: // contented IO
			case (TState)
			1: begin nIORQ <= 0; nRD <= 0; end
			4: begin A<=16'hFFFF; TStates <= 5; end
			default: ;
			endcase

		4:
			case (TState)
			5: TStates <= 4;
			default: ;
			endcase

		5:
			case (TState)
				4: begin A<=16'h4000; TStates <= 4; end
			default: ;
			endcase

			default: ;
			endcase

	end
end

// M1 cycle
always @(posedge clk_neg) begin
	if (ce_n) case (MCycle)

	1:
		case (TState)
		1: {nMREQ, nRD} <= 0;
		3: nMREQ <= 0;
		4: nMREQ <= 1;
		default: ;
		endcase

	2: ;

	3:
		case (TState)
		4: {nIORQ, nRD} <= 2'b11;
		default: ;
		endcase

	4: ;
	5: ;
	default: ;
	endcase
end

/* verilator lint_on MULTIDRIVEN */

endmodule
