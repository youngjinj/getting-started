#!/bin/bash

TEMP_FILE_ARRAY=(        \
	"csql.err"       \
	"csql.access"    \
	"*_loaddb.log"   \
	"*_unloaddb.log" \
)

for TEMP_FILE in "${TEMP_FILE_ARRAY[@]}"; do
	find $HOME -name $TEMP_FILE
	find $HOME -name $TEMP_FILE -exec rm -i {} \;
done
