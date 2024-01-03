#!/bin/bash

if [ $# -ne 2 ]; then
  echo "Usage: $0 <version> <test_count>"
  exit
fi

T_VERSION=$1
T_COUNT=$2

T_OUTPUT=$1-cs.out

T_QUERY="select /*+ ordered */ count (tb.c4) from t1 ta, t2 tb where ta.c1 = tb.c1 and ta.c2 = tb.c2 and ta.c3 = tb.c3 and ta.c4 = tb.c4 and tb.c5 = md5 ('1')"

echo "#### Start. (${T_VERSION}, client/server, ${T_COUNT})"

cubrid server restart demodb

csql -u dba demodb -C -c "${T_QUERY}"

for ((i=0; i<${T_COUNT}; i++)); do
  csql -u dba demodb -C -c "${T_QUERY}" | tail -1 | awk -F '\\(|\\)' '{print $2}' | awk '{print $1}' >> ${T_OUTPUT}
done

cubrid server stop demodb

echo "#### End.   (${T_VERSION}, client/server, ${T_COUNT})"
