#!/bin/bash

T_COUNT=10
T_UNIT_COUNT=0

cubrid server restart demodb 
sleep 2

for ((i=500000; i<=3000000; i+=500000)); do
  csql -u dba demodb -C -i hash_${i:0:-4}.sql
  sleep 2

  for ((j=0; j<${T_COUNT}; j++)); do
    echo "#### Hash Join (${i:0:-4}, ${j})"
    csql -u dba demodb -C -i hash_${i:0:-4}.sql | tail -1 | awk -F '\\(|\\)' '{print $2}' | awk '{print $1}' >> hash_${i:0:-4}.out
  done
done

cubrid server stop demodb
