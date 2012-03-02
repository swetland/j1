
all: testbench a1 ram.hex

SRC := rtl/testbench.v rtl/j1.v rtl/dualsyncram.v

testbench: $(SRC)
	iverilog -Wall -o testbench $(SRC)

a1: a1.c
	cc -g -Wall -o a1 a1.c

ram.hex: src/core.1 src/test.1 a1
	./a1 -o ram.hex src/core.1 src/test.1

clean::
	rm -f a1 ram.hex testbench testbench.vcd
