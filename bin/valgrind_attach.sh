valgrind --tool=callgrind \
         --instr-atstart=no \
         --trace-children=yes \
         --trace-children-skip='/bin/sh,*/bin/cub_master,*/bin/cub_javasp' \
         cubrid server restart demodb

T_QUERY="select col3, max(col2) from t111 group by col3"
# T_QUERY="select /*+ recompile ordered use_nl */ count(*) from t111 ta, t222 tb where ta.col1=tb.col1 and tb.col3 = 1"

csql -u dba demodb -c "${T_QUERY}"

callgrind_control -i on
csql -u dba demodb -c "${T_QUERY}"
callgrind_control -i off

cubrid service stop

