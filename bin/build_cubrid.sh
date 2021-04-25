#!/bin/bash

REPO=$1

if [ -z "$REPO" ]; then
        REPO=$PWD
fi

cd $REPO \
&& ./build.sh -m debug -p /home/cubrid/CUBRID build
