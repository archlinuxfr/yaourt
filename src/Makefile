# Makefile for yaourt
#
# Copyright (C) 2008 Julien MISCHKOWITZ <wain@archlinux.fr>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
#

VERSION = 1.0
SHELL = /bin/bash
INSTALL = /bin/install -c
GZIP = /bin/gzip
MSGFMT = /usr/bin/msgfmt
SED = /bin/sed
DESTDIR =
bindir = /usr/bin
libdir = /usr/lib/yaourt
man5dir = /usr/man/man5
man8dir = /usr/man/man8
sysconfdir = /etc
completiondir = ${sysconfdir}/bash_completion.d
localedir = /usr/share/locale

PROGRAMS = yaourt pacdiffviewer
install: 
	${GZIP} -c yaourt.8 > yaourt.8.gz
	${GZIP} -c yaourtrc.5 > yaourtrc.5.gz
	$(INSTALL) -d $(DESTDIR)$(bindir)
	$(INSTALL) -d $(DESTDIR)$(libdir)
	$(INSTALL) -d $(DESTDIR)$(man8dir)
	$(INSTALL) -d $(DESTDIR)$(man5dir)
	$(INSTALL) -d $(DESTDIR)$(sysconfdir)
	$(INSTALL) -d $(DESTDIR)$(completiondir)
	$(INSTALL) -m755 yaourt.sh $(DESTDIR)$(bindir)/yaourt
	$(INSTALL) -m755 pacdiffviewer.sh $(DESTDIR)$(bindir)/pacdiffviewer
	$(INSTALL) -m644 yaourt.8.gz $(DESTDIR)$(man8dir)
	$(INSTALL) -m644 yaourtrc.5.gz $(DESTDIR)$(man5dir)
	$(INSTALL) -m644 yaourtrc $(DESTDIR)$(sysconfdir)/yaourtrc
	$(INSTALL) -m644 lib/alpm_backup.sh $(DESTDIR)$(libdir)
	$(INSTALL) -m644 lib/alpm_query.sh $(DESTDIR)$(libdir)
	$(INSTALL) -m644 lib/alpm_stats.sh $(DESTDIR)$(libdir)
	$(INSTALL) -m644 lib/abs.sh $(DESTDIR)$(libdir)
	$(INSTALL) -m644 lib/aur.sh $(DESTDIR)$(libdir)
	$(INSTALL) -m644 lib/basicfunctions.sh $(DESTDIR)$(libdir)
	$(INSTALL) -m644 lib/color.sh $(DESTDIR)$(libdir)
	$(INSTALL) -m644 lib/pacman_conf.sh $(DESTDIR)$(libdir)
	$(INSTALL) -m755 bashcompletion $(DESTDIR)$(completiondir)/yaourt
	# Install locale
	for file in po/*/*.po; \
	do \
	  package=$$(echo $$file | $(SED) -e 's#po/\([^/]\+\).*#\1#'); \
	  lang=$$(echo $$file | $(SED) -e 's#.*/\([^/]\+\).po#\1#'); \
	  $(INSTALL) -d $(DESTDIR)$(localedir)/$$lang/LC_MESSAGES; \
	  $(MSGFMT) -o $(DESTDIR)$(localedir)/$$lang/LC_MESSAGES/$$package.mo $$file; \
	done

.PHONY: install
