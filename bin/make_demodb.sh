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
else
	rm -rf $CUBRID/databases/demodb
fi

mkdir -p $CUBRID/databases/demodb/log

cubrid createdb \
	-F $CUBRID/databases/demodb \
	-L $CUBRID/databases/demodb/log \
	demodb \
	ko_KR.utf8

for OPTION in "$@"; do
	case $OPTION in
		"loaddb")
			cubrid loaddb \
				-u dba \
				-s $CUBRID/demo/demodb_schema \
				-d $CUBRID/demo/demodb_objects \
				demodb
			;;
		"loaddb-compat")
			cubrid loaddb \
				-u dba \
				-s $CUBRID/demo/demodb_schema \
				-d $CUBRID/demo/demodb_objects \
				--no-user-specified-name \
				demodb
			;;
		"javasp")

			;;
		*)
			;;
	esac
done
