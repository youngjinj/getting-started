cubrid server stop demodb

csql -u dba demodb -S -i create_dummy.sql

for ((i=200000; i<=1000000; i+=200000)); do
  csql -u dba demodb -S -i create_${i:0:-4}.sql
done
