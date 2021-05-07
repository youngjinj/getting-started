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
		&& git config --add remote.upstream.fetch +refs/pull/$PR_NUMBER/head:refs/remotes/upstream/pr/$PR_NUMBER \
		&& git fetch upstream \
		&& git checkout -b $CLONE_NAME upstream/pr/$PR_NUMBER
fi

if [[ $CLONE_NAME =~ release-* ]]; then
	RELEASE_VERSION=`echo $CLONE_NAME | awk -F "-" '{print $NF}'`

	cd $HOME/github/$CLONE_NAME \
		&& git fetch upstream \
		&& git checkout -t upstream/release/$RELEASE_VERSION
fi

cd $HOME/github/$CLONE_NAME \
	&& $HOME/bin/init_git.sh
