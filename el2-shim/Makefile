CROSS_COMPILE ?= /opt/abcross/arm64/bin/aarch64-aosc-linux-gnu-

DEBUG ?= 0
DIAGNOSTIC_NO_STAGE2 ?= 0
DIAGNOSTIC_NO_PSCI_TRAP ?= 0
DIAGNOSTIC_SKIP_INIT ?= 0
DIAGNOSTIC_TABLES_ONLY ?= 0

CC = $(CROSS_COMPILE)gcc
AS = $(CROSS_COMPILE)as
LD = $(CROSS_COMPILE)ld
OBJCOPY = $(CROSS_COMPILE)objcopy

INCLUDES = -I ./include -I ./uboot-headers -ffreestanding

DEFINES = -DSOC_HEADER="\"h6.h\""

ifneq ($(DEBUG),1)
DEFINES += -DNDEBUG
endif

ifeq ($(DIAGNOSTIC_NO_STAGE2),1)
DEFINES += -DDIAGNOSTIC_NO_STAGE2
endif

ifeq ($(DIAGNOSTIC_NO_PSCI_TRAP),1)
DEFINES += -DDIAGNOSTIC_NO_PSCI_TRAP
endif

ifeq ($(DIAGNOSTIC_SKIP_INIT),1)
DEFINES += -DDIAGNOSTIC_SKIP_INIT
endif

ifeq ($(DIAGNOSTIC_TABLES_ONLY),1)
DEFINES += -DDIAGNOSTIC_TABLES_ONLY
endif

ASFLAGS = $(INCLUDES) $(DEFINES) -D__ASSEMBLY__
CFLAGS = $(INCLUDES) $(DEFINES) -O2 -mno-outline-atomics \
	-mgeneral-regs-only -fno-stack-protector

LDSCRIPT = ldscripts/a64.ld
LDSCRIPTS = ldscripts/a64.ld ldscripts/common.ld

LDFLAGS = -nostdlib -static -T $(LDSCRIPT)

OBJS = start.o init.o uart.o stack.o exceptions.o exception_funcs.o panic.o pgtables.o trapped_funcs.o

all: el2-bb.bin

el2-bb.elf: $(OBJS) $(LDSCRIPTS)
	$(LD) $(LDFLAGS) $(OBJS) -o $@

el2-bb.bin: el2-bb.elf
	$(OBJCOPY) -O binary $< $@

.PHONY: clean
clean:
	rm -f el2-bb.* *.o
