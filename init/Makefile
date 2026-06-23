CC ?= gcc
CFLAGS = -Os -s -Wall -I../output/buildroot-2026.02/output/host/arm-buildroot-uclinux-uclibcgnueabi/sysroot/usr/include
LDFLAGS = -Wl,--gc-sections

CROSS = ../output/buildroot-2026.02/output/host/bin/arm-buildroot-uclinux-uclibcgnueabi-

init: init.c
	$(CROSS)$(CC) $(CFLAGS) $(LDFLAGS) -o init init.c

clean:
	rm -f init