#!/bin/bash

if [ $# != 2 ]; then
	echo -e "\nUsage: $0 SRC DEST\n"
	exit 1
fi

SRC=$1
if [ `echo $SRC | rev | cut -c -1` != "/" ]; then
	$SRC=$SRC/
fi

DEST=$2
if [ `echo $DEST | rev | cut -c -1` != "/" ]; then
	$DEST=$DEST/
fi

rsync -avhP --delete --delete-excluded $SRC $DEST
