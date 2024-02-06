gcc -g -o schema_info schema_info.c -m64 -I${CUBRID}/cci/include -lnsl ${CUBRID}/cci/lib/libcascci.so -lpthread
