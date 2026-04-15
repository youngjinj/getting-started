#!/bin/bash

TARGET_PATH=$1

if [ -z ${TARGET_PATH} ]; then
        TARGET_PATH=${PWD}
fi

if [ ! -e ${TARGET_PATH}/.gitignore ]; then
        exit
fi

if [ `grep Youngjinj ${TARGET_PATH}/.gitignore | wc -l` != 0 ]; then
        exit
fi

cat <<EOF >> ${TARGET_PATH}/.gitignore

## Youngjinj
external/
jdbc/
java/
csql.access
csql.err

# Never commit sensitive credentials to git
*.key
*.pem
*.cert

### OMC (Open Model Context) Specific ###
.omc/sessions/
.omc/state/
.omc/*.log
.omc/cache/
EOF
