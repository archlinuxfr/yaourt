# yaourt: pacman frontend

VERSION       = $(shell git describe --abbrev=4)
DESTDIR       =
PREFIX        = /usr/local
SHELL         = /bin/bash
INSTALL       = /usr/bin/env install 
MSGFMT        = /usr/bin/msgfmt
SED           = /bin/sed
bindir        = $(PREFIX)/bin
libdir        = $(PREFIX)/lib
sysconfdir    = $(PREFIX)/etc
completiondir = ${sysconfdir}/bash_completion.d
localedir     = $(PREFIX)/share/locale
localstatedir = $(PREFIX)/var
mandir        = $(PREFIX)/share/man
dbpath        = ${localstatedir}/lib/pacman/
cachedir      = ${localstatedir}/cache/pacman/pkg/
aururl        = http://aur.archlinux.org

SCRIPTS = yaourt.sh pacdiffviewer.sh \
		  yaourtrc \
		  lib/util.sh lib/pkgbuild.sh lib/pacman.sh lib/abs.sh

all: $(SCRIPTS)

$(SCRIPTS): ${SCRIPTS:=.in}
	@echo '	GEN' $@
	@$(SED) -e 's|@VERSION@|$(VERSION)|g' \
	        -e 's|@localedir@|$(localedir)|g' \
	        -e 's|@sysconfdir@|$(sysconfdir)|g' \
	        -e 's|@libdir@|$(libdir)|g' \
	        -e 's|@localstatedir@|$(localstatedir)|g' \
	        -e 's|@dbpath@|$(dbpath)|g' \
	        -e 's|@cachedir@|$(cachedir)|g' \
	        -e 's|@aururl@|$(aururl)|g' \
	        $@.in > $@

install: $(SCRIPTS)
	$(INSTALL) -d $(DESTDIR)$(bindir)
	$(INSTALL) -d $(DESTDIR)$(libdir)/yaourt
	$(INSTALL) -d $(DESTDIR)$(sysconfdir)
	$(INSTALL) -d $(DESTDIR)$(completiondir)
	$(INSTALL) -d $(DESTDIR)$(mandir)/man{5,8}
	# Scripts
	$(INSTALL) -m755 yaourt.sh $(DESTDIR)$(bindir)/yaourt
	$(INSTALL) -m755 pacdiffviewer.sh $(DESTDIR)$(bindir)/pacdiffviewer
	# Configuration
	$(INSTALL) -m644 yaourtrc $(DESTDIR)$(sysconfdir)/yaourtrc
	$(INSTALL) -m644 bashcompletion $(DESTDIR)$(completiondir)/yaourt
	# Libs
	$(INSTALL) -m644 lib/alpm_backup.sh $(DESTDIR)$(libdir)/yaourt
	$(INSTALL) -m644 lib/alpm_query.sh $(DESTDIR)$(libdir)/yaourt
	$(INSTALL) -m644 lib/alpm_stats.sh $(DESTDIR)$(libdir)/yaourt
	$(INSTALL) -m644 lib/abs.sh $(DESTDIR)$(libdir)/yaourt
	$(INSTALL) -m644 lib/aur.sh $(DESTDIR)$(libdir)/yaourt
	$(INSTALL) -m644 lib/util.sh $(DESTDIR)$(libdir)/yaourt
	$(INSTALL) -m644 lib/io.sh $(DESTDIR)$(libdir)/yaourt
	$(INSTALL) -m644 lib/pacman.sh $(DESTDIR)$(libdir)/yaourt
	$(INSTALL) -m644 lib/pkgbuild.sh $(DESTDIR)$(libdir)/yaourt
	$(INSTALL) -m644 lib/misc.sh $(DESTDIR)$(libdir)/yaourt
	# Man
	$(INSTALL) -m644 man/*.5 $(DESTDIR)$(mandir)/man5
	$(INSTALL) -m644 man/*.8 $(DESTDIR)$(mandir)/man8
	# Locales
	test -x $(MSGFMT) && for file in po/*/*.po; \
	do \
	  package=$$(echo $$file | $(SED) -e 's#po/\([^/]\+\).*#\1#'); \
	  lang=$$(echo $$file | $(SED) -e 's#.*/\([^/]\+\).po#\1#'); \
	  $(INSTALL) -d $(DESTDIR)$(localedir)/$$lang/LC_MESSAGES; \
	  $(MSGFMT) -o $(DESTDIR)$(localedir)/$$lang/LC_MESSAGES/$$package.mo $$file; \
	done

dist:
	mkdir yaourt-$(VERSION) 
	cp -a AUTHORS ChangeLog INSTALL COPYING Makefile pacdiffviewer.sh.in yaourt.sh.in yaourtrc \
	  bashcompletion lib man po yaourt-$(VERSION)
	$(SED) -i -e 's|^VERSION.*|VERSION=$(VERSION)|g' yaourt-$(VERSION)/Makefile
	tar zcvf yaourt-$(VERSION).tar.gz yaourt-$(VERSION)
	rm -rf yaourt-$(VERSION)

clean:
	rm -f $(SCRIPTS)
	rm -f yaourt-$(VERSION).tar.gz
	rm -rf yaourt-$(VERSION)


.PHONY: all install clean dist
