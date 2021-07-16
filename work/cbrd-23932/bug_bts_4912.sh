#!/bin/bash

. $init_path/init.sh

init test

set -x

dbname=4912


cubrid_createdb $dbname
sleep 2

cubrid loaddb -s nsight_schema $dbname
cubrid loaddb -i nsight_indexes $dbname
cubrid loaddb -d nsight_objects $dbname

cubrid server start $dbname
sleep 2

count1="`csql -u dba -c "SELECT host_id, avg_cpu_used_rto FROM foo WHERE log_ocr_ymdt BETWEEN '2011-02-21 13:45:00' AND '2011-02-21 13:45:59' AND host_id IN ( '00:30:48:5C:9E:28', '00:24:E8:7A:A3:4B' );" $dbname | awk '(NR==6) {print $2}'`"


csql -u dba -i $dbname.sql $dbname

count2="`csql -u dba -c "select a1 from aa where a1 in ('0', '1');" $dbname | awk '(NR==6) {print $1}'`"

if [ ! -z $count1 ] && [ ! -z $count2 ] && [ $count1 -eq 1 ] && [ "$count2" = "'1'" ]
then
	write_ok
else
	write_nok
fi


cubrid server stop $dbname
sleep 2
cubrid deletedb $dbname
sleep 2

rm -rf lob
rm *.err

finish
