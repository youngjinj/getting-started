#!/bin/bash

. $HOME/cubrid.sh

cubrid deletedb 4912 ko_KR.utf8

cd $HOME/work/CBRD-23932 \
	&& ./make_4912.sh \
	&& ./start_4912.sh

count1=`csql -u dba 4912 -i count1.sql | awk '(NR==6) {print $2}'`

csql -u dba 4912 -i count1.sql

count2=`csql -u dba 4912 -i count1.sql | awk '(NR==6) {print $1}'`


if [ ! -z $count1 ] && [ ! -z $count2 ] && [ $count1 -eq 1 ] && [ "$count2" = "'1'" ]; then
	write_ok
else
	write_nok
fi
