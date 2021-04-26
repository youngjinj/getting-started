#!/bin/bash

git clone https://github.com/oracle/docker-images.git $HOME/github/oracle

# $HOME/github/oracle/docker-images/OracleDatabase/SingleInstance/dockerfiles/19.3.0/LINUX.X64_193000_db_home.zip

cd $HOME/github/oracle/docker-images/OracleDatabase/SingleInstance/dockerfiles \
	&& ./buildContainerImage.sh -v 19.3.0 -e 
