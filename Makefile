# vim: set noet sw=4 ts=4:

# External utilities
PYTHON=python
PIP=pip
PYTEST=py.test
PYFLAGS=
DEST_DIR=/

# Horrid hack to ensure setuptools is installed in our Python environment. This
# is necessary with Python 3.3's venvs which don't install it by default.
ifeq ($(shell python -c "import setuptools" 2>&1),)
SETUPTOOLS:=
else
SETUPTOOLS:=$(shell wget https://bitbucket.org/pypa/setuptools/raw/bootstrap/ez_setup.py -O - | $(PYTHON))
endif

# Calculate the base names of the distribution, the location of all source,
# documentation, packaging, icon, and executable script files
NAME:=$(shell $(PYTHON) $(PYFLAGS) setup.py --name)
VER:=$(shell $(PYTHON) $(PYFLAGS) setup.py --version)
ifeq ($(shell lsb_release -si),Ubuntu)
DEB_SUFFIX:=ubuntu2
else
DEB_SUFFIX:=
endif
PYVER:=$(shell $(PYTHON) $(PYFLAGS) -c "import sys; print('py%d.%d' % sys.version_info[:2])")
PY_SOURCES:=$(shell \
	$(PYTHON) $(PYFLAGS) setup.py egg_info >/dev/null 2>&1 && \
	cat $(NAME).egg-info/SOURCES.txt)
DEB_SOURCES:=debian/changelog \
	debian/control \
	debian/copyright \
	debian/rules \
	debian/docs \
	debian/$(NAME)-docs.docs \
	debian/$(NAME)-docs.doc-base \
	debian/$(NAME)-client.manpages \
	debian/$(NAME)-server.manpages \
	debian/$(NAME)-server.cpid.init \
	debian/$(NAME)-server.cpid.default \
	$(wildcard debian/*.desktop)
DOC_SOURCES:=$(wildcard docs/*.rst)

# Calculate the name of all outputs
DIST_EGG=dist/$(NAME)-$(VER)-$(PYVER).egg
DIST_TAR=dist/$(NAME)-$(VER).tar.gz
DIST_ZIP=dist/$(NAME)-$(VER).zip
DIST_DEB=dist/$(NAME)-server_$(VER)-1$(DEB_SUFFIX)_all.deb \
	dist/$(NAME)-client_$(VER)-1$(DEB_SUFFIX)_all.deb \
	dist/$(NAME)-common_$(VER)-1$(DEB_SUFFIX)_all.deb \
	dist/$(NAME)-docs_$(VER)-1$(DEB_SUFFIX)_all.deb
DIST_DSC=dist/$(NAME)_$(VER)-1$(DEB_SUFFIX).tar.gz \
	dist/$(NAME)_$(VER)-1$(DEB_SUFFIX).dsc \
	dist/$(NAME)_$(VER)-1$(DEB_SUFFIX)_source.changes
MAN_PAGES=man/cpi.1 man/cpid.1


# Default target
all:
	@echo "make install - Install on local system"
	@echo "make develop - Install symlinks for development"
	@echo "make test - Run tests through nose environment"
	@echo "make doc - Generate HTML and PDF documentation"
	@echo "make source - Create source package"
	@echo "make egg - Generate a PyPI egg package"
	@echo "make zip - Generate a source zip package"
	@echo "make tar - Generate a source tar package"
	@echo "make deb - Generate a Debian package"
	@echo "make dist - Generate all packages"
	@echo "make clean - Get rid of all generated files"
	@echo "make release - Create and tag a new release"
	@echo "make upload - Upload the new release to repositories"

install: $(SUBDIRS)
	$(PYTHON) $(PYFLAGS) setup.py install --root $(DEST_DIR)

doc: $(DOC_SOURCES)
	$(PYTHON) $(PYFLAGS) setup.py build_sphinx -b html

source: $(DIST_TAR) $(DIST_ZIP)

egg: $(DIST_EGG)

zip: $(DIST_ZIP)

tar: $(DIST_TAR)

deb: $(DIST_DEB) $(DIST_DSC)

dist: $(DIST_EGG) $(DIST_DEB) $(DIST_DSC) $(DIST_TAR) $(DIST_ZIP)

develop: tags
	$(PIP) install -e .

test:
	$(PYTEST) -v tests/

clean:
	$(PYTHON) $(PYFLAGS) setup.py clean
	$(MAKE) -f $(CURDIR)/debian/rules clean
	rm -fr build/ dist/ $(NAME).egg-info/ tags
	find $(CURDIR) -name "*.pyc" -delete

tags: $(PY_SOURCES)
	ctags -R --exclude="build/*" --exclude="debian/*" --exclude="docs/*" --languages="Python"

$(MAN_PAGES): $(DOC_SOURCES)
	$(PYTHON) $(PYFLAGS) setup.py build_sphinx -b man
	mkdir -p man/
	cp build/sphinx/man/*.1 man/

$(DIST_TAR): $(PY_SOURCES) $(SUBDIRS) $(LICENSES)
	$(PYTHON) $(PYFLAGS) setup.py sdist --formats gztar

$(DIST_ZIP): $(PY_SOURCES) $(SUBDIRS) $(LICENSES)
	$(PYTHON) $(PYFLAGS) setup.py sdist --formats zip

$(DIST_EGG): $(PY_SOURCES) $(SUBDIRS) $(LICENSES)
	$(PYTHON) $(PYFLAGS) setup.py bdist_egg

$(DIST_DEB): $(PY_SOURCES) $(DEB_SOURCES) $(MAN_PAGES)
	# build the source package in the parent directory then rename it to
	# project_version.orig.tar.gz
	$(PYTHON) $(PYFLAGS) setup.py sdist --dist-dir=../
	rename -f 's/$(NAME)-(.*)\.tar\.gz/$(NAME)_$$1\.orig\.tar\.gz/' ../*
	debuild -b -i -I -Idist -Ibuild -Ihtmlcov -I__pycache__ -I.coverage -Itags -I*.pyc -rfakeroot
	mkdir -p dist/
	for f in $(DIST_DEB); do cp ../$${f##*/} dist/; done

$(DIST_DSC): $(PY_SOURCES) $(DEB_SOURCES) $(MAN_PAGES)
	# build the source package in the parent directory then rename it to
	# project_version.orig.tar.gz
	$(PYTHON) $(PYFLAGS) setup.py sdist --dist-dir=../
	rename -f 's/$(NAME)-(.*)\.tar\.gz/$(NAME)_$$1\.orig\.tar\.gz/' ../*
	debuild -S -i -I -Idist -Ibuild -Ihtmlcov -I__pycache__ -I.coverage -Itags -I*.pyc -rfakeroot
	mkdir -p dist/
	for f in $(DIST_DSC); do cp ../$${f##*/} dist/; done

release: $(PY_SOURCES) $(DOC_SOURCES) $(DEB_SOURCES)
	# ensure there are no current uncommitted changes
	test -z "$(shell git status --porcelain)"
	# update the changelog with new release information
	dch --newversion $(VER)-1 --controlmaint
	# commit the changes and add a new tag
	git commit debian/changelog -m "Updated changelog for release $(VER)"
	git tag -s release-$(VER) -m "Release $(VER)"

upload: $(PY_SOURCES) $(DOC_SOURCES) $(DIST_DEB) $(DIST_DSC)
	# build a source archive and upload to PyPI
	$(PYTHON) $(PYFLAGS) setup.py sdist upload
	# build the deb source archive and upload to the PPA
	dput waveform-ppa ../$(NAME)_$(VER)-1$(DEB_SUFFIX)_source.changes

.PHONY: all install develop test doc source egg deb tar zip dist clean tags release upload

