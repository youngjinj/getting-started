#!/bin/bash

TARGET_PATH=$1

if [ -z ${TARGET_PATH} ]; then
        TARGET_PATH=${PWD}
fi

if [ ! -d ${TARGET_PATH}/cubridmanager/server/external/jsoncpp ]; then
        echo "ERROR: It was run in the wrong path."
        exit
fi

set -x 

cd ${TARGET_PATH}/cubridmanager/server/external/jsoncpp

g++ -m64 -o src/json_reader.o -c -Wall -Iinclude src/json_reader.cpp
g++ -m64 -o src/json_value.o -c -Wall -Iinclude src/json_value.cpp
g++ -m64 -o src/json_writer.o -c -Wall -Iinclude src/json_writer.cpp

ar rc src/libjson.a src/*.o
ranlib src/libjson.a

rm -f ${TARGET_PATH}/cubridmanager/server/external/jsoncpp/linux_64/lib/libjson.a
mv src/libjson.a ${TARGET_PATH}/cubridmanager/server/external/jsoncpp/linux_64/lib/libjson.a

set +x
