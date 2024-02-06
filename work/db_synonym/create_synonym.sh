echo "" > create_synonym.sql

for var1 in {1..10}
do
  for var2 in {1..10000}
  do
    echo "create synonym synonym_${var1}_${var2} for db_root;" >> create_synonym.sql
  done
  echo "commit;" >> create_synonym.sql
done
