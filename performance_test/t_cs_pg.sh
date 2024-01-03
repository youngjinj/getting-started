#!/bin/bash

if [ $# -ne 2 ]; then
  echo "Usage: $0 <version> <test_count>"
  exit
fi

T_VERSION=$1
T_COUNT=$2

T_OUTPUT=$1-cs-pg.out

# T_QUERY="/*+ Leading((ta tb)) NestLoop(ta tb) SeqScan(ta) IndexScan(tb) */ select count (tb.c4) from t1 ta, t2 tb where ta.c1 = tb.c1 and ta.c2 = tb.c2 and ta.c3 = tb.c3 and ta.c4 = tb.c4 and tb.c5 = md5 ('1')"
T_QUERY="/*+ Leading((ta tb)) SeqScan(ta) IndexScan(tb) */ select count (tb.c4) from t1 ta, t2 tb where ta.c1 = tb.c1 and ta.c2 = tb.c2 and ta.c3 = tb.c3 and ta.c4 = tb.c4 and tb.c5 = md5 ('1')"

echo "#### Start. (${T_VERSION}, client/server - postgres, ${T_COUNT})"

pg_ctl -D /home/youngjinj/pgsql/data -l /home/youngjinj/pgsql/logfile restart

psql test -c "\timing" -c "${T_QUERY}"

for ((i=0; i<${T_COUNT}; i++)); do
  psql test -c "\timing" -c "${T_QUERY}" | tail -1 | awk '{print $2/1000}' >> ${T_OUTPUT}
done

pg_ctl -D /home/youngjinj/pgsql/data stop

echo "#### End.   (${T_VERSION}, client/server - postgres, ${T_COUNT})"
