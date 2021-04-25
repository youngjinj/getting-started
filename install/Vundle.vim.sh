#!/bin/bash

git clone https://github.com/VundleVim/Vundle.vim.git $HOME/.vim/bundle/Vundle.vim

ln -s $HOME/github/backup/install/.vimrc $HOME/.vimrc

vim -E -u $HOME/.vimrc +PluginInstall +qall -V || true
