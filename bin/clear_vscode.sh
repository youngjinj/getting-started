#!/bin/bash

kill $(ps -ef | grep $HOME/.vscode | grep -v grep | awk '{print $2}')
