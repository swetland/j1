// Copyright 2012, Brian Swetland

module de0board(
	input CLOCK_50,
	output [9:0] LEDG,
	output [6:0] HEX0_D,
	output [6:0] HEX1_D,
	output [6:0] HEX2_D,
	output [6:0] HEX3_D,
	output HEX0_DP,
	output HEX1_DP,
	output HEX2_DP,
	output HEX3_DP,
	input [2:0] ORG_BUTTON,
	output [3:0] VGA_R,
	output [3:0] VGA_G,
	output [3:0] VGA_B,
	output VGA_HS,
	output VGA_VS
	);

reg [15:0] status;
reg [31:0] count;

assign LEDG = 10'b1111111111;
assign HEX0_DP = ~reset;
assign HEX1_DP = 1'b1;
assign HEX2_DP = 1'b1;
assign HEX3_DP = 1'b1;

hex2seven hex0(.in(status[3:0]),.out(HEX0_D));
hex2seven hex1(.in(status[7:4]),.out(HEX1_D));
hex2seven hex2(.in(status[11:8]),.out(HEX2_D));
hex2seven hex3(.in(status[15:12]),.out(HEX3_D));

wire reset, clk, jtag_reset;
assign clk = CLOCK_50;

assign reset = jtag_reset | (~ORG_BUTTON[0]);

wire [15:0] io_addr, io_data_r, io_data_w;
wire io_re, io_we;

wire [15:0] pgm_addr, pgm_data;
wire pgm_we;

always @(posedge clk)
	if (reset)
		status <= 16'h8888;
	else if (io_we && (io_addr == 16'h8000))
		status <= io_data_w;

j1 cpu(
	.sys_clk_i(clk),
	.sys_rst_i(reset),

	.io_addr(io_addr),
	.io_din(io_data_r),
	.io_dout(io_data_w),
	.io_rd(io_re),
	.io_wr(io_we),

	.pgm_addr(pgm_addr),
	.pgm_data(pgm_data),
	.pgm_we(pgm_we)
	);

jtagloader loader(
	.clk(clk),
	.addr(pgm_addr),
	.data(pgm_data),
	.we(pgm_we),
	.reset(jtag_reset)
	);

endmodule

