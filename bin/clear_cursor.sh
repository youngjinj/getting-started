#!/bin/bash

kill $(ps -ef | grep $HOME/.cursor-server | grep -v grep | awk '{print $2}')
