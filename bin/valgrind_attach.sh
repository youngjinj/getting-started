valgrind --tool=callgrind \
         --instr-atstart=no \
         --trace-children=yes \
         --trace-children-skip='/bin/sh,*/bin/cub_master,*/bin/cub_javasp' \
         cubrid server restart demodb

csql -u dba demodb -c 'select /*+ recompile ordered */ t2.c1, t2.c2 from t1 t1, t2 t2 where t1.c1 = t2.c1 and t2.c2 = 100001'

callgrind_control -i on
csql -u dba demodb -c 'select /*+ recompile ordered */ t2.c1, t2.c2 from t1 t1, t2 t2 where t1.c1 = t2.c1 and t2.c2 = 100001'
callgrind_control -i off

cubrid service stop

