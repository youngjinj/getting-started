#!/bin/bash

CURRENT_BRANCH=`git branch | grep "^*" | awk '{print $NF}'`

if [ "${CURRENT_BRANCH}" == "development" ]; then
	if [ `git branch -a | grep "${PWD##/*/}$" | wc -l` > 0 ]; then
		git checkout ${PWD##/*/}
	fi
fi

if [ ! -e .vscode ]; then
	cp -r ${HOME}/github/getting-started/install/vscode/.vscode .
fi

${HOME}/github/getting-started/bin/make_ctags_cscope.sh .

if [ ! -e .gitignore ]; then
	exit 1
fi

if [ `grep Youngjinj .gitignore | wc -l` != 0 ]; then
	exit 1
fi

cat <<EOF >> .gitignore

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
