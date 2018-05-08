
# Copyright (c) 2003-2010, Andrew Dunstan

# See accompanying License file for license details

ALLPERLFILES = $(shell find ./bin  ./cgi-bin \( -name '*.pl' -o -name '*.pm' \) -print | sed 's!\./!!') BuildFarmWeb.pl.skel

syncheck:
	export BFCONFDIR=.;	for f in $(ALLPERLFILES) ; do perl -cw $${f}; done;

tidy:
	perltidy $(ALLPERLFILES)

critic:
	perlcritic -3 --theme core $(ALLPERLFILES)

show:
	@echo $(ALLPERLFILES)
