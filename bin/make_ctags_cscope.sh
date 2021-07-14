#!/bin/bash

REPO=$1

if [ -z ${REPO} ]; then
	REPO=${PWD}
fi

cd ${REPO} \
	&& ctags -R ${REPO} \
	&& find ${REPO} \( -name '*.c' -o -name '*.cpp' -o -name '*.cc' -o -name '*.h' -o -name '*.s' -o -name    '*.S' \) -print > cscope.files \
	&& cscope -b -i cscope.files
