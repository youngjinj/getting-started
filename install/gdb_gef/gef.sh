#!/bin/bash

ln -sf ${HOME}/github/getting-started/install/gdb_gef/.gdbinit ${HOME}/.gdbinit
ln -sf ${HOME}/github/getting-started/install/gdb_gef/.gef.rc ${HOME}/.gef.rc

git clone https://github.com/hugsy/gef.git ${HOME}/github/gef
git clone https://github.com/hugsy/gef-legacy.git ${HOME}/github/gef-legacy
git clone https://github.com/hugsy/gef-extras.git ${HOME}/github/gef-extras
