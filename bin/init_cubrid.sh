#!/bin/bash

# Debug: v11.0, v10.2, v10.1, v9.3, ...
# Release: 11.0.0.0248, 10.2.0.8797, 10.1.5.7809, 9.3.6.0002, ...
VERSION=$1

if [ -z ${VERSION} ]; then
	VERSION="v11.2"
fi

if [ -f ${HOME}/cubrid.sh ]; then
	. ${HOME}/cubrid.sh
	cubrid service stop
fi

rm -rf ${HOME}/CUBRID

# If release version.
if [[ `echo ${VERSION} | grep -e "^[^v].*" | wc -l` > 0 ]]; then
	if [ ! -d ${HOME}/release/CUBRID-${VERSION} ]; then
		echo "Error: The release version is not installed."
		exit 1
	fi
	ln -sf ${HOME}/release/CUBRID-${VERSION} ${HOME}/CUBRID
	VERSION=`echo $VERSION | awk -F "." '{print "v"$1"."$2}'`
fi

ln -sf ${HOME}/github/getting-started/cubrid/.cubrid_${VERSION}.sh ${HOME}/cubrid.sh

source ${HOME}/cubrid.sh

if [ ! -d $CUBRID_DATABASES ]; then
        mkdir -p $CUBRID_DATABASES
fi

export TMPDIR=${CUBRID}/tmp
if [ ! -d ${TMPDIR} ]; then
        mkdir -p ${TMPDIR}
fi

export CUBRID_TMP=${CUBRID}/var/CUBRID_SOCK
if [ ! -d ${CUBRID_TMP} ]; then
        mkdir -p ${CUBRID_TMP}
fi

if [ -d ${HOME}/CUBRID/databases ] && [ ! -L ${HOME}/CUBRID/databases ]; then
	rmdir ${HOME}/CUBRID/databases
fi

if [ ! -e ${HOME}/CUBRID/databases ]; then
	mkdir -p ${HOME}/databases
	ln -sf ${HOME}/databases ${HOME}/CUBRID/databases
fi

ls -al ${HOME}/CUBRID
ls -al ${HOME}/CUBRID/databases
