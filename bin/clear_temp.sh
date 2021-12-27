#!/bin/bash

if [ -z $1 ]; then
	COMMAND="ls"
else
	COMMAND=$1
fi

TEMP_FILE_ARRAY=(        \
	"csql.err"       \
	"csql.access"    \
	"*_loaddb.log"   \
	"*_unloaddb.log" \
)

for TEMP_FILE in "${TEMP_FILE_ARRAY[@]}"; do
	find $HOME -name $TEMP_FILE -exec $COMMAND {} \;
done

find $HOME/github -name "core.*" -exec $COMMAND {} \;
