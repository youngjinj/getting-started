#!/bin/bash

if [ $# -ne 2 ]; then
  echo "Usage: $0 <version> <test_count>"
  exit
fi

T_VERSION=$1
T_COUNT=$2

T_OUTPUT=$1-cs.out

# T_QUERY="select /*+ ordered */ count (tb.c4) from t1 ta, t2 tb where ta.c1 = tb.c1 and ta.c2 = tb.c2 and ta.c3 = tb.c3 and ta.c4 = tb.c4 and tb.c6 = md5 ('1')"
# T_QUERY="select /*+ ordered */ count (tb.c6) from t1 ta, t2 tb where ta.c1 = tb.c1 and ta.c2 = tb.c2 and ta.c3 = tb.c3 and tb.c6 = md5 ('3')"
# T_QUERY="select /*+ ordered */ count (tb.c6) from t1 ta, t2 tb where ta.c1 = tb.c1 and ta.c2 = tb.c2 and ta.c3 = tb.c3 and ta.c4 = tb.c4 and ta.c5 = tb.c5 and tb.c7 = repeat ('2', 8) and tb.c9 = repeat ('2', 8)";
# T_QUERY="select /*+ ordered */ count (tb.c6) from t1 ta, t2 tb where ta.c1 = tb.c1 and ta.c2 = tb.c2 and ta.c3 = tb.c3 and ta.c4 = tb.c4 and ta.c5 = tb.c5 and tb.c7 = -111 and tb.c9 = -1"

# T_QUERY="insert into t2 select c1, c2, c3, c4, c5, rand () from t1";
T_QUERY="insert into t2 (c1, c2, c3, c4, c5) select * from t1"

T_QUERY_CACHE="select * from t1 limit 99999, 1";
# T_QUERY_CACHE=${T_QUERY}

echo "#### Start. (${T_VERSION}, client/server, ${T_COUNT})"

cubrid server restart demodb

csql -u dba demodb -C -c "${T_QUERY_CACHE}"

for ((i=0; i<${T_COUNT}; i++)); do
  csql -u dba demodb -C -i prepare.sql

  csql -u dba demodb -C -c "${T_QUERY}" | tail -1 | awk -F '\\(|\\)' '{print $2}' | awk '{print $1}' >> ${T_OUTPUT}
done

cubrid server stop demodb

cubrid vacuumdb demodb -S

echo "#### End.   (${T_VERSION}, client/server, ${T_COUNT})"
