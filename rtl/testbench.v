// Copyright 2012, Brian Swetland

`timescale 1ns/1ns

module testbench;

reg clk, reset;

initial begin
	$readmemh("ram.hex", rom);
        $dumpfile("testbench.vcd");
        $dumpvars(0,testbench);
	clk = 0;
	reset = 1;
	#40
	reset = 0;
	#1000
	$finish;
end

always #10 clk = ~clk;

wire [15:0] io_addr, io_rdata, io_wdata;
wire io_re, io_we;

// sync rom
reg [15:0] rom_data;
wire [12:0] rom_addr;
reg [15:0] rom[0:2**13-1];
always @(posedge clk)
	rom_data <= rom[rom_addr];

j1 cpu(
	.sys_clk_i(clk),
	.sys_rst_i(reset),

	.insn(rom_data),
	.insn_addr(rom_addr),

	.io_rd(io_re),
	.io_wr(io_we),
	.io_addr(io_addr),
	.io_dout(io_wdata),
	.io_din(io_rdata)
	);

always @(posedge clk)
	if (io_we)
		$display("%h <- %h", io_addr, io_wdata);

endmodule

