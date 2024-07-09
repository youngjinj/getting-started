#!/bin/bash

TARGET_PATH=$1

if [ -z ${TARGET_PATH} ]; then
	TARGET_PATH=${PWD}
fi

# deprecated
exit

cd ${TARGET_PATH} \
	&& ctags -R ${TARGET_PATH} \
	&& find ${TARGET_PATH} \( -name '*.c' -o -name '*.cpp' -o -name '*.cc' -o -name '*.h' -o -name '*.s' -o -name    '*.S' \) -print > ${TARGET_PATH}/cscope.files \
	&& cscope -b -i ${TARGET_PATH}/cscope.files
