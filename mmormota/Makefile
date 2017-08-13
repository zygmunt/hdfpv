PREFIX=/usr
BINDIR=$(PREFIX)/bin

PROGRAMS = video_30 video_48

VC_LIBDIR ?= /opt/vc/lib
VC_INCDIR ?= /opt/vc/include

IL_INCDIR = $(HOST_DIR)/usr/src/hello_pi/libs/ilclient

INCLUDEFLAGS = -I$(IL_INCDIR) -I$(VC_INCDIR) -I$(VC_INCDIR)/interface/vmcs_host/linux -I$(VC_INCDIR)/interface/vcos/pthreads 

LIBFLAGS=-L$(VC_LIBDIR) -lbcm_host -lvchostif -lilclient -lvcilcs

all: $(PROGRAMS)

%.o: %.c
	$(CC) -c -o $@ $< $(CFLAGS) $(INCLUDEFLAGS)

video_30: video_30.o
	$(CC) -o $@ $^ $(LDFLAGS) $(LIBFLAGS)

video_48: video_48.o
	$(CC) -o $@ $^ $(LDFLAGS) $(LIBFLAGS)

.PHONY: install
install: $(PROGRAMS)
	$(foreach prog,$(PROGRAMS),install -D -m 0755 $(prog) $(DESTDIR)$(BINDIR)/$(prog);)

clean:
	rm -f $(PROGRAMS) *~ *.o
