PREFIX=/usr
BINDIR=$(PREFIX)/bin

PROGRAMS=ftee bftee

all: $(PROGRAMS)

%.o: %.c
	$(CC) -c -o $@ $< $(CFLAGS)

ftee: ftee.o 
	$(CC) -o $@ $^ $(LDFLAGS)

bftee: bftee.o 
	$(CC) -o $@ $^ $(LDFLAGS)

.PHONY: install
install: $(PROGRAMS)
	$(foreach prog,$(PROGRAMS),install -D -m 0755 $(prog) $(DESTDIR)$(BINDIR)/$(prog);)

clean:
	rm -f $(PROGRAMS) *~ *.o
