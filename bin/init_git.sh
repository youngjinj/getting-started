#!/bin/bash

if [ ! -e .git ]; then
	exit
fi

if [ ! -e .vscode ]; then
	cp -r $HOME/github/backup/.vscode .
fi

$HOME/bin/make_ctags_cscope.sh .

if [ ! -e .gitignore ]; then
	exit
fi

if [ `grep Youngjinj .gitignore | wc -l` != 0 ]; then
	exit
fi

cat << EOF >> .gitignore

## Youngjinj
.gitignore
build/
.vscode/
cscope.files
cscope.out
tags
csql.access
csql.err
EOF
