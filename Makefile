top:; @date

Makefile:;

%.html: %.md; pandoc -s -o $@ $<
md := $(wildcard *.md)
html := $(md:%.md=%.html)
html: $(html);
.PHONY: html

/usr/bin/pandoc:; sudo aptitude install pandoc
