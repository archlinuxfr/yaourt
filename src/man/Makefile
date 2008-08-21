# Makefile for yaourt Man Page
#
#  Author : Marc Poiroud <marci1@archlinux.fr>
#
PREFIX=/usr
MANDIR=$(PREFIX)/share/man
MAN5DIR=$(MANDIR)/man5
MAN8DIR=$(MANDIR)/man8

all : install

install : install-man5 install-man8

# install English Man Page
install-man5 :
	install -d -m 755 $(DESTDIR)$(MAN5DIR)
	for f in *.5; \
	do \
	  install -m 644 "$$f" $(DESTDIR)$(MAN5DIR)/"$$f"; \
	done;

install-man8 :
	install -d -m 755 $(DESTDIR)$(MAN8DIR)
	for f in *.8; \
	do \
	  install -m 644 "$$f" $(DESTDIR)$(MAN8DIR)/"$$f"; \
	done;

# Install French Man Page /!\ Inactif /!\
#install-fr :
#	cd fr ; \
#	make install ;
