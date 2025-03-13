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
