#!/bin/bash

source /opt/intel/oneapi/setvars.sh

# vtune-backend --reset-passphrase

# vtune-backend --web-port=9000 --allow-remote-access --enable-server-profiling --data-directory ${HOME}/vtune_projects

vtune-backend --web-port=9000 --enable-server-profiling &

# https://127.0.0.1:9000/ui/
