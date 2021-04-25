#!/bin/bash

# podman system migrate

podman run -d --name=cubrid -h cubrid --net=host --privileged --security-opt label=disable centos:7 /sbin/init
# podman exec -it cubrid /bin/bash

FROM centos:7

RUN sed 's/enabled=1/enabled=0/' -i /etc/yum/pluginconf.d/fastestmirror.conf

RUN yum install -y epel-release
RUN yum install -y https://rpms.remirepo.net/enterprise/remi-release-7.rpm
RUN yum install -y https://repo.ius.io/ius-release-el7.rpm

RUN yum update -y
RUN yum install -y yum-utils
RUN yum groupinstall -y "Base"
RUN yum groupinstall -y "Development Tools"
RUN yum install -y openssh-server openssh-clients

RUN echo -e "\nPort 10022" >> /etc/ssh/sshd_config
