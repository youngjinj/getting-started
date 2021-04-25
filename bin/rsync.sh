#!/bin/bash

if [ $# != 2 ]; then
	echo -e "\nUsage: $0 SRC DEST\n"
	exit 1
fi

SRC=$1
DEST=$2

if [ `echo $DEST | rev | cut -c -1` != "/" ]; then
	$DEST=$DEST/
fi

if [[ $DEST ~= *$SRC ]]; then
	$DEST=$DEST$SRC
fi

echo "rsync -avhP --delete --delete-excluded $SRC $DEST"
