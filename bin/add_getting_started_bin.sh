#!/bin/bash

if [ ! -e ${HOME}/.custom_profile ]; then
	exit
fi

if [ `grep "Getting Started" ${HOME}/.custom_profile | wc -l` != 0 ]; then
	exit
fi

cat <<EOF >> ${HOME}/.custom_profile

# Getting Started
if [ -d "${HOME}/github/getting-started/bin" ]; then
	PATH=${HOME}/github/getting-started/bin:${PATH}
	export PATH
fi
EOF
