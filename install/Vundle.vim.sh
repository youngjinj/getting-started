#!/bin/bash

git clone https://github.com/VundleVim/Vundle.vim.git $HOME/.vim/bundle/Vundle.vim
vim -E -u $HOME/.vimrc +PluginInstall +qall -V || true
