#!/bin/bash

if [ $# -ne 2 ]
then
  echo ""
  echo "usage: $0 <target_archive> <target_directory>"
  echo ""
  exit 1
fi

mkdir -p $2
tar -zxvf $1 --strip-components 1 -C $2
