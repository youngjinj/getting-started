cubrid service start
cubrid server start demodb

CSQL_PIDS=""
ALL_SUCCESS_YN="Y"

for var in {1..10}
do
  csql -u dba demodb -c "create user user_${var};"
  nohup csql -u user_${var} demodb -i create_synonym.sql --no-auto-commit &
  CP_PIDS+=($!)
done

for i in {1..10}; do
  if wait ${CSQL_PIDS[$i]}; then
    echo "user_${var} : Ok"
  else
    ALL_SUCCESS_YN="N"
    echo "user_${var} : Fail"
  fi
done

if [ $ALL_SUCCESS_YN == "Y" ]; then
  echo "All : Ok"
else
  echo "All : Fail"
fi

csql -u dba demodb -c "show all indexes capacity of _db_synonym;" -l
