#!/bin/bash

echo "create table t1 (c1 varchar, c2 varchar, c3 varchar, c4 varchar, c5 varchar, c6 varchar, c7 varchar, c8 datetime, c9 datetime);" >> cubrid_create.sql
# echo "create table t1 (c1 varchar2(4000), c2 varchar2(4000), c3 varchar2(4000), c4 varchar2(4000), c5 varchar2(4000), c6 varchar2(4000), c7 varchar2(4000), c8 date, c9 date);" >> oracle_create.sql

for ((i=0; i<200000; i++))
do
  echo "insert into t1 values ('`uuidgen`', '`uuidgen`', '`uuidgen`', '`uuidgen`', '`uuidgen`', '`uuidgen`', '`uuidgen`', SYSDATETIME, SYSDATETIME);" >> cubrid_insert.sql
  # echo "insert into t1 values ('`uuidgen`', '`uuidgen`', '`uuidgen`', '`uuidgen`', '`uuidgen`', '`uuidgen`', '`uuidgen`', SYSDATE, SYSDATE);" >> oracle_insert.sql
done
