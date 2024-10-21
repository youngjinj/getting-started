#!/bin/bash

if [ $# -ne 2 ]; then
  echo "Usage: $0 <version> <test_count>"
  exit
fi

T_VERSION=$1
T_COUNT=$2

T_OUTPUT=$1-cs.out

# T_QUERY="insert into t2 select c1, c2, c3, c4, c5, rand () from t1";
T_QUERY="insert into t2 (c1, c2, c3, c4, c5) select * from t1"

T_QUERY_CACHE="select * from t1 limit 99999, 1";
# T_QUERY_CACHE=${T_QUERY}

echo "#### Start. (${T_VERSION}, client/server, ${T_COUNT})"

cubrid server restart demodb

# csql -u dba demodb -C -i t_cs.sql

for ((i=0; i<${T_COUNT}; i++)); do
# csql -u dba demodb -C -i prepare.sql

  csql -u dba demodb -C -i t_cs.sql | tail -1 | awk -F '\\(|\\)' '{print $2}' | awk '{print $1}' >> ${T_OUTPUT}
done

cubrid server stop demodb

# cubrid vacuumdb demodb -S

echo "#### End.   (${T_VERSION}, client/server, ${T_COUNT})"
