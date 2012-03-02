// Copyright 2012, Brian Swetland

`timescale 1ns/1ns

module testbench;

reg clk, reset;

initial begin
	$readmemh("ram.hex", cpu.memory.mem);
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

j1 cpu(
	.sys_clk_i(clk),
	.sys_rst_i(reset),
	.io_din(io_rdata),
	.io_rd(io_re),
	.io_wr(io_we),
	.io_addr(io_addr),
	.io_dout(io_wdata),
	.pgm_addr(0),
	.pgm_data(0),
	.pgm_we(0)
	);

always @(posedge clk)
	if (io_we)
		$display("%h <- %h", io_addr, io_wdata);

endmodule

