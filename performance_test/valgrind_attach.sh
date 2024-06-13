valgrind --tool=callgrind \
         --instr-atstart=no \
         --trace-children=yes \
         --trace-children-skip='/bin/sh,*/bin/cub_master,*/bin/cub_javasp' \
         cubrid server restart demodb

T_QUERY="SELECT /*+ USE_HASH */ COUNT (B.C5) FROM T1 A, T2 B WHERE A.C1 = B.C1 AND A.C2 = B.C2 AND A.C3 = B.C3 AND A.C4 = B.C4 AND A.C5 = B.C5;"
# T_QUERY="select /*+ recompile ordered use_nl */ count(*) from t111 ta, t222 tb where ta.col1=tb.col1 and tb.col3 = 1"

csql -u dba demodb -c "${T_QUERY}"

callgrind_control -i on
csql -u dba demodb -c "${T_QUERY}"
callgrind_control -i off

cubrid service stop

