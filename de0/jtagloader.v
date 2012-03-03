// Copyright 2012, Brian Swetland

`timescale 1ns/1ns

module jtagloader(
	input clk,
	output reg reset,

	output we,
	output reg [31:0] addr,
	output [31:0] data,

	input [7:0] uart_tx,
	input uart_tx_we,
	output uart_busy
	);

parameter IR_CTRL = 4'd0;
parameter IR_ADDR = 4'd1;
parameter IR_DATA = 4'd2;
parameter IR_UART = 4'd3;

initial reset = 0;

wire update;
wire [3:0] iir;
wire tck, tdi, sdr, udr, uir, cdr;
reg [31:0] dr;
reg [3:0] ir;

reg [7:0] txdata;
reg txbusy = 0;

assign uart_busy = txbusy;

jtag jtag0(
	.tdi(tdi),
	.tdo(dr[0]),
	.tck(tck),
	.ir_in(iir),
	.virtual_state_sdr(sdr),
	.virtual_state_udr(udr),
	.virtual_state_cdr(cdr),
	.virtual_state_uir(uir)
	);

always @(posedge tck) begin
	if (uir) ir <= iir;
	if (sdr) dr <= { tdi, dr[31:1] };
	if (cdr) dr <= { 23'b0, txbusy, txdata };
	end

sync sync0(
	.in(udr),
	.clk_in(tck),
	.out(update),
	.clk_out(clk)
	);

assign data = dr;
assign we = update & (ir == IR_DATA);

always @(posedge clk)
	if (update)
		case (iir)
		IR_CTRL: reset <= dr[0];
		IR_ADDR: addr <= dr;
		IR_DATA: addr <= addr + 32'd2;
		IR_UART: txbusy <= 0;
		endcase
	else if (uart_tx_we) begin
		txdata <= uart_tx;
		txbusy <= 1;
	end

endmodule

module sync(
	input clk_in,
	input clk_out,
	input in,
	output out
	);
reg toggle;
reg [2:0] sync;
always @(posedge clk_in)
	if (in) toggle <= ~toggle;
always @(posedge clk_out)
	sync <= { sync[1:0], toggle };
assign out = (sync[2] ^ sync[1]);
endmodule

