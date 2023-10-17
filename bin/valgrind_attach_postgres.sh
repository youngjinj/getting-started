valgrind --tool=callgrind \
         --instr-atstart=no \
         --trace-children=yes \
         pg_ctl restart -D /home/youngjinj/pgsql/data

psql test -c "/*+ Leading((ta tb)) NestLoop(ta tb) SeqScan(ta) IndexScan(tb) */ select count (ta.dummy1) from t1 ta, t2 tb where ta.c1 = tb.c1 and ta.c2 = tb.c2 and tb.c3 = 1;"

callgrind_control -i on
psql test -c "/*+ Leading((ta tb)) NestLoop(ta tb) SeqScan(ta) IndexScan(tb) */ select count (ta.dummy1) from t1 ta, t2 tb where ta.c1 = tb.c1 and ta.c2 = tb.c2 and tb.c3 = 1;"
callgrind_control -i off

pg_ctl stop -D /home/youngjinj/pgsql/data
