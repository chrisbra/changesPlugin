SCRIPT=autoload/changes.vim plugin/changesPlugin.vim
DOC=doc/changesPlugin.txt
PLUGIN=changes


all: $(PLUGIN)

clean:
	rm -f *.vba */*.orig *.~* .VimballRecord

dist-clean: clean

install:
	vim -u NONE -N -c':so' -c':q!' ${PLUGIN}.vba

uninstall:
	vim -u NONE -N -c':RmVimball ${PLUGIN}.vba'

undo:
	for i in */*.orig; do mv -f "$$i" "$${i%.*}"; done

commit:
	git commit -m "increased version number" $(PERLSCRIPT)

changes:
	perl -i.orig -pne 'if (/Version:/) {s/\.(\d)*/sprintf(".%d", 1+$$1)/e}' ${SCRIPT}
	perl -i -pne 'if (/GetLatestVimScripts:/) {s/(\d+)\s+:AutoInstall:/sprintf("%d", 1+$$1)/e}' ${SCRIPT}
	perl -i -pne 'if (/Last Change:/) {s/\d+\.\d+\.\d\+$$/sprintf("%s", `date -R`)/e}' ${SCRIPT}
	perl -i.orig -pne 'if (/Version:/) {s/\.(\d)+.*\n/sprintf(".%d %s", 1+$$1, `date -R`)/e}' ${DOC}
	vim -u NONE -N -c 'ru! vimballPlugin.vim' -c ':call append(".", ["autoload/changes.vim", "doc/changesPlugin.txt", "plugin/changesPlugin.vim"])' -c ':%MkVimball ${PLUGIN}' -c':q!'
