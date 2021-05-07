#!/bin/bash

REPO=$1

if [ -z "$REPO" ]; then
        REPO=$PWD
fi

cd $REPO \
&& ./build.sh -m release -p $HOME/CUBRID build
