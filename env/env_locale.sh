#!/bin/bash

# localedef -f UTF-8 -i ko_KR ko_KR.utf8
# ln -sf /usr/share/zoneinfo/Asia/Seoul /etc/localtime

LC_ALL=ko_KR.utf8
LANG=ko_KR.utf8
LANGUAGE=ko_KR.utf8

export LC_ALL
export LANG
export LANGUAGE
