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

wire [15:0] io_addr, io_data_w;
reg [15:0] io_data_r;
wire io_re, io_we;

wire [15:0] pgm_addr, pgm_data;
wire pgm_we;

always @(posedge clk)
	if (reset)
		status <= 16'h8888;
	else if (io_we && (io_addr == 16'hE000))
		status <= io_data_w;

reg [15:0] rom[0:2**13-1];
wire [12:0] rom_addr;
reg [15:0] rom_data;
reg [15:0] ram_data;

wire [15:0] xaddr;
assign xaddr = pgm_we ? pgm_addr[13:1] : io_addr[12:0];

always @(posedge clk) begin
	if (pgm_we)
		rom[xaddr] <= pgm_data;
	rom_data <= rom[rom_addr];
	ram_data <= rom[xaddr];
end

wire uart_busy;

always @(*) case(io_addr[15:12])
	4'h0: io_data_r = ram_data;
	4'hF: io_data_r = { 15'b0, uart_busy };
	default: io_data_r = 16'hXXXX;
	endcase

j1 cpu(
	.sys_clk_i(clk),
	.sys_rst_i(reset),

	.insn(rom_data),
	.insn_addr(rom_addr),

	.io_addr(io_addr),
	.io_din(io_data_r),
	.io_dout(io_data_w),
	.io_rd(io_re),
	.io_wr(io_we)
	);

jtagloader loader(
	.clk(clk),
	.reset(jtag_reset),

	.addr(pgm_addr),
	.data(pgm_data),
	.we(pgm_we),

	.uart_tx(io_data_w[7:0]),
	.uart_tx_we(io_we & (io_addr[15:12] == 4'hF)),
	.uart_busy(uart_busy)
	);

wire [11:0] pixel;
wire [10:0] vram_addr;
wire [7:0] vram_data;
wire [7:0] line;
wire newline, advance;

reg clk25;

always @(posedge clk)
	clk25 = ~clk25;

vga vga(
	.clk(clk25),
	.reset(1'b0),
	.newline(newline),
	.advance(advance),
	.line(line),
	.pixel(pixel),
	.r(VGA_R),
	.b(VGA_B),
	.g(VGA_G),
	.hs(VGA_HS),
	.vs(VGA_VS)
	);

pixeldata pxd(
	.clk(clk25),
	.newline(newline),
	.advance(advance),
	.line(line),
	.pixel(pixel),
	.vram_data(vram_data),
	.vram_addr(vram_addr)
	);

videoram #(8,11) vram(
	.clk(clk),
	.we(io_we & (io_addr[15:12] == 4'h8)),
	.rdata(vram_data),
	.raddr(vram_addr),
	.wdata(io_data_w[7:0]),
	.waddr(io_addr)
	);

endmodule

