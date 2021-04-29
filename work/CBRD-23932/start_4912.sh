#!/bin/bash

VERSION=`ls -al $CUBRID_DATABASES | awk -F '/' '{printf $NF}'`

if [ -d $HOME/github/backup/conf/$VERSION ]; then
	cp -v $HOME/github/backup/conf/$VERSION/* $CUBRID/conf/	
fi

cubrid service restart
cubrid server start 4912
