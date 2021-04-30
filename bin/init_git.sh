#!/bin/bash

git checkout ${PWD##/*/}

if [ ! -e .vscode ]; then
	cp -r $HOME/github/backup/.vscode .
fi

$HOME/bin/make_ctags_cscope.sh .

if [ ! -e .gitignore ]; then
	exit 1
fi

if [ `grep Youngjinj .gitignore | wc -l` != 0 ]; then
	exit 1
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
