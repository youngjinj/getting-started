#!/bin/bash

gdb cub_server $(ps -fU $(id -u) | grep -v grep | grep cub_server | awk '{print $2}')
