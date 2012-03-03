// J1 FORTH CPU
// http://excamera.com/sphinx/fpga-j1.html

// changes from the original
// - programing interface (pgm_addr,data,we) added
// - generic dualsyncram plumbed in (altera fpga friendly)
// - use width specifiers on constants to make altera tools happier
// - reindented w/ hardtabs and various tidying up
// - use J0-style memory interface
// - parameterize PC (max 13) and SP (3-8) widths
// - add J0-style pause signal

`timescale 1ns/1ns

module j1 #(
	parameter SP_BITS=5,
	parameter PC_BITS=13
	) (
	input sys_clk_i,
	input sys_rst_i,
	input pause,

	output [PC_BITS-1:0] insn_addr,
	input [15:0] insn,

	output io_rd,
	output io_wr,
	output [15:0] io_addr,
	output [15:0] io_dout,
	input [15:0] io_din
	);

assign insn_addr = _pc;

wire [15:0] immediate = { 1'b0, insn[14:0] };

reg [PC_BITS-1:0] pc, _pc;	// Program Counter
reg [SP_BITS-1:0] dsp, _dsp;	// Data stack pointer
reg [SP_BITS-1:0] rsp, _rsp;	// Return stack pointer
reg [15:0] st0, _st0;		// Data stack top register

wire _dstkW;			// D stack write
reg _rstkW;			// R stack write
wire _ramWE;			// RAM write enable

reg [15:0] _rstkD;

wire [PC_BITS-1:0] pc_plus_1;
assign pc_plus_1 = pc + 1;

// The D and R stacks
reg [15:0] dstack[0:SP_BITS**2-1];
reg [15:0] rstack[0:SP_BITS**2-1];
always @(posedge sys_clk_i)
begin
	if (_dstkW)
		dstack[_dsp] = st0;
	if (_rstkW)
		rstack[_rsp] = _rstkD;
end

wire [15:0] st1 = dstack[dsp];
wire [15:0] rst0 = rstack[rsp];

// st0sel is the ALU operation.
// For branch and call the operation is T, for 0branch it is N.
// For ALU ops it is loaded from the instruction field.
reg [3:0] st0sel;
always @*
begin
	case (insn[14:13])
	2'b00: st0sel = 0;		// ubranch
	2'b10: st0sel = 0;		// call
	2'b01: st0sel = 1;		// 0branch
	2'b11: st0sel = insn[11:8];	// ALU
	endcase
end

// Compute the new value of T.
always @*
begin
	if (insn[15])
		_st0 = immediate;
	else
		case (st0sel)
		4'b0000: _st0 = st0;
		4'b0001: _st0 = st1;
		4'b0010: _st0 = st0 + st1;
		4'b0011: _st0 = st0 & st1;
		4'b0100: _st0 = st0 | st1;
		4'b0101: _st0 = st0 ^ st1;
		4'b0110: _st0 = ~st0;
		4'b0111: _st0 = { 16{ (st1 == st0) } };
		4'b1000: _st0 = { 16{ ($signed(st1) < $signed(st0)) } };
		4'b1001: _st0 = st1 >> st0[3:0];
		4'b1010: _st0 = st0 - 16'd1;
		4'b1011: _st0 = rst0;
		4'b1100: _st0 = io_din;
		4'b1101: _st0 = st1 << st0[3:0];
		4'b1110: _st0 = { {(8-SP_BITS){1'b0}}, rsp, {(8-SP_BITS){1'b0}}, dsp };
		4'b1111: _st0 = { 16{(st1 < st0)} };
		endcase
end

wire is_alu = (insn[15:13] == 3'b011);
wire is_lit = (insn[15]);

assign io_rd = (is_alu & (insn[11:8] == 4'hc));
assign io_wr = _ramWE;
assign io_addr = st0;
assign io_dout = st1;

assign _ramWE = is_alu & insn[5];
assign _dstkW = is_lit | (is_alu & insn[7]);

wire [1:0] dd = insn[1:0];  // D stack delta
wire [1:0] rd = insn[3:2];  // R stack delta

always @*
begin
	if (is_lit) begin
		_dsp = dsp + 1;
		_rsp = rsp;
		_rstkW = 0;
		_rstkD = { {(16-PC_BITS){1'b0}}, _pc };
	end else if (is_alu) begin
		_dsp = dsp + { {(SP_BITS-2){dd[1]}}, dd };
		_rsp = rsp + { {(SP_BITS-2){rd[1]}}, rd };
		_rstkW = insn[6];
		_rstkD = st0;
	end else begin
		if (insn[15:13] == 3'b001) begin
			// predicated jump is like DROP
			_dsp = dsp - 1;
		end else begin
			_dsp = dsp;
		end
		if (insn[15:13] == 3'b010) begin
			// call
			_rsp = rsp + 1;
			_rstkW = 1;
			_rstkD = { {(16-PC_BITS){1'b0}}, pc_plus_1 };
		end else begin
			// jump
			_rsp = rsp;
			_rstkW = 0;
			_rstkD = _pc;
		end
	end
end

always @*
begin
	if (sys_rst_i | pause)
		_pc = pc;
	else if ((insn[15:13] == 3'b000) |
		((insn[15:13] == 3'b001) & (|st0 == 0)) |
		(insn[15:13] == 3'b010))
		_pc = insn[PC_BITS-1:0];
	else if (is_alu & insn[12])
		_pc = rst0[PC_BITS-1:0];
	else
		_pc = pc_plus_1;
end

always @(posedge sys_clk_i)
begin
	if (sys_rst_i) begin
		pc <= 0;
		dsp <= 0;
		st0 <= 0;
		rsp <= 0;
	end else if (!pause) begin
		dsp <= _dsp;
		pc <= _pc;
		st0 <= _st0;
		rsp <= _rsp;
	end
end

endmodule
