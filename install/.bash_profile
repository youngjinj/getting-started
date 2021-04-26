# .bash_profile

# Get the aliases and functions
if [ -f ~/.bashrc ]; then
	. ~/.bashrc
fi

# User specific environment and startup programs

PATH=$PATH:$HOME/.local/bin:$HOME/bin

export PATH

alias podman="sudo podman"
alias yum="sudo yum"

export MAKEFLAGS="-j 12"

. $HOME/env/env_locale.sh

. $HOME/cubrid.sh

. $HOME/env/env_java.sh

if [ ! -z $CUBRID ]; then
        . $HOME/env/env_cubrid_dir.sh
fi
