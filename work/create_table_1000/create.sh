#!/bin/bash

rm create.sql

for NUM in {1..70}
do
	echo "create table t$NUM (c1 int primary key);" >> create.sql
done

echo "update statistics on catalog classes;" >> create.sql
echo "commit;" >> create.sql
