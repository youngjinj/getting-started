# .bashrc

# Source global definitions
if [ -f /etc/bashrc ]; then
	. /etc/bashrc
fi

# User specific environment
if ! [[ "$PATH" =~ "$HOME/.local/bin:$HOME/bin:" ]]
then
    PATH="$HOME/.local/bin:$HOME/bin:$PATH"
fi
export PATH

# Uncomment the following line if you don't like systemctl's auto-paging feature:
# export SYSTEMD_PAGER=

# User specific aliases and functions

unset SSH_ASKPASS

alias podman="sudo podman"

export MAKEFLAGS="-j 6"

. $HOME/env/env_locale.sh

. $HOME/cubrid.sh

. $HOME/env/env_java.sh

if [ ! -z $CUBRID ]; then
        . $HOME/env/env_cubrid_dir.sh
fi
