#!/bin/bash

# /etc/firewalld/zones/public.xml

# user or registered ports: 1024-49151
sudo firewall-cmd --permanent --zone=public --add-port=1024-49151/tcp

# dynamic / private / ephemeral ports: 49152-65535
sudo firewall-cmd --permanent --zone=public --add-port=49152-65535/tcp

sudo firewall-cmd --reload
