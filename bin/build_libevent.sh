#!/bin/bash

TARGET_PATH=$1

if [ -z ${TARGET_PATH} ]; then
        TARGET_PATH=${PWD}
fi

if [ ! -d ${TARGET_PATH}/cubridmanager/server/external/libevent ]; then
        echo "ERROR: It was run in the wrong path."
        exit
fi

set -x 

if [ ! -d ${TARGET_PATH}/cubridmanager/server/external/libevent/src ]; then
	mkdir -p ${TARGET_PATH}/cubridmanager/server/external/libevent/src
	tar -zxvf $HOME/install/libevent-release-2.1.4-alpha.tar.gz --strip-components 1 -C ${TARGET_PATH}/cubridmanager/server/external/libevent/src
	cd ${TARGET_PATH}/cubridmanager/server/external/libevent/src
	./autogen.sh
fi

cd /home/cubrid/github/cubrid/cubridmanager/server/external/libevent/src
./configure --prefix=${TARGET_PATH}/cubridmanager/server/external/libevent/linux_64 CFLAGS="$CFLAGS -fPIC" LDFLAGS="$LDFLAGS" --disable-shared --enable-static
make
make install

set +x
