CROSS_COMPILE ?=
CC := $(CROSS_COMPILE)gcc
LD := $(CROSS_COMPILE)gcc

SRCDIR := src
INCDIR := include

CPPFLAGS := -O2 -Wall -Wno-unused-parameter
CPPFLAGS += -DADB_HOST=0 -DHAVE_FORKEXEC=1 -D_XOPEN_SOURCE -D_GNU_SOURCE
# CPPFLAGS += -DHAVE_VFORKEXEC=1
# CPPFLAGS += -DADBD_NO_PTY=1
CPPFLAGS += -DALLOW_ADBD_ROOT=1 -DHAVE_SYMLINKS
CPPFLAGS += -DHAVE_TERMIO_H -DADBD_NON_ANDROID
CPPFLAGS += -I$(INCDIR)

# Feature gates (inverted: set to 1 to disable)
NO_AUTH ?= 0
NO_LISTENER ?= 0

LDFLAGS :=

# Libraries per feature (when enabled)
AUTH_LIBS := -lcrypto -lcrypt

# Aggregate required libraries
LIBS := -lc -lpthread -lz
ifeq ($(NO_AUTH),0)
LIBS += $(AUTH_LIBS)
endif

SRCS := $(wildcard $(SRCDIR)/*.c)
ifeq ($(NO_AUTH),1)
SRCS := $(filter-out $(SRCDIR)/adb_auth_client.c, $(SRCS))
endif
ifeq ($(NO_LISTENER),1)
CPPFLAGS += -DADBD_NO_LISTENER
endif
OBJS := $(SRCS:.c=.o)

.PHONY: all clean

all: adbd

adbd: $(OBJS)
	$(LD) -o $@ $(LDFLAGS) $^ $(LIBS)

$(SRCDIR)/%.o: $(SRCDIR)/%.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -c -o $@ $<

clean:
	rm -f $(OBJS) adbd
