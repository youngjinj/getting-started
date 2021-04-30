#!/bin/bash

CLONE_NAME=$1

if [ -z $CLONE_NAME ]; then
	exit
fi

if [ -d $HOME/github/$CLONE_NAME ]; then
	echo "ERROR: Same name exists."
	exit
fi

cd $HOME/github \
	&& git clone https://github.com/youngjinj/cubrid.git $CLONE_NAME \
	&& cd $CLONE_NAME \
	&& git remote add upstream https://github.com/CUBRID/cubrid.git \
	&& git fetch upstream \
	&& git merge upstream/develop \
	&& git remote set-url origin https://youngjinj@github.com/youngjinj/cubrid.git \
	&& git push

if [[ $CLONE_NAME =~ pr-* ]]; then
	PR_NUMBER=`echo $CLONE_NAME | awk -F "-" '{print $NF}'`

	cd $HOME/github/$CLONE_NAME \
		&& git fetch upstream pull/$PR_NUMBER/head:$CLONE_NAME \
		&& git checkout $CLONE_NAME
fi

cd $HOME/github/$CLONE_NAME \
	&& $HOME/bin/init_git.sh
