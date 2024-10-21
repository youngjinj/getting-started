valgrind --tool=callgrind \
         --instr-atstart=no \
         --trace-children=yes \
         --trace-children-skip='/bin/sh,*/bin/cub_master,*/bin/cub_javasp' \
         cubrid server restart demodb

csql -u dba demodb -i valgrind_attach.sql

callgrind_control -i on

csql -u dba demodb -i valgrind_attach.sql

callgrind_control -i off

cubrid service stop
