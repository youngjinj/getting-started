#!/bin/bash

podman run -d --name=lawrence -h lawrence --net=host --privileged --security-opt label=disable centos:7 /sbin/init

