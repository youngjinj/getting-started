#!/bin/bash

. $HOME/cubrid.sh

if [ -z "$CUBRID" ]; then
	exit 1
fi

if [ $(cubrid server status | grep demodb | wc -l) -gt 0 ]; then
	cubrid server stop demodb
fi

if [ $(cat $CUBRID/databases/databases.txt | grep demodb | wc -l) -gt 0 ]; then
	cubrid deletedb demodb
	rm -rf $CUBRID/databases/demodb
fi

mkdir -p $CUBRID/databases/demodb/log

cubrid createdb \
	-F $CUBRID/databases/demodb \
	-L $CUBRID/databases/demodb/log \
	--db-volume-size=64M \
	--log-volume-size=64M \
	demodb \
	ko_KR.utf8

for OPTION in "$@"; do
	echo $OPTION

	case $OPTION in
		"loaddb")
			cubrid loaddb \
				-u dba \
				-s $CUBRID/demo/demodb_schema \
				-d $CUBRID/demo/demodb_objects \
				demodb
			;;
		"javasp")

			;;
		*)
			;;
	esac
done
