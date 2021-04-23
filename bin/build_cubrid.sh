#!/bin/bash

BUILD_PATH=$1

if [ -z $BUILD_PATH ]; then
	BUILD_PATH=$PWD
fi

cd $BUILD_PATH \
	&& ./build.sh -m debug -p /home/cubrid/CUBRID build
