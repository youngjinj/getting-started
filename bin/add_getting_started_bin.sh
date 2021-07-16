#!/bin/bash

if [ ! -e ${HOME}/.custom_profile ]; then
	exit
fi

# if [ `grep "Getting Started" ${HOME}/.custom_profile | wc -l` != 0 ]; then
#	exit
#fi

echo $'
# Getting Started
if [ -d "${HOME}/github/getting-started/bin" ]; then
	PATH=${HOME}/github/getting-started/bin:${PATH}
	export PATH
fi

if [ -e ${HOME}/cubrid.sh ] && [ -e `readlink -f ${HOME}/cubrid.sh` ]; then
	source ${HOME}/cubrid.sh
fi' >> ${HOME}/.custom_profile
