PREFIX    ?= /usr/local
BINDIR    ?= $(PREFIX)/bin
MANDIR    ?= $(PREFIX)/share/man/man1
DATADIR   ?= $(PREFIX)/share/organize

VERSION := 2.0.2
SCRIPT   := src/organize.sh
OUTPUT   := build/organize.sh

.PHONY: all install uninstall clean distclean deb

all: $(OUTPUT)

$(OUTPUT): $(SCRIPT)
	mkdir -p build
	cp $< $@
	sed -i 's/@@VERSION@@/$(VERSION)/g' $@

install: $(OUTPUT)
	install -Dm755 $(OUTPUT) $(DESTDIR)$(BINDIR)/organize
	install -Dm644 config/rules.conf.example $(DESTDIR)$(DATADIR)/rules.conf.default
	install -Dm644 man/organize.1 $(DESTDIR)$(MANDIR)/organize.1

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/organize
	rm -rf $(DESTDIR)$(DATADIR)
	rm -f $(DESTDIR)$(MANDIR)/organize.1

clean:
	rm -rf build

distclean: clean
	rm -f organize_*.deb

deb: $(OUTPUT)
	mkdir -p debian/usr/bin debian/usr/share/organize debian/usr/share/man/man1
	install -m755 $(OUTPUT) debian/usr/bin/organize
	install -m644 config/rules.conf.example debian/usr/share/organize/rules.conf.default
	install -m644 man/organize.1 debian/usr/share/man/man1/
	mkdir -p debian/DEBIAN
	cp deb/control debian/DEBIAN/
	chmod 755 debian/DEBIAN/postinst 2>/dev/null || true
	dpkg-deb --build debian organize_$(VERSION)_all.deb
	rm -rf debian
