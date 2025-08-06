#!/bin/bash

TARGET_PATH=$1

if [ -z ${TARGET_PATH} ]; then
        TARGET_PATH=${PWD}
fi

CANONICAL_PATH=`readlink -f $(dirname ${BASH_SOURCE})`

CURRENT_BRANCH=`git branch | grep "^*" | awk '{print $NF}'`

if [ "${CURRENT_BRANCH}" == "develop" ]; then
	if [ `git branch -a | grep "${PWD##/*/}" | wc -l` != 0 ]; then
		git checkout ${PWD##/*/}
	fi
fi

if [ ! -e ${TARGET_PATH}/.vscode ]; then
	cp -r ${CANONICAL_PATH}/../install/vscode/.vscode ${TARGET_PATH}

	# CORE_COUNT=`grep -c processor /proc/cpuinfo | awk '{print $NF/2}'`
	CORE_COUNT=$(nproc)

	sed -i "s/\"cmake.parallelJobs\": 6/\"cmake.parallelJobs\": ${CORE_COUNT}/" ${TARGET_PATH}/.vscode/settings.json
fi

# ${CANONICAL_PATH}/build_jsoncpp.sh ${TARGET_PATH}
# ${CANONICAL_PATH}/build_libevent.sh ${TARGET_PATH}

if [ ! -e ${TARGET_PATH}/.github/workflows/google-java-format-1.7-all-deps.jar ]; then
	wget https://github.com/google/google-java-format/releases/download/google-java-format-1.7/google-java-format-1.7-all-deps.jar

	mv google-java-format-1.7-all-deps.jar ${TARGET_PATH}/.github/workflows
fi

# deprecated
exit

${CANONICAL_PATH}/make_ctags_cscope.sh ${TARGET_PATH}
