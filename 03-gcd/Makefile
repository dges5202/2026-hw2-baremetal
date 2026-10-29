CC ?= cc
CFLAGS ?= -O0 -std=c99 -Wall -Wextra -Wpedantic

CROSS ?= riscv64-unknown-elf-
ARCH  = -march=rv32i_zicsr -mabi=ilp32
AFLAGS = -g $(ARCH)
LDFLAGS = -m elf32lriscv -T linker.ld --no-warn-rwx-segments
EMU ?= $(RV32EMU)
ifeq ($(EMU),)
EMU := ../rv32emu/build/rv32emu
endif

.PHONY: all test asm run-asm dump-asm clean

all: gcd

gcd: gcd.c
	$(CC) $(CFLAGS) $< -o $@

test: gcd
	./gcd

asm: gcd.elf

gcd.o: gcd.S
	$(CROSS)as $(AFLAGS) $< -o $@

gcd.elf: gcd.o linker.ld
	$(CROSS)ld $(LDFLAGS) -o $@ gcd.o

run-asm: gcd.elf
	$(EMU) $<

dump-asm: gcd.elf
	$(CROSS)objdump -d $<

clean:
	$(RM) gcd gcd.o gcd.elf
