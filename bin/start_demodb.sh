#!/bin/bash

VERSION=`ls -al ${CUBRID_DATABASES} | awk -F '/' '{printf $NF}'`

if [ -d ${HOME}/github/getting-started/cubrid/conf/${VERSION} ]; then
	cp -v ${HOME}/github/getting-started/cubrid/conf/${VERSION}/* ${CUBRID}/conf/	
fi

cubrid service restart
cubrid server start demodb
