#!/bin/bash

T_COUNT=10
T_UNIT_COUNT=0

cubrid server restart demodb
sleep 2

for ((i=200000; i<=1000000; i+=200000)); do
  csql -u dba demodb -C -i nl_${i:0:-4}.sql
  sleep 2

  for ((j=0; j<${T_COUNT}; j++)); do
    echo "#### Nested Loop Join (${i:0:-4}, ${j})"
    csql -u dba demodb -C -i nl_${i:0:-4}.sql | tail -1 | awk -F '\\(|\\)' '{print $2}' | awk '{print $1}' >> nl_${i:0:-4}.out
  done

  csql -u dba demodb -C -i sm_${i:0:-4}.sql
  sleep 2

  for ((j=0; j<${T_COUNT}; j++)); do
    echo "#### Sort Merge Join (${i:0:-4}, ${j})"
    csql -u dba demodb -C -i sm_${i:0:-4}.sql | tail -1 | awk -F '\\(|\\)' '{print $2}' | awk '{print $1}' >> sm_${i:0:-4}.out
  done

  csql -u dba demodb -C -i hash_${i:0:-4}.sql
  sleep 2

  for ((j=0; j<${T_COUNT}; j++)); do
    echo "#### Hash Join (${i:0:-4}, ${j})"
    csql -u dba demodb -C -i hash_${i:0:-4}.sql | tail -1 | awk -F '\\(|\\)' '{print $2}' | awk '{print $1}' >> hash_${i:0:-4}.out
  done

  csql -u dba demodb -C -i nl_cnt_only_${i:0:-4}.sql
  sleep 2

  for ((j=0; j<${T_COUNT}; j++)); do
    echo "#### Nested Loop Join (Couny Only) (${i:0:-4}, ${j})"
    csql -u dba demodb -C -i nl_cnt_only_${i:0:-4}.sql | tail -1 | awk -F '\\(|\\)' '{print $2}' | awk '{print $1}' >> nl_cnt_only_${i:0:-4}.out
  done

  csql -u dba demodb -C -i sm_cnt_only_${i:0:-4}.sql
  sleep 2

  for ((j=0; j<${T_COUNT}; j++)); do
    echo "#### Sort Merge Join (Count Only) (${i:0:-4}, ${j})"
    csql -u dba demodb -C -i sm_cnt_only_${i:0:-4}.sql | tail -1 | awk -F '\\(|\\)' '{print $2}' | awk '{print $1}' >> sm_cnt_only_${i:0:-4}.out
  done

  csql -u dba demodb -C -i hash_cnt_only_${i:0:-4}.sql
  sleep 2

  for ((j=0; j<${T_COUNT}; j++)); do
    echo "#### Hash Join (Count Only) (${i:0:-4}, ${j})"
    csql -u dba demodb -C -i hash_cnt_only_${i:0:-4}.sql | tail -1 | awk -F '\\(|\\)' '{print $2}' | awk '{print $1}' >> hash_cnt_only_${i:0:-4}.out
  done
done

cubrid server stop demodb
