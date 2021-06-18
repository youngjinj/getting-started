# CentOS 8
sudo dnf -y module disable container-tools
sudo dnf -y install 'dnf-command(copr)'
sudo dnf -y copr enable rhcontainerbot/container-selinux
sudo curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/CentOS_8/devel:kubic:libcontainers:stable.repo

# OPTIONAL FOR RUNC USERS: crun will be installed by default. Install runc first if you prefer runc
sudo dnf -y --refresh install runc

# Install Podman
sudo dnf -y --refresh install podman
