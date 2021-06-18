# .bash_profile

# Get the aliases and functions
if [ -f ~/.bashrc ]; then
	. ~/.bashrc
fi

# User specific environment and startup programs

unset SSH_ASKPASS

alias podman="sudo podman"

export MAKEFLAGS="-j 6"

. $HOME/env/env_locale.sh

. $HOME/cubrid.sh

. $HOME/env/env_java.sh

if [ ! -z $CUBRID ]; then
	. $HOME/env/env_cubrid_dir.sh
fi
