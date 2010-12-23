APP_NAME=lib
PACKAGE=acf-$(APP_NAME)
VERSION=0.2.0

APP_DIST=\
	*.lua\


EXTRA_DIST=README Makefile

DISTFILES=$(APP_DIST) $(EXTRA_DIST) 

TAR=tar

P=$(PACKAGE)-$(VERSION)
tarball=$(P).tar.bz2
install_dir=$(DESTDIR)/usr/share/lua/5.1/

all:
clean:
	rm -rf $(tarball) $(P)

dist: $(tarball)

install:
	mkdir -p "$(install_dir)"
	cp -a $(APP_DIST) "$(install_dir)"

$(tarball):	$(DISTFILES)
	rm -rf $(P)
	mkdir -p $(P)
	cp -a $(DISTFILES) $(P)
	$(TAR) -jcf $@ $(P)
	rm -rf $(P)

# target that creates a tar package, unpacks is and install from package
dist-install: $(tarball)
	$(TAR) -jxf $(tarball)
	$(MAKE) -C $(P) install DESTDIR=$(DESTDIR)
	rm -rf $(P)

.PHONY: all clean dist install dist-install
