gcc -fPIC -g -c -I"${CUBRID}/include" -I"${JAVA_HOME}/include" -I"${JAVA_HOME}/include/linux" JNIExample.c
gcc -shared -o libJNIExample.so JNIExample.o
