#!/bin/bash

TARGET_PATH=$1

if [ -z ${TARGET_PATH} ]; then
        TARGET_PATH=${PWD}
fi

if [ ! -e ${TARGET_PATH}/.gitignore ]; then
        exit
fi

if [ `grep Youngjinj ${TARGET_PATH}/.gitignore | wc -l` != 0 ]; then
        exit
fi

cat <<EOF >> ${TARGET_PATH}/.gitignore

## Youngjinj
build/
.vscode/
cscope.files
cscope.out
tags
csql.access
csql.err
EOF
