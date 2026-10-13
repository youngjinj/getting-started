valgrind --tool=callgrind \
	 --cache-sim=yes \
         --instr-atstart=no \
         --trace-children=yes \
         --trace-children-skip='/bin/sh,*/bin/cub_master,*/bin/cub_javasp,*/bin/cub_pl' \
         cubrid server restart demodb

csql -u dba demodb -i valgrind_attach.sql

callgrind_control -i on

csql -u dba demodb -i valgrind_attach.sql

callgrind_control -i off

cubrid service stop
