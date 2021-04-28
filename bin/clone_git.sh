#!/bin/bash

REPO=$1

if [ -z $REPO ]; then
	exit
fi

if [ -e $HOME/github/$REPO ]; then
	echo "ERROR: Same name exists."
	exit
fi

cd $HOME/github \
&& git clone https://github.com/youngjinj/cubrid.git $REPO \
&& cd $REPO \
&& git remote add upstream https://github.com/CUBRID/cubrid.git \
&& git fetch upstream \
&& git merge upstream/develop \
&& git remote set-url origin https://youngjinj@github.com/youngjinj/cubrid.git \
&& git push \
&& $HOME/bin/init_git.sh
