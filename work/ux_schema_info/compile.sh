gcc -o ux_schema_info ux_schema_info.c -I$CUBRID/include -I$CUBRID/cci/include -L$CUBRID/lib -L$CUBRID/cci/lib -lnsl -lcascci
gcc -o test_cci_schema_info test_cci_schema_info.c -I$CUBRID/include -I$CUBRID/cci/include -L$CUBRID/lib -L$CUBRID/cci/lib -lnsl -lcascci -g
