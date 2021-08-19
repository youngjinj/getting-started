#!/bin/bash

if [ $# != 1 ]; then
	echo "$# is Illegal number of parameters."
	echo "Usage: $0 <CLONE_NAME>"
	exit
fi

CLONE_NAME=$1
CLONE_NAME=${CLONE_NAME,,}

CANONICAL_PATH=`readlink -f $(dirname ${BASH_SOURCE})`

TARGET_CLONE_PATH=${HOME}/github/${CLONE_NAME}

if [ -d ${HOME}/github/${CLONE_NAME} ]; then
	echo "ERROR: Same name exists."
	exit
fi

${CANONICAL_PATH}/global_config_git.sh

# git clone https://github.com/youngjinj/cubrid.git ${TARGET_CLONE_PATH}
git clone --recursive git@github.com:youngjinj/cubrid.git ${TARGET_CLONE_PATH} \

cd ${TARGET_CLONE_PATH} \
	&& git remote add upstream https://github.com/CUBRID/cubrid.git \
	&& rm -rf ${TARGET_CLONE_PATH}/cubridmanager \
	&& git rm cubridmanager \
	&& git fetch upstream
	
	# && git merge upstream/develop \
	# && git push

	# && git remote set-url origin https://youngjinj@github.com/youngjinj/cubrid.git \
	# && git push

if [[ ${CLONE_NAME} =~ pr-* ]]; then
	PR_NUMBER=`echo ${CLONE_NAME} | awk -F "-" '{print $NF}'`

	cd ${TARGET_CLONE_PATH} \
		&& git config --add remote.upstream.fetch +refs/pull/${PR_NUMBER}/head:refs/remotes/upstream/pr/${PR_NUMBER} \
		&& git fetch upstream \
		&& git checkout -b ${CLONE_NAME} upstream/pr/${PR_NUMBER}
fi

if [[ ${CLONE_NAME} =~ cbrd-* ]]; then
	git checkout ${CLONE_NAME^^} \
	&& git fetch upstream \
	&& git merge upstream/develop
fi

if [[ ${CLONE_NAME,,} =~ release-* ]]; then
	RELEASE_VERSION=`echo ${CLONE_NAME} | awk -F "-" '{print $NF}'`

	cd ${TARGET_CLONE_PATH} \
		&& git fetch upstream \
		&& git checkout -t upstream/release/${RELEASE_VERSION}
fi

${CANONICAL_PATH}/init_git.sh ${TARGET_CLONE_PATH}
