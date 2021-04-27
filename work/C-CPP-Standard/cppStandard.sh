echo | gcc -x c++ -E -dM - | grep "STRICT_ANSI\|__cplusplus"
