#!/bin/bash

if [ `git config --list | grep "user.name" | wc -l` == 0 ] || [ `git config --list | grep "user.email" | wc -l` == 0 ]; then
        git config --global user.name "youngjinj"
        git config --global user.email "youngjinj@cubrid.com"
fi
