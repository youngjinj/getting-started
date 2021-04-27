#!/bin/bash

if [ ! -d $CUBRID_DATABASES ]; then
        mkdir -p $CUBRID_DATABASES
fi

TMPDIR=$CUBRID/tmp
if [ ! -d $TMPDIR ]; then
        mkdir -p $TMPDIR
fi

CUBRID_TMP=$CUBRID/var/CUBRID_SOCK
if [ ! -d $CUBRID_TMP ]; then
        mkdir -p $CUBRID_TMP
fi

export TMPDIR
export CUBRID_TMP
