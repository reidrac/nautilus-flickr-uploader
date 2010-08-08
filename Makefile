DESTDIR=/usr/local
NAME=nautilus-flickr-uploader
PERL=`which perl`
VERSION=0.06

all:
	echo Try reading INSTALL file

install: pure_install
	sed -i -e "s|-I./lib|-I$(DESTDIR)/share/$(NAME)/lib|g" $(DESTDIR)/bin/$(NAME)
	sed -i -e "s|/usr/bin/perl|$(PERL)|g" $(DESTDIR)/bin/$(NAME)
	sed -i -e "s|./UI|$(DESTDIR)/share/$(NAME)/UI|g" $(DESTDIR)/share/$(NAME)/lib/Upload.pm
	sed -i -e "s|./UI|$(DESTDIR)/share/$(NAME)/UI|g" $(DESTDIR)/share/$(NAME)/lib/Account.pm
	sed -i -e "s|./bin|${DESTDIR}/bin|g" $(DESTDIR)/share/applications/$(NAME).desktop

pure_install:
	mkdir -p $(DESTDIR)/bin
	mkdir -p $(DESTDIR)/share/$(NAME)/lib
	mkdir -p $(DESTDIR)/share/$(NAME)/lib/Upload
	mkdir -p $(DESTDIR)/share/$(NAME)/lib/Account
	mkdir -p $(DESTDIR)/share/$(NAME)/UI
	mkdir -p $(DESTDIR)/share/applications
	mkdir -p $(DESTDIR)/share/icons/hicolor/scalable/apps
	install -p -m664 bin/$(NAME) $(DESTDIR)/bin
	install -p -m664 lib/*.pm $(DESTDIR)/share/$(NAME)/lib
	install -p -m664 lib/Upload/*.pm $(DESTDIR)/share/$(NAME)/lib/Upload
	install -p -m664 lib/Account/*.pm $(DESTDIR)/share/$(NAME)/lib/Account
	install -p -m664 UI/*.glade $(DESTDIR)/share/$(NAME)/UI
	install -p -m664 UI/$(NAME).svg $(DESTDIR)/share/icons/hicolor/scalable/apps
	install -p -m664 $(NAME).desktop $(DESTDIR)/share/applications/$(NAME).desktop
	chmod 755 $(DESTDIR)/bin/$(NAME)
	./gen-mo $(DESTDIR)

unistall:
	rm -f $(DESTDIR)/bin/$(NAME)
	rm -rf $(DESTDIR)/share/$(NAME)
	rm -f $(DESTDIR)/share/applications/$(NAME).desktop

dist:
	mkdir -p .tmp/$(NAME)-$(VERSION)/
	cp Changes COPYING TODO README INSTALL Makefile nautilus-flickr-uploader.desktop gen-mo .tmp/$(NAME)-$(VERSION)/
	mkdir -p .tmp/$(NAME)-$(VERSION)/UI/
	cp UI/*.glade .tmp/$(NAME)-$(VERSION)/UI/
	cp UI/*.svg .tmp/$(NAME)-$(VERSION)/UI/
	cp -r bin/ lib/ specs/ po/ .tmp/$(NAME)-$(VERSION)/
	cd .tmp && tar cvfz ../$(NAME)-$(VERSION).tar.gz $(NAME)-$(VERSION)/
	rm -rf .tmp

rpm: dist
	mv -f $(NAME)-$(VERSION).tar.gz ~/rpmbuild/SOURCES
	cp -f specs/nautilus-flickr-uploader.spec ~/rpmbuild/SPECS
	cd ~/rpmbuild/SPECS && rpmbuild -ba nautilus-flickr-uploader.spec
	cd ~/rpmbuild/RPMS/noarch && rpmlint nautilus-flickr-uploader-$(VERSION)-1.fc12.noarch.rpm

# EOF
