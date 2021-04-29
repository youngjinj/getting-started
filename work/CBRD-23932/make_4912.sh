#!/bin/bash

IS_LOAD=1

. $HOME/cubrid.sh

if [ -z "$CUBRID" ]; then
	exit 1
fi

if [ $(cubrid server status | grep 4912 | wc -l) -gt 0 ]; then
	cubrid server stop 4912
fi

if [ $(cat $CUBRID/databases/databases.txt | grep 4912 | wc -l) -gt 0 ]; then
	cubrid deletedb 4912
	rm -rf $CUBRID/databases/4912
fi

mkdir -p $CUBRID/databases/4912/log

cubrid createdb \
	-F $CUBRID/databases/4912 \
	-L $CUBRID/databases/4912/log \
	--db-volume-size=64M \
	--log-volume-size=64M \
	4912 \
	ko_KR.utf8

if [ $IS_LOAD == 1 ]; then
	cubrid loaddb \
		-u dba \
		-s $HOME/work/CBRD-23932/nsight_schema \
		-d $HOME/work/CBRD-23932/nsight_objects \
		-i $HOME/work/CBRD-23932/nsight_indexes \
		4912
fi
