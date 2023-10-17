# set -x

# cubrid service stop

# cubrid deletedb demodb
sed -i /^demodb/d $CUBRID/databases/databases.txt
rm -rf $CUBRID/databases/demodb
rm -rf $CUBRID/databases/demodb_*

mkdir -p $CUBRID/databases/demodb/log
cubrid createdb \
      -F $CUBRID/databases/demodb \
      -L $CUBRID/databases/demodb/log \
      demodb \
      ko_KR.utf8

cubrid addvoldb --db-volume-size=512M -p temp demodb -S

if [ -f $CUBRID/conf/cubrid.conf__backup ]; then
  cp $CUBRID/conf/cubrid.conf__backup $CUBRID/conf/cubrid.conf
else
  cp $CUBRID/conf/cubrid.conf $CUBRID/conf/cubrid.conf__backup
fi

cat << EOF >> $CUBRID/conf/cubrid.conf
data_buffer_size=1G
temp_file_memory_size_in_pages=20
temp_file_max_size_in_pages=0
EOF

sed -i 's/^max_clients=.*/max_clients=200/g' $CUBRID/conf/cubrid.conf

sed -i '/%BROKER1/,/$p/s/^MIN_NUM_APPL_SERVER.*$/MIN_NUM_APPL_SERVER     =40/g' $CUBRID/conf/cubrid_broker.conf

csql -u dba demodb -S -i init.sql

cubrid vacuumdb demodb -S
