set nocompatible              " be iMproved, required

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
