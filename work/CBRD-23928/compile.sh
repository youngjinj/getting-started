#!/bin/bash

gcc -S -O1 -o function_1.a function.c
gcc -O1 -o function_1 function.c

gcc -S -O2 -finline -o function_fyes_2.a example.c
gcc -S -O2 -o function_2.a function.c
gcc -S -O2 -fno-inline -o function_fno_2.a function.c
gcc -O2 -finline -o function_fyes_2 example.c
gcc -O2 -o function_2 function.c
gcc -O2 -fno-inline -o function_fno_2 function.c
# g++ -O2 -finline -o function_fyes_2 example.cpp
# g++ -O2 -o function_2 function.cpp
# g++ -O2 -fno-inline -o function_fno_2 function.cpp

gcc -S -O2 -o macro_2.a macro.c
gcc -O2 -o macro_2 macro.c

gcc -S -O1 -o example_1.a example.c
gcc -O1 -o example_1 example.c

gcc -S -O2 -finline -o example_fyes_2.a example.c
gcc -S -O2 -o example_2.a example.c
gcc -S -O2 -fno-inline -o example_fno_2.a example.c
gcc -O2 -finline -o example_fyes_2 example.c
gcc -O2 -o example_2 example.c
gcc -O2 -fno-inline -o example_fno_2 example.c
# g++ -O2 -finline -o example_cpp_fyes_2 example.cpp
# g++ -O2 -o example_cpp_2 example.cpp
# g++ -O2 -fno-inline -o example_cpp_fno_2 example.cpp

gcc -O2 -o macro_2 macro_t.c
