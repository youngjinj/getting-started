cat << EOF >> $CUBRID/conf/cubrid.conf
create_table_reuseoid=n
dont_reuse_heap_file=y
EOF
