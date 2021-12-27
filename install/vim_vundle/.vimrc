set nocompatible              " be iMproved, required
filetype off                  " required

" set the runtime path to include Vundle and initialize
set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()
" alternatively, pass a path where Vundle should install plugins
"call vundle#begin('~/some/path/here')

" let Vundle manage Vundle, required
Plugin 'VundleVim/Vundle.vim'

" The following are examples of different formats supported.
" Keep Plugin commands between vundle#begin/end.
" plugin on GitHub repo
Plugin 'tpope/vim-fugitive'
" plugin from http://vim-scripts.org/vim/scripts.html
" Plugin 'L9'
" Git plugin not hosted on GitHub
Plugin 'git://git.wincent.com/command-t.git'
" git repos on your local machine (i.e. when working on your own plugin)
"Plugin 'file:///home/gmarik/path/to/plugin'
" The sparkup vim script is in a subdirectory of this repo called vim.
" Pass the path to set the runtimepath properly.
Plugin 'rstacruz/sparkup', {'rtp': 'vim/'}
" Install L9 and avoid a Naming conflict if you've already installed a
" different version somewhere else.
" Plugin 'ascenator/L9', {'name': 'newL9'}

Plugin 'altercation/vim-colors-solarized'
Plugin 'vim-airline/vim-airline'
Plugin 'scrooloose/nerdtree'
Plugin 'majutsushi/tagbar'
Plugin 'scrooloose/syntastic'

" All of your Plugins must be added before the following line
call vundle#end()            " required
filetype plugin indent on    " required
" To ignore plugin indent changes, instead use:
"filetype plugin on
"
" Brief help
" :PluginList       - lists configured plugins
" :PluginInstall    - installs plugins; append `!` to update or just :PluginUpdate
" :PluginSearch foo - searches for foo; append `!` to refresh local cache
" :PluginClean      - confirms removal of unused plugins; append `!` to auto-approve removal
"
" see :h vundle for more details or wiki for FAQ
" Put your non-Plugin stuff after this line

set encoding=utf-8
set fileencodings=utf-8
set termencoding=utf-8

if has("syntax")
        syntax on
endif

set backspace=indent,eol,start

set pastetoggle=<F2>

set tabstop=8
set softtabstop=8
set shiftwidth=8
" set expandtab

set cindent
set autoindent
set smartindent

"set number
set ruler

set cursorline
set showmatch

set laststatus=2
" set statusline=%F\ %y%m%r\ %=Line:\ %l/%L\ [%p%%]\ Col:%c\ Buf:%n

" ctags
"if filereadable("/home/cubrid/github/cubrid/tags")
"	set tags =/home/cubrid/github/cubrid/tags
"endif
set tags +=./tags,tags;

" cscope
set csprg=/usr/bin/cscope       "cscopeprg
set cst                         "cscopetag
set csto=0                      "cscopetagorder
set nocsverb                    "nocscopeverbose
"if filereadable("/home/cubrid/github/cubrid/cscope.out")
"	cs add /home/cubrid/github/cubrid/cscope.out
"endif
if filereadable("cscope.out")
	cs add cscope.out
else
	let cscope_file=findfile("cscope.out", ".;")
	let cscope_pre=matchstr(cscope_file, ".*/")
	if filereadable(cscope_file)
		exe "cs add" cscope_file cscope_pre
	endif
endif
set csverb                      "cscopeverbose

" Plugin 'altercation/vim-colors-solarized'
set background=dark
colorscheme solarized

noremap <F3> :set list!<CR>

" Plugin 'scrooloose/nerdtree'
noremap <C-n> :NERDTreeToggle<CR>

" Plugin 'majutsushi/tagbar'
noremap <F8> :TagbarToggle<CR>
